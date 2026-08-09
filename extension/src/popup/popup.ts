import { fromB64, open, seal } from "../lib/crypto";
import { createRequest, waitForAnswer } from "../lib/relay";
import {
  getMatch,
  getPairing,
  getSettings,
  rememberMatch,
  type Pairing,
} from "../lib/state";

/**
 * The popup drives the whole desktop flow (B2–B6). It is the only UI surface
 * — nothing is ever injected into the page except the fill itself.
 *
 * States: unpaired → ready → awaitingPhone → filled | denied | expired |
 * unreachable; plus the unmatched entry variant (B5).
 */

const main = document.getElementById("main")!;

type AnswerPayload =
  | {
      verdict: "approved";
      code: string;
      site?: string;
      username?: string;
    }
  | { verdict: "denied" }
  | { verdict: "unmatched" };

interface RequestPayload {
  kind: "code";
  domain: string;
  browser: string;
  ts: number;
}

function el(html: string): HTMLElement {
  const t = document.createElement("template");
  t.innerHTML = html.trim();
  return t.content.firstElementChild as HTMLElement;
}

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

async function activeTab(): Promise<chrome.tabs.Tab | null> {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab ?? null;
}

function domainOf(tab: chrome.tabs.Tab | null): string | null {
  try {
    const url = new URL(tab?.url ?? "");
    if (!["http:", "https:"].includes(url.protocol)) return null;
    return url.hostname.replace(/^www\./, "");
  } catch {
    return null;
  }
}

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

function chipHtml(domain: string, site: string | null, username: string | null,
    matched: boolean): string {
  const initial = (site ?? domain)[0]?.toUpperCase() ?? "?";
  return `
    <div class="chip">
      <div class="tile">${esc(initial)}</div>
      <div class="who">
        <div class="site">${esc(domain)}</div>
        ${username ? `<div class="user">${esc(username)}</div>` : ""}
      </div>
      ${matched ? '<div class="badge">MATCHED</div>' : ""}
    </div>`;
}

// ---- States ---------------------------------------------------------------

function renderUnpaired(): void {
  main.replaceChildren(
    el(`<div>
      <div class="headline">Your phone is the key. This is the keyhole.</div>
      <div class="sub">Pair your phone once and signing in anywhere becomes a
        tap. Your codes stay on the phone — this extension never sees the
        secret.</div>
      <div class="stack">
        <button class="btn" id="pair">Pair my phone</button>
      </div>
    </div>`),
  );
  document.getElementById("pair")!.addEventListener("click", () => {
    void chrome.runtime.openOptionsPage();
  });
}

function renderNoField(domain: string | null): void {
  main.replaceChildren(
    el(`<div>
      <div class="headline">Nothing to fill here${domain ? ` on ${esc(domain)}` : ""}.</div>
      <div class="sub">When a site asks for a six-digit code, open this popup
        and the code can come straight from your phone.</div>
    </div>`),
  );
}

async function renderReady(pairing: Pairing, domain: string): Promise<void> {
  const match = await getMatch(domain);
  main.replaceChildren(
    el(`<div>
      ${chipHtml(domain, match?.site ?? null, match?.username ?? null, match !== null)}
      <div class="headline">Ready when you are.</div>
      <div class="sub">Your code has to come from something you're holding —
        your phone.</div>
      <div class="stack">
        <button class="btn" id="ask-phone">
          <div class="glyph"></div>
          <div class="btn-col">Ask my phone
            <span class="btn-sub">Approve there and the code lands here</span>
          </div>
        </button>
      </div>
      <div class="footnote">Your codes stay on your phone. Only the six digits
        travel — and only after you approve.</div>
    </div>`),
  );
  document.getElementById("ask-phone")!.addEventListener("click", () => {
    void runPhoneFlow(pairing, domain);
  });
}

function renderAwaitingPhone(onCancel: () => void): void {
  main.replaceChildren(
    el(`<div>
      <div class="center">
        <div class="pulse-wrap">
          <div class="pulse-ring"></div>
          <div class="phone-glyph"></div>
        </div>
        <div class="wait-title">Sent to your phone</div>
        <div class="wait-sub">Approve it there and the code lands here. Your
          secret never leaves the phone.</div>
        <button class="btn ghost" id="cancel">Cancel</button>
      </div>
    </div>`),
  );
  document.getElementById("cancel")!.addEventListener("click", onCancel);
}

function renderFilled(filledIntoPage: boolean, code: string): void {
  main.replaceChildren(
    el(`<div>
      <div class="check-row">
        <div class="check-dot">✓</div>
        <div class="check-title">${filledIntoPage ? "Filled in for you." : "Here's your code."}</div>
      </div>
      <div class="sub">${
        filledIntoPage
          ? "Your phone made the code and sent only those six digits. Nothing else crossed over."
          : `The page's code box hid from us — the code is <b style="font-family:'JetBrains Mono',monospace">${esc(code.slice(0, 3))} ${esc(code.slice(3))}</b>, copied to your clipboard.`
      }</div>
    </div>`),
  );
}

function renderDenied(pairing: Pairing, domain: string): void {
  document.querySelector(".brand-tile")!.classList.add("danger");
  main.replaceChildren(
    el(`<div>
      <div class="headline">You turned this one down</div>
      <div class="sub">No code was sent. If that was a mistake, ask again —
        if it wasn't, change your password for this site.</div>
      <div class="stack">
        <button class="btn secondary" id="again">Ask again</button>
        <button class="btn danger" id="change">Change my password</button>
      </div>
    </div>`),
  );
  document.getElementById("again")!.addEventListener("click", () => {
    document.querySelector(".brand-tile")!.classList.remove("danger");
    void runPhoneFlow(pairing, domain);
  });
  document.getElementById("change")!.addEventListener("click", () => {
    void chrome.tabs.create({
      url: `https://${domain}/settings/security`,
    });
  });
}

function renderExpired(pairing: Pairing, domain: string, askedAt: Date): void {
  document.querySelector(".brand-tile")!.classList.add("muted");
  const fmt = (d: Date) =>
    `${d.getHours().toString().padStart(2, "0")}:${d.getMinutes().toString().padStart(2, "0")}`;
  const expired = new Date(askedAt.getTime() + 60_000);
  main.replaceChildren(
    el(`<div>
      <div class="headline">That request ran out of time</div>
      <div class="sub">Requests expire after a minute so an old one can't be
        approved by accident later. Nothing went wrong — just ask again.</div>
      <div class="note-box">Asked at ${fmt(askedAt)} · expired ${fmt(expired)}</div>
      <div class="stack">
        <button class="btn" id="again">Ask again</button>
      </div>
    </div>`),
  );
  document.getElementById("again")!.addEventListener("click", () => {
    document.querySelector(".brand-tile")!.classList.remove("muted");
    void runPhoneFlow(pairing, domain);
  });
}

function renderUnreachable(pairing: Pairing, domain: string): void {
  main.replaceChildren(
    el(`<div>
      <div class="headline">Your phone didn't answer</div>
      <div class="sub">It might be asleep, out of signal, or face-down on a
        table. Nothing's wrong with your account.</div>
      <div class="stack">
        <button class="btn" id="again">Ask again</button>
        <button class="btn ghost" id="manual">Or open the app and read the code</button>
      </div>
    </div>`),
  );
  document.getElementById("again")!.addEventListener("click", () => {
    void runPhoneFlow(pairing, domain);
  });
  document.getElementById("manual")!.addEventListener("click", () => window.close());
}

function renderUnmatched(pairing: Pairing, domain: string): void {
  main.replaceChildren(
    el(`<div>
      <div class="headline">You haven't saved ${esc(domain)} yet</div>
      <div class="sub">If you already have this account on your phone, it may
        be filed under a different name — your phone will show the list when
        you ask, and this popup will remember the match.</div>
      <div class="stack">
        <button class="btn" id="ask-anyway">Ask my phone anyway</button>
      </div>
      <div class="footnote">Nothing about this site has been sent anywhere
        except, encrypted, to your own phone.</div>
    </div>`),
  );
  document.getElementById("ask-anyway")!.addEventListener("click", () => {
    void runPhoneFlow(pairing, domain);
  });
}

// ---- The flow -------------------------------------------------------------

let cancelled = false;

async function runPhoneFlow(pairing: Pairing, domain: string): Promise<void> {
  cancelled = false;
  const sessionKey = fromB64(pairing.sessionKeyB64);
  const payload: RequestPayload = {
    kind: "code",
    domain,
    browser: browserLabel(),
    ts: Date.now(),
  };
  const askedAt = new Date();
  renderAwaitingPhone(() => {
    cancelled = true;
    void init();
  });

  let requestId: string;
  try {
    const created = await createRequest(
      pairing.pairingId,
      pairing.extToken,
      seal(sessionKey, payload),
    );
    requestId = created.requestId;
  } catch {
    renderUnreachable(pairing, domain);
    return;
  }

  while (!cancelled) {
    let result;
    try {
      result = await waitForAnswer(requestId, pairing.extToken);
    } catch {
      renderUnreachable(pairing, domain);
      return;
    }
    if (cancelled) return;
    if (result.status === "pending") continue;
    if (result.status === "expired" || result.status === "gone") {
      renderExpired(pairing, domain, askedAt);
      return;
    }
    // answered
    let answer: AnswerPayload;
    try {
      answer = open<AnswerPayload>(sessionKey, result.answerBlob);
    } catch {
      renderUnreachable(pairing, domain);
      return;
    }
    if (answer.verdict === "denied") {
      renderDenied(pairing, domain);
    } else if (answer.verdict === "unmatched") {
      renderUnmatched(pairing, domain);
    } else {
      if (answer.site) {
        await rememberMatch(domain, {
          site: answer.site,
          username: answer.username ?? "",
        });
      }
      const settings = await getSettings();
      const rule = settings.siteRules[domain];
      const shouldFill = settings.autofill && rule !== "never-autofill";
      let filled = false;
      if (shouldFill) {
        const tab = await activeTab();
        if (tab?.id != null) {
          try {
            const res = await chrome.tabs.sendMessage(tab.id, {
              type: "twokeys:fill",
              code: answer.code,
              submit: settings.autoSubmit,
            });
            filled = res?.filled === true;
          } catch {
            filled = false;
          }
        }
      }
      if (!filled) {
        await navigator.clipboard.writeText(answer.code).catch(() => {});
      }
      renderFilled(filled, answer.code);
    }
    return;
  }
}

// ---- Boot -----------------------------------------------------------------

async function init(): Promise<void> {
  document.getElementById("open-settings")!.addEventListener("click", () => {
    void chrome.runtime.openOptionsPage();
  });

  const pairing = await getPairing();
  if (!pairing) {
    renderUnpaired();
    return;
  }
  const tab = await activeTab();
  const domain = domainOf(tab);
  if (!domain) {
    renderNoField(null);
    return;
  }
  await renderReady(pairing, domain);
}

void init();
