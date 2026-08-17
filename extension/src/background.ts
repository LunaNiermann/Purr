/**
 * MV3 service worker: owns the approval flow so it survives the popup closing.
 *
 * The popup only kicks things off ("tk-start") and reflects state. The actual
 * create-request → wait-for-phone → fill sequence runs here, driven by
 * back-to-back long-poll fetches that keep the worker alive across the 60 s
 * request window. State lives in chrome.storage.session (see lib/flow.ts) so
 * the popup shows the right thing whenever it reopens.
 */
import { fromB64, open, seal } from "./lib/crypto";
import { setFlow } from "./lib/flow";
import { browserLabel } from "./lib/label";
import { createRequest, waitForAnswer } from "./lib/relay";
import { getPairing, getSettings, rememberMatch } from "./lib/state";

interface RequestPayload {
  kind: "code";
  domain: string;
  browser: string;
  ts: number;
}

type AnswerPayload =
  | { verdict: "approved"; code: string; site?: string; username?: string }
  | { verdict: "denied" }
  | { verdict: "unmatched" };

// One flow at a time. If a new one starts, the old one's loop sees a different
// id and bows out.
let activeRequestId: string | null = null;

chrome.runtime.onInstalled.addListener((details) => {
  if (details.reason === "install") void chrome.runtime.openOptionsPage();
});

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg?.type === "tk-start") {
    // Ack immediately; the flow runs on its own and reports via storage.
    void runApproval(msg.domain as string, msg.tabId as number);
    sendResponse({ ok: true });
  } else if (msg?.type === "tk-cancel") {
    activeRequestId = null;
    void setFlow(null);
    sendResponse({ ok: true });
  } else if (msg?.type === "tk-key-fill") {
    // Key route: the popup already unlocked the code with a touch. Fill it
    // through the same path as a phone answer (settings, rules, clipboard
    // fallback) and reflect the result via the flow.
    void keyFill(
      msg.code as string,
      msg.domain as string,
      msg.tabId as number,
      msg.site as string | undefined,
      msg.username as string | undefined,
    );
    sendResponse({ ok: true });
  }
  return false;
});

/** Fill a code the popup already unlocked with a security-key touch. Reuses the
 * phone-route fill path so settings, per-site rules, and the clipboard fallback
 * all apply identically. */
async function keyFill(
  code: string,
  domain: string,
  tabId: number,
  site: string | undefined,
  username: string | undefined,
): Promise<void> {
  activeRequestId = null; // supersede any phone flow in flight
  if (site) await rememberMatch(domain, { site, username: username ?? "" });
  const filled = await tryFill(tabId, code);
  await setFlow({
    status: filled ? "filled" : "filledClipboard",
    domain,
    code: filled ? undefined : code,
    at: Date.now(),
  });
}

async function runApproval(domain: string, tabId: number): Promise<void> {
  const pairing = await getPairing();
  if (!pairing) {
    await setFlow({ status: "unreachable", domain, at: Date.now() });
    return;
  }
  const sessionKey = fromB64(pairing.sessionKeyB64);
  const payload: RequestPayload = {
    kind: "code",
    domain,
    browser: browserLabel(),
    ts: Date.now(),
  };

  await setFlow({ status: "awaitingPhone", domain, at: Date.now() });

  let requestId: string;
  try {
    const created = await createRequest(
      pairing.pairingId,
      pairing.extToken,
      seal(sessionKey, payload),
    );
    requestId = created.requestId;
    activeRequestId = requestId;
    await setFlow({ status: "awaitingPhone", domain, requestId, at: Date.now() });
  } catch {
    await setFlow({ status: "unreachable", domain, at: Date.now() });
    return;
  }

  // Long-poll until answered/expired. Each call blocks up to ~25 s server-side
  // and the active fetch keeps the worker alive; we loop back-to-back.
  while (activeRequestId === requestId) {
    let result;
    try {
      result = await waitForAnswer(requestId, pairing.extToken);
    } catch {
      await setFlow({ status: "unreachable", domain, requestId, at: Date.now() });
      return;
    }
    if (activeRequestId !== requestId) return; // cancelled or superseded
    if (result.status === "pending") continue;
    if (result.status === "expired" || result.status === "gone") {
      await setFlow({ status: "expired", domain, requestId, at: Date.now() });
      return;
    }
    // answered
    let answer: AnswerPayload;
    try {
      answer = open<AnswerPayload>(sessionKey, result.answerBlob);
    } catch {
      await setFlow({ status: "unreachable", domain, requestId, at: Date.now() });
      return;
    }
    activeRequestId = null;
    if (answer.verdict === "denied") {
      await setFlow({ status: "denied", domain, at: Date.now() });
    } else if (answer.verdict === "unmatched") {
      await setFlow({ status: "unmatched", domain, at: Date.now() });
    } else {
      if (answer.site) {
        await rememberMatch(domain, {
          site: answer.site,
          username: answer.username ?? "",
        });
      }
      const filled = await tryFill(tabId, answer.code);
      await setFlow({
        status: filled ? "filled" : "filledClipboard",
        domain,
        code: filled ? undefined : answer.code,
        at: Date.now(),
      });
    }
    return;
  }
}

/**
 * Fill the code into the page's 2FA field via a one-shot injection.
 *
 * No standing content script: we inject `pageFill` into the tab only now, under
 * the activeTab grant the user created by opening the popup. That keeps the
 * extension off the broad "all sites" host permission — it never touches a page
 * until the person asks it to. Returns false (→ clipboard fallback) if the tab
 * can't be scripted (chrome:// pages, PDF viewer, no field found).
 */
async function tryFill(tabId: number, code: string): Promise<boolean> {
  const settings = await getSettings();
  const rule = settings.siteRules[await domainOfTab(tabId)] ?? undefined;
  if (!settings.autofill || rule === "never-autofill") return false;
  try {
    const [res] = await chrome.scripting.executeScript({
      target: { tabId },
      func: pageFill,
      args: [code, settings.autoSubmit],
    });
    return res?.result === true;
  } catch {
    return false;
  }
}

/**
 * Injected into the page (must be fully self-contained — it is serialised and
 * runs in the page's world, so it can close over nothing from this module).
 * Finds the 2FA field, fills it the way frameworks notice, optionally submits.
 */
function pageFill(code: string, submit: boolean): boolean {
  const OTP_RE =
    /(^|[-_ ])(otp|totp|2fa|mfa|one[-_ ]?time|verification|auth(entication)?)([-_ ]?(code|token|pin))?([-_ ]|$)|^code$|^token$/i;
  const visible = (el: HTMLElement): boolean => {
    const r = el.getBoundingClientRect();
    if (r.width === 0 || r.height === 0) return false;
    const s = getComputedStyle(el);
    return s.visibility !== "hidden" && s.display !== "none";
  };
  const inputs = [...document.querySelectorAll("input")].filter(
    (i) =>
      !i.disabled &&
      !i.readOnly &&
      visible(i) &&
      ["text", "tel", "number", "password", ""].includes(i.type || "text"),
  );
  const singles = inputs.filter(
    (i) => i.maxLength === 1 || i.getAttribute("maxlength") === "1",
  );
  let target: HTMLInputElement[] | null = null;
  let segmented = false;
  if (singles.length >= 4 && singles.length <= 8) {
    target = singles;
    segmented = true;
  } else {
    const one =
      inputs.find((i) => i.autocomplete === "one-time-code") ??
      inputs.find(
        (i) =>
          OTP_RE.test(i.name) ||
          OTP_RE.test(i.id) ||
          OTP_RE.test(i.getAttribute("aria-label") ?? ""),
      );
    if (one) target = [one];
  }
  if (!target) return false;

  const setValue = (input: HTMLInputElement, value: string): void => {
    const setter = Object.getOwnPropertyDescriptor(
      HTMLInputElement.prototype,
      "value",
    )?.set;
    setter?.call(input, value);
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  };
  if (segmented) {
    const digits = code.split("");
    target.forEach((input, i) => {
      input.focus();
      setValue(input, digits[i] ?? "");
    });
  } else {
    target[0]!.focus();
    setValue(target[0]!, code);
  }
  if (submit) {
    const form = target[0]!.form;
    form
      ?.querySelector<HTMLButtonElement>(
        'button[type="submit"], input[type="submit"], button:not([type])',
      )
      ?.click();
  }
  return true;
}

async function domainOfTab(tabId: number): Promise<string> {
  try {
    const tab = await chrome.tabs.get(tabId);
    return new URL(tab.url ?? "").hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}
