import { getFlow, type Flow } from "../lib/flow";
import { getMatch, getPairing } from "../lib/state";

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
      ${matched ? '<div class="badge">MATCHED</div>' : ""}
    </div>`;
}

// ---- Screens --------------------------------------------------------------

function renderUnpaired(): void {
  document.getElementById("open-settings")?.removeAttribute("hidden");
  main.replaceChildren(
    el(`<div>
      <div class="headline">Your phone is the key. This is the keyhole.</div>
      <div class="sub">Pair your phone once and signing in becomes a tap. Your
        codes stay on the phone — this extension never sees the secret.</div>
      <div class="stack"><button class="btn" id="pair">Pair my phone</button></div>
    </div>`),
  );
  document.getElementById("pair")!.addEventListener("click", () => {
    void chrome.runtime.openOptionsPage();
  });
}

function renderNoField(): void {
  main.replaceChildren(
    el(`<div>
      <div class="headline">Nothing to fill here.</div>
      <div class="sub">Open this on a page asking for a six-digit code, and the
        code can come straight from your phone.</div>
    </div>`),
  );
}

async function renderReady(domain: string): Promise<void> {
  const match = await getMatch(domain);
  main.replaceChildren(
    el(`<div>
      ${chip(domain, match?.username ?? null, match !== null)}
      <div class="headline">Ready when you are.</div>
      <div class="sub">Your code has to come from something you're holding —
        your phone.</div>
      <div class="stack">
        <button class="btn" id="ask">
          <div class="glyph"></div>
          <div class="btn-col">Ask my phone
            <span class="btn-sub">Approve there and the code lands here</span>
          </div>
        </button>
      </div>
      <div class="footnote">Only the six digits travel, and only after you
        approve. You can close this — it'll fill in when you approve.</div>
    </div>`),
  );
  document.getElementById("ask")!.addEventListener("click", () => {
    void start(domain);
  });
}

function renderAwaiting(domain: string): void {
  main.replaceChildren(
    el(`<div>
      ${chip(domain, null, false)}
      <div class="center">
        <div class="pulse-wrap"><div class="pulse-ring"></div><div class="phone-glyph"></div></div>
        <div class="wait-title">Sent to your phone</div>
        <div class="wait-sub">Approve it there and the code lands here. You can
          close this window — it keeps working.</div>
        <button class="btn ghost" id="cancel">Cancel</button>
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
        <div class="check-title">Filled in for you.</div></div>
      <div class="sub">Your phone made the code and sent only those six digits.
        Nothing else crossed over.</div>
    </div>`),
  );
}

function renderFilledClipboard(code: string): void {
  main.replaceChildren(
    el(`<div>
      <div class="check-row"><div class="check-dot">✓</div>
        <div class="check-title">Here's your code.</div></div>
      <div class="sub">We couldn't find the code box on this page, so copy it in
        yourself:</div>
      <div class="stack">
        <button class="btn" id="copy">Copy ${esc(code.slice(0, 3))} ${esc(code.slice(3))}</button>
      </div>
    </div>`),
  );
  document.getElementById("copy")!.addEventListener("click", async () => {
    await navigator.clipboard.writeText(code).catch(() => {});
    const b = document.getElementById("copy")!;
    b.textContent = "Copied";
  });
}

function renderDenied(domain: string): void {
  document.querySelector(".brand-tile")?.classList.add("danger");
  main.replaceChildren(
    el(`<div>
      <div class="headline">You turned this one down</div>
      <div class="sub">No code was sent. If that was a mistake, ask again — if it
        wasn't, change your password for this site.</div>
      <div class="stack">
        <button class="btn secondary" id="again">Ask again</button>
        <button class="btn danger" id="change">Change my password</button>
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
      <div class="headline">That request ran out of time</div>
      <div class="sub">Requests expire after a minute so an old one can't be
        approved by accident. Nothing went wrong — just ask again.</div>
      <div class="stack"><button class="btn" id="again">Ask again</button></div>
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
      <div class="headline">Your phone didn't answer</div>
      <div class="sub">It might be asleep, out of signal, or face-down on a
        table. Nothing's wrong with your account.</div>
      <div class="stack">
        <button class="btn" id="again">Ask again</button>
        <button class="btn ghost" id="close">Or open the app and read the code</button>
      </div>
    </div>`),
  );
  document.getElementById("again")!.addEventListener("click", () => void start(domain));
  document.getElementById("close")!.addEventListener("click", () => window.close());
}

function renderUnmatched(domain: string): void {
  main.replaceChildren(
    el(`<div>
      <div class="headline">You haven't saved ${esc(domain)} yet</div>
      <div class="sub">If you already have this account on your phone under a
        different name, open it there and approve — this popup will remember the
        match next time.</div>
      <div class="stack"><button class="btn" id="again">Ask again</button></div>
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
  document.getElementById("open-settings")!.addEventListener("click", () => {
    void chrome.runtime.openOptionsPage();
  });

  const pairing = await getPairing();
  if (!pairing) return renderUnpaired();

  const domain = domainOf(await activeTab());
  currentDomain = domain;

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
