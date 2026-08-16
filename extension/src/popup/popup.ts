import { getFlow, type Flow } from "../lib/flow";
import { initI18n, localizeDom, t } from "../lib/i18n";
import {
  codeFor,
  isEnrolled,
  matchAccount,
  refreshReplica,
  unlockReplica,
} from "../lib/keyroute";
import { getMatch, getPairing, getSettings } from "../lib/state";

/**
 * The popup is a thin controller. It kicks off an approval ("tk-start" →
 * background) and then just reflects the flow state the service worker writes
 * to chrome.storage.session — so if the popup closes while the user approves
 * on their phone, reopening it shows the current state (filled / denied / …).
 */

const main = document.getElementById("main")!;
let currentDomain: string | null = null;

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

function chip(domain: string, username: string | null, matched: boolean): string {
  const initial = (username || domain)[0]?.toUpperCase() ?? "?";
  return `
    <div class="chip">
      <div class="tile">${esc(initial)}</div>
      <div class="who">
        <div class="site">${esc(domain)}</div>
        ${username ? `<div class="user">${esc(username)}</div>` : ""}
      </div>
      ${matched ? `<div class="badge">${t("badgeMatched")}</div>` : ""}
    </div>`;
}

// ---- Screens --------------------------------------------------------------

function renderUnpaired(): void {
  document.getElementById("open-settings")?.removeAttribute("hidden");
  main.replaceChildren(
    el(`<div>
      <div class="headline">${t("popupUnpairedTitle")}</div>
      <div class="sub">${t("popupUnpairedSub")}</div>
      <div class="stack"><button class="btn" id="pair">${t("pairMyPhone")}</button></div>
    </div>`),
  );
  document.getElementById("pair")!.addEventListener("click", () => {
    void chrome.runtime.openOptionsPage();
  });
}

function renderNoField(): void {
  main.replaceChildren(
    el(`<div>
      <div class="headline">${t("popupNoFieldTitle")}</div>
      <div class="sub">${t("popupNoFieldSub")}</div>
    </div>`),
  );
}

async function renderReady(domain: string): Promise<void> {
  const match = await getMatch(domain);
  const settings = await getSettings();
  const paired = (await getPairing()) !== null;
  // The key route is available when a key is enrolled and the site isn't pinned
  // to the phone. preferKey decides which action leads.
  const keyOn = (await isEnrolled()) && settings.siteRules[domain] !== "always-phone";
  const keyLeads = keyOn && settings.preferKey;

  const keyBtn = (primary: boolean) => `
    <button class="btn${primary ? "" : " secondary"}" id="key">
      <div class="glyph"></div>
      <div class="btn-col">${t("popupFillKey")}
        <span class="btn-sub">${t("popupFillKeySub")}</span>
      </div>
    </button>`;
  const phoneBtn = (primary: boolean) => `
    <button class="btn${primary ? "" : " secondary"}" id="ask">
      <div class="glyph"></div>
      <div class="btn-col">${t("popupAskPhone")}
        <span class="btn-sub">${t("popupAskPhoneSub")}</span>
      </div>
    </button>`;

  const actions: string[] = [];
  if (keyLeads) {
    actions.push(keyBtn(true));
    if (paired) actions.push(phoneBtn(false));
  } else {
    if (paired) actions.push(phoneBtn(true));
    if (keyOn) actions.push(keyBtn(!paired));
  }

  main.replaceChildren(
    el(`<div>
      ${chip(domain, match?.username ?? null, match !== null)}
      <div class="headline">${t("popupReadyTitle")}</div>
      <div class="sub">${
        keyOn ? t("popupReadySubKey") : t("popupReadySubPhone")
      }</div>
      <div class="stack">${actions.join("")}</div>
      <div class="footnote">${t("popupReadyFootnote")}</div>
    </div>`),
  );
  document.getElementById("ask")?.addEventListener("click", () => void start(domain));
  document.getElementById("key")?.addEventListener("click", () => void fillWithKey(domain));
}

function renderKeyTouching(domain: string): void {
  main.replaceChildren(
    el(`<div>
      ${chip(domain, null, false)}
      <div class="center">
        <div class="pulse-wrap"><div class="pulse-ring"></div><div class="phone-glyph"></div></div>
        <div class="wait-title">${t("popupKeyTouchTitle")}</div>
        <div class="wait-sub">${t("popupKeyTouchSub")}</div>
      </div>
    </div>`),
  );
}

function renderKeyError(domain: string, message: string): void {
  main.replaceChildren(
    el(`<div>
      <div class="headline">${t("popupKeyErrorTitle")}</div>
      <div class="sub">${esc(message)}</div>
      <div class="stack"><button class="btn" id="again">${t("tryAgain")}</button></div>
    </div>`),
  );
  document.getElementById("again")!.addEventListener("click", () => void fillWithKey(domain));
}

/** Key route: touch (in this popup) → decrypt the replica → match → fill.
 * The touch must run here — WebAuthn needs the extension page's user gesture. */
async function fillWithKey(domain: string): Promise<void> {
  currentDomain = domain;
  renderKeyTouching(domain);
  try {
    const accounts = await unlockReplica(); // the touch happens inside
    const account = matchAccount(accounts, domain);
    if (!account) return renderUnmatched(domain);
    const code = codeFor(account);
    const tabId = (await activeTab())?.id;
    if (tabId == null) return renderKeyError(domain, t("popupNoTab"));
    // Hand off to the worker to fill + report via the flow (renders next).
    await chrome.runtime.sendMessage({
      type: "tk-key-fill",
      code,
      domain,
      tabId,
      site: account.site,
      username: account.user,
    });
  } catch (e) {
    renderKeyError(domain, (e as Error).message);
  }
}

function renderAwaiting(domain: string): void {
  main.replaceChildren(
    el(`<div>
      ${chip(domain, null, false)}
      <div class="center">
        <div class="pulse-wrap"><div class="pulse-ring"></div><div class="phone-glyph"></div></div>
        <div class="wait-title">${t("popupSentTitle")}</div>
        <div class="wait-sub">${t("popupSentSub")}</div>
        <button class="btn ghost" id="cancel">${t("cancel")}</button>
      </div>
    </div>`),
  );
  document.getElementById("cancel")!.addEventListener("click", () => {
    void chrome.runtime.sendMessage({ type: "tk-cancel" });
    if (currentDomain) void renderReady(currentDomain);
  });
}

function renderFilled(): void {
  main.replaceChildren(
    el(`<div>
      <div class="check-row"><div class="check-dot">✓</div>
        <div class="check-title">${t("popupFilledTitle")}</div></div>
      <div class="sub">${t("popupFilledSub")}</div>
    </div>`),
  );
}

function renderFilledClipboard(code: string): void {
  main.replaceChildren(
    el(`<div>
      <div class="check-row"><div class="check-dot">✓</div>
        <div class="check-title">${t("popupClipTitle")}</div></div>
      <div class="sub">${t("popupClipSub")}</div>
      <div class="stack">
        <button class="btn" id="copy">${t("popupCopyCode", [esc(code.slice(0, 3)), esc(code.slice(3))])}</button>
      </div>
    </div>`),
  );
  document.getElementById("copy")!.addEventListener("click", async () => {
    await navigator.clipboard.writeText(code).catch(() => {});
    const b = document.getElementById("copy")!;
    b.textContent = t("copied");
  });
}

function renderDenied(domain: string): void {
  document.querySelector(".brand-tile")?.classList.add("danger");
  main.replaceChildren(
    el(`<div>
      <div class="headline">${t("popupDeniedTitle")}</div>
      <div class="sub">${t("popupDeniedSub")}</div>
      <div class="stack">
        <button class="btn secondary" id="again">${t("askAgain")}</button>
        <button class="btn danger" id="change">${t("popupChangePassword")}</button>
      </div>
    </div>`),
  );
  document.getElementById("again")!.addEventListener("click", () => {
    document.querySelector(".brand-tile")?.classList.remove("danger");
    void start(domain);
  });
  document.getElementById("change")!.addEventListener("click", () => {
    void chrome.tabs.create({ url: `https://${domain}/` });
  });
}

function renderExpired(domain: string): void {
  document.querySelector(".brand-tile")?.classList.add("muted");
  main.replaceChildren(
    el(`<div>
      <div class="headline">${t("popupExpiredTitle")}</div>
      <div class="sub">${t("popupExpiredSub")}</div>
      <div class="stack"><button class="btn" id="again">${t("askAgain")}</button></div>
    </div>`),
  );
  document.getElementById("again")!.addEventListener("click", () => {
    document.querySelector(".brand-tile")?.classList.remove("muted");
    void start(domain);
  });
}

function renderUnreachable(domain: string): void {
  main.replaceChildren(
    el(`<div>
      <div class="headline">${t("popupUnreachableTitle")}</div>
      <div class="sub">${t("popupUnreachableSub")}</div>
      <div class="stack">
        <button class="btn" id="again">${t("askAgain")}</button>
        <button class="btn ghost" id="close">${t("popupOpenApp")}</button>
      </div>
    </div>`),
  );
  document.getElementById("again")!.addEventListener("click", () => void start(domain));
  document.getElementById("close")!.addEventListener("click", () => window.close());
}

function renderUnmatched(domain: string): void {
  main.replaceChildren(
    el(`<div>
      <div class="headline">${t("popupUnmatchedTitle", [esc(domain)])}</div>
      <div class="sub">${t("popupUnmatchedSub")}</div>
      <div class="stack"><button class="btn" id="again">${t("askAgain")}</button></div>
    </div>`),
  );
  document.getElementById("again")!.addEventListener("click", () => void start(domain));
}

// ---- Control --------------------------------------------------------------

function start(domain: string): void {
  currentDomain = domain;
  renderAwaiting(domain);
  const tabIdP = activeTab().then((t) => t?.id);
  void tabIdP.then((tabId) => {
    if (tabId == null) return;
    void chrome.runtime.sendMessage({ type: "tk-start", domain, tabId });
  });
}

function renderFromFlow(flow: Flow): void {
  document.querySelector(".brand-tile")?.classList.remove("danger", "muted");
  switch (flow.status) {
    case "awaitingPhone":
      return renderAwaiting(flow.domain);
    case "filled":
      return renderFilled();
    case "filledClipboard":
      return renderFilledClipboard(flow.code ?? "");
    case "denied":
      return renderDenied(flow.domain);
    case "expired":
      return renderExpired(flow.domain);
    case "unreachable":
      return renderUnreachable(flow.domain);
    case "unmatched":
      return renderUnmatched(flow.domain);
  }
}

async function init(): Promise<void> {
  await initI18n(); // resolve the chosen (or browser) language before rendering
  localizeDom(); // header buttons carry data-i18n
  document.getElementById("open-settings")!.addEventListener("click", () => {
    void chrome.runtime.openOptionsPage();
  });

  const pairing = await getPairing();
  if (!pairing) return renderUnpaired();

  const domain = domainOf(await activeTab());
  currentDomain = domain;

  // Warm the replica cache now (network), so a later key touch decrypts from a
  // fresh local copy without racing a fetch against the WebAuthn gesture window.
  if (domain != null && (await isEnrolled())) void refreshReplica();

  // Reflect any in-progress/terminal flow the service worker owns.
  const flow = await getFlow();
  if (flow && (domain == null || flow.domain === domain)) {
    renderFromFlow(flow);
  } else if (domain == null) {
    renderNoField();
  } else {
    await renderReady(domain);
  }

  // Live updates while the popup stays open.
  chrome.storage.session.onChanged.addListener((changes) => {
    if (!changes.flow) return;
    const next = changes.flow.newValue as Flow | undefined;
    if (next) renderFromFlow(next);
  });
}

void init();
