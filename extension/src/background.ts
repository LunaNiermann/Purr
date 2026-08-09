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
  }
  return false;
});

function browserLabel(): string {
  const ua = navigator.userAgent;
  const browser = ua.includes("Edg/") ? "Edge" : "Chrome";
  const os = ua.includes("Windows")
    ? "Windows"
    : ua.includes("Mac")
      ? "Mac"
      : "Linux";
  return `${browser} · ${os}`;
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

/** Ask the content script to fill the code into the page's 2FA field. */
async function tryFill(tabId: number, code: string): Promise<boolean> {
  const settings = await getSettings();
  const rule = settings.siteRules[await domainOfTab(tabId)] ?? undefined;
  if (!settings.autofill || rule === "never-autofill") return false;
  try {
    const res = await chrome.tabs.sendMessage(tabId, {
      type: "twokeys:fill",
      code,
      submit: settings.autoSubmit,
    });
    return res?.filled === true;
  } catch {
    // No content script on that tab (e.g. it loaded before install) — the
    // popup will show the code for manual copy instead.
    return false;
  }
}

async function domainOfTab(tabId: number): Promise<string> {
  try {
    const tab = await chrome.tabs.get(tabId);
    return new URL(tab.url ?? "").hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}
