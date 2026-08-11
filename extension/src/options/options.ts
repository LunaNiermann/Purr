import QRCode from "qrcode";

import {
  deriveSessionKey,
  fromB64,
  generateKeyPair,
  newPairingSecret,
  toB64,
  open as openBlob,
} from "../lib/crypto";
import { RELAY_URL, createPairing, unpair, waitForPhone } from "../lib/relay";
import {
  addSecurityKey,
  confirmSecurityKey,
  defaultSettings,
  getPairing,
  getSecurityKeys,
  getSettings,
  removeSecurityKey,
  setPairing,
  setSettings,
  type Pairing,
  type Settings,
} from "../lib/state";
import { deriveReplicaKey, registerKey, webauthnAvailable } from "../lib/webauthn";

/**
 * Options page: first-run pairing (B1: intro → scan → paired) when no phone
 * is paired, settings (B7) afterwards.
 */

const page = document.getElementById("page")!;

function el(html: string): HTMLElement {
  const t = document.createElement("template");
  t.innerHTML = html.trim();
  return t.content.firstElementChild as HTMLElement;
}

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) => `&#${c.charCodeAt(0)};`);
}

function stepDots(step: number): string {
  return `
    <div class="step-dots">
      ${[1, 2, 3]
        .map((n) => `<div class="step-dot${n <= step ? " on" : ""}"></div>`)
        .join("")}
      <span class="step-label">Step ${step} of 3</span>
    </div>`;
}

function pairShell(step: number, inner: string): HTMLElement {
  return el(`
    <div class="pair-card">
      <div class="pair-head">
        <div class="brand-tile">2</div>
        <div class="name">Purr</div>
        ${stepDots(step)}
      </div>
      ${inner}
    </div>`);
}

// ---- B1 step 1: intro -----------------------------------------------------

function renderIntro(): void {
  page.replaceChildren(
    pairShell(
      1,
      `<div class="pair-body">
        <div class="pair-main">
          <div class="pair-hero">Your phone is<br>the key. This is<br>the keyhole.</div>
          <div class="pair-copy">Pairing takes about a minute. After that,
            signing in anywhere is a tap on your phone — no codes to type,
            nothing to remember.</div>
          <div class="tick-list">
            <div class="tick"><div class="mark">✓</div><div class="text">Your
              codes stay on your phone. This extension never sees the
              secret.</div></div>
            <div class="tick"><div class="mark">✓</div><div class="text">Works
              with no account. Nothing to sign up for.</div></div>
            <div class="tick"><div class="mark">✓</div><div class="text">Unpair
              from either side, any time.</div></div>
          </div>
          <div class="pair-actions">
            <button class="btn large" id="start">Pair my phone</button>
          </div>
        </div>
        <div class="pair-side">
          <div style="width:132px;height:246px;border-radius:26px;border:2.5px solid rgba(27,26,23,.22);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px">
            <div class="brand-tile" style="width:34px;height:34px;border-radius:11px;font-size:15px">2</div>
            <div style="font-size:12.5px;color:rgba(27,26,23,.45);text-align:center;line-height:1.45;padding:0 16px">Get the app first, if you haven't</div>
          </div>
        </div>
      </div>`,
    ),
  );
  document.getElementById("start")!.addEventListener("click", () => {
    void renderScan();
  });
}

// ---- B1 step 2: QR --------------------------------------------------------

async function renderScan(): Promise<void> {
  const keys = generateKeyPair();
  const secret = newPairingSecret();
  let created: { pairingId: string; extToken: string };
  try {
    created = await createPairing(toB64(keys.pub));
  } catch {
    page.replaceChildren(
      pairShell(
        2,
        `<div class="pair-body"><div class="pair-main">
          <div class="pair-hero" style="font-size:28px">Can't reach the pairing service</div>
          <div class="pair-copy">Check the connection and try again. Nothing
            was set up yet, so nothing is half-done.</div>
          <div class="pair-actions"><button class="btn large" id="retry">Try again</button></div>
        </div></div>`,
      ),
    );
    document.getElementById("retry")!.addEventListener("click", () => {
      void renderScan();
    });
    return;
  }

  // The QR payload: everything the phone needs, including the secret the
  // relay never sees.
  const qrPayload = `purr-pair:${btoa(
    JSON.stringify({
      v: 1,
      relay: RELAY_URL,
      pairingId: created.pairingId,
      extPub: toB64(keys.pub),
      secret: toB64(secret),
    }),
  )}`;

  page.replaceChildren(
    pairShell(
      2,
      `<div class="pair-body">
        <div class="pair-main">
          <div class="pair-hero" style="font-size:30px">Point your phone at this</div>
          <div class="pair-copy" style="font-size:15.5px;max-width:360px">Open
            Purr on your phone, tap <b style="color:var(--ink);font-weight:600">Security
            → Pair a computer</b>, then hold it up to the square.</div>
          <div class="waiting-line">
            <div class="waiting-dot"></div>
            Waiting for your phone…
          </div>
          <button class="btn ghost" id="back" style="margin-top:26px;padding-left:0">Back</button>
        </div>
        <div class="pair-side">
          <div class="qr-box"><canvas id="qr"></canvas></div>
        </div>
      </div>`,
    ),
  );
  document.getElementById("back")!.addEventListener("click", () => {
    renderIntro();
  });

  await QRCode.toCanvas(
    document.getElementById("qr") as HTMLCanvasElement,
    qrPayload,
    { margin: 0, color: { dark: "#1B1A17", light: "#FFFFFF" }, width: 184 },
  );

  // Long-poll until the phone joins (each call holds ~25 s server-side).
  while (document.getElementById("qr") !== null) {
    let result;
    try {
      result = await waitForPhone(created.pairingId, created.extToken);
    } catch {
      await new Promise((r) => setTimeout(r, 3000));
      continue;
    }
    if (!result.completed) continue;

    const sessionKey = deriveSessionKey(
      keys.priv,
      fromB64(result.phonePub!),
      secret,
    );
    let phoneName = "Your phone";
    if (result.phoneNameBlob) {
      try {
        phoneName = openBlob<{ name: string }>(
          sessionKey,
          result.phoneNameBlob,
        ).name;
      } catch {
        // An undecryptable name blob means the phone doesn't hold the QR
        // secret — treat the pairing as compromised and abort.
        renderIntro();
        return;
      }
    }
    const pairing: Pairing = {
      pairingId: created.pairingId,
      extToken: created.extToken,
      extPrivB64: toB64(keys.priv),
      extPubB64: toB64(keys.pub),
      phonePubB64: result.phonePub!,
      sessionKeyB64: toB64(sessionKey),
      phoneName,
      pairedAt: Date.now(),
      lastUsedAt: null,
    };
    await setPairing(pairing);
    renderPaired(pairing);
    return;
  }
}

// ---- B1 step 3: paired ----------------------------------------------------

function renderPaired(pairing: Pairing): void {
  page.replaceChildren(
    pairShell(
      3,
      `<div class="paired-wrap">
        <div class="paired-check">✓</div>
        <div class="paired-title">Paired with "${esc(pairing.phoneName)}"</div>
        <div class="paired-copy">Next time a site asks for a code, this
          extension will spot it and ask your phone. You'll just tap
          Approve.</div>
        <div class="device-row">
          <div class="tile">${esc(pairing.phoneName[0]?.toUpperCase() ?? "P")}</div>
          <div class="grow">
            <div class="title">${esc(pairing.phoneName)}</div>
            <div class="subtitle">Paired just now</div>
          </div>
          <div class="badge">ACTIVE</div>
        </div>
        <div class="pair-actions">
          <button class="btn large" id="done">Done</button>
        </div>
      </div>`,
    ),
  );
  document.getElementById("done")!.addEventListener("click", () => {
    void renderSettings();
  });
}

// ---- B7: settings ---------------------------------------------------------

async function renderSettings(): Promise<void> {
  const pairing = await getPairing();
  if (!pairing) {
    renderIntro();
    return;
  }
  const settings = await getSettings();

  const agoDays = Math.floor((Date.now() - pairing.pairedAt) / 86_400_000);
  const pairedAgo =
    agoDays === 0
      ? "today"
      : agoDays === 1
        ? "yesterday"
        : agoDays < 30
          ? `${agoDays} days ago`
          : `${Math.floor(agoDays / 30)} month${agoDays >= 60 ? "s" : ""} ago`;

  const ruleLabel = {
    "always-phone": "Always ask my phone",
    "never-autofill": "Never fill automatically",
  } as const;

  page.replaceChildren(
    el(`<div>
      <div class="page-head">
        <div class="brand-tile">2</div>
        <div class="page-title">Purr settings</div>
      </div>

      <div class="section-label">When a site asks for a code</div>
      <div class="card">
        <div class="row">
          <div class="grow">
            <div class="title">Fill it in for me automatically</div>
            <div class="subtitle">After you approve — we never fill without a tap somewhere</div>
          </div>
          <button class="toggle${settings.autofill ? " on" : ""}" data-key="autofill"><div class="knob"></div></button>
        </div>
        <div class="row">
          <div class="grow">
            <div class="title">Submit the form once it's filled</div>
            <div class="subtitle">Saves a click; turn off if a site behaves oddly</div>
          </div>
          <button class="toggle${settings.autoSubmit ? " on" : ""}" data-key="autoSubmit"><div class="knob"></div></button>
        </div>
      </div>

      <div class="section-label">Sites with their own rules</div>
      <div class="card" id="rules"></div>

      <div class="section-label">Sign in with a security key <span style="opacity:.6;font-weight:500">· experimental</span></div>
      <div class="card" id="security-keys"></div>
      <div class="sub" style="margin-top:10px">Touch a registered key to fill a
        code on this computer with your phone in your pocket. Your codes live
        here only as ciphertext; the key is what unlocks them.</div>

      <div class="section-label">Paired devices</div>
      <div class="card">
        <div class="row">
          <div class="device-row" style="margin:0;background:none;padding:0">
            <div class="tile">${esc(pairing.phoneName[0]?.toUpperCase() ?? "P")}</div>
            <div class="grow">
              <div class="title">${esc(pairing.phoneName)}</div>
              <div class="subtitle">Paired ${pairedAgo}${pairing.lastUsedAt ? " · last used recently" : ""}</div>
            </div>
            <button class="small-outline" id="unpair">Unpair</button>
          </div>
        </div>
      </div>
      <div class="sub" style="margin-top:10px">Unpairing only affects this
        browser. Your codes stay on your phone, untouched.</div>
    </div>`),
  );

  // Toggles
  for (const toggle of page.querySelectorAll<HTMLButtonElement>(".toggle")) {
    toggle.addEventListener("click", async () => {
      const key = toggle.dataset.key as "autofill" | "autoSubmit" | "preferKey";
      const current = await getSettings();
      const updated: Settings = { ...current, [key]: !current[key] };
      await setSettings(updated);
      toggle.classList.toggle("on", updated[key]);
    });
  }

  // Site rules
  const rules = document.getElementById("rules")!;
  const entries = Object.entries(settings.siteRules);
  if (entries.length === 0) {
    rules.appendChild(
      el(`<div class="subtitle" style="font-size:13.5px;color:var(--ink-55)">
        No special rules yet. Rules land here when you add one.</div>`),
    );
  }
  for (const [domain, rule] of entries) {
    const row = el(`<div class="row">
      <div class="grow"><div class="title" style="font-size:14.5px">${esc(domain)}</div></div>
      <div class="subtitle">${ruleLabel[rule]}</div>
      <button class="small-outline">Remove</button>
    </div>`);
    row.querySelector("button")!.addEventListener("click", async () => {
      const current = await getSettings();
      delete current.siteRules[domain];
      await setSettings(current);
      void renderSettings();
    });
    rules.appendChild(row);
  }
  const addRow = el(`<div class="row">
    <input class="vault-search" id="rule-domain" placeholder="site.example.com" style="max-width:280px">
    <button class="small-outline" id="add-never">Never fill automatically</button>
  </div>`);
  addRow.querySelector("#add-never")!.addEventListener("click", async () => {
    const input = document.getElementById("rule-domain") as HTMLInputElement;
    const domain = input.value.trim().toLowerCase();
    if (!domain) return;
    const current = await getSettings();
    current.siteRules[domain] = "never-autofill";
    await setSettings(current);
    void renderSettings();
  });
  rules.appendChild(addRow);

  await populateSecurityKeys();

  document.getElementById("unpair")!.addEventListener("click", async () => {
    await unpair(pairing.pairingId, pairing.extToken).catch(() => {});
    await setPairing(null);
    await setSettings(defaultSettings);
    renderIntro();
  });
}

// ---- "Touch your key": register + validate security keys -------------------

/** (Re)build the security-keys card: registered keys, add, and a touch test
 * that confirms PRF unlock works end to end on the real hardware. */
async function populateSecurityKeys(): Promise<void> {
  const card = document.getElementById("security-keys");
  if (!card) return;
  card.replaceChildren();

  if (!webauthnAvailable()) {
    card.appendChild(
      el(`<div class="subtitle" style="font-size:13.5px;color:var(--ink-55)">
        This browser doesn't support security keys.</div>`),
    );
    return;
  }

  const status = el(
    `<div class="subtitle" style="font-size:13px;color:var(--ink-55);margin-top:6px"></div>`,
  );

  const keys = await getSecurityKeys();
  for (const k of keys) {
    const state = k.prfConfirmed
      ? `<span style="color:var(--green)">Ready</span>`
      : `<span style="color:var(--ink-55)">Not confirmed — tap Test unlock</span>`;
    const row = el(`<div class="row">
      <div class="tile">⚿</div>
      <div class="grow">
        <div class="title" style="font-size:14.5px">${esc(k.label)}</div>
        <div class="subtitle">Added ${new Date(k.addedAt).toLocaleDateString()} · ${state}</div>
      </div>
      <button class="small-outline">Remove</button>
    </div>`);
    row.querySelector("button")!.addEventListener("click", async () => {
      await removeSecurityKey(k.credentialIdB64);
      await populateSecurityKeys();
    });
    card.appendChild(row);
  }

  const addRow = el(`<div class="row">
    <input class="vault-search" id="sk-label" placeholder="Name this key (e.g. YubiKey)" style="max-width:240px">
    <button class="small-outline" id="sk-add">Add a security key</button>
  </div>`);
  addRow.querySelector("#sk-add")!.addEventListener("click", async () => {
    const label =
      (document.getElementById("sk-label") as HTMLInputElement).value.trim() ||
      "Security key";
    status.textContent = "Touch your key…";
    try {
      const res = await registerKey(label);
      await addSecurityKey({
        credentialIdB64: res.credentialIdB64,
        label,
        addedAt: Date.now(),
        prfConfirmed: false,
      });
      status.textContent = res.prfSupported
        ? `✓ ${label} registered. Tap "Test unlock" and touch it to confirm PRF works.`
        : `⚠ ${label} registered, but it reported no PRF support — it likely can't unlock the key route. Try Test unlock to be sure.`;
      await populateSecurityKeys();
    } catch (e) {
      status.textContent = `Couldn't register: ${(e as Error).message}`;
    }
  });
  card.appendChild(addRow);

  if (keys.length > 0) {
    const testRow = el(`<div class="row">
      <div class="grow"><div class="subtitle" style="font-size:13.5px">Confirm a touch unlocks the vault</div></div>
      <button class="small-outline" id="sk-test">Test unlock</button>
    </div>`);
    testRow.querySelector("#sk-test")!.addEventListener("click", async () => {
      status.textContent = "Touch your key…";
      try {
        const ids = (await getSecurityKeys()).map((k) => k.credentialIdB64);
        const { credentialIdB64 } = await deriveReplicaKey(ids);
        await confirmSecurityKey(credentialIdB64);
        const used = (await getSecurityKeys()).find(
          (k) => k.credentialIdB64 === credentialIdB64,
        );
        status.textContent = `✓ Unlock confirmed with ${used?.label ?? "your key"} — PRF works end to end.`;
        await populateSecurityKeys();
      } catch (e) {
        status.textContent = `Unlock failed: ${(e as Error).message}`;
      }
    });
    card.appendChild(testRow);
  }

  card.appendChild(status);
}

// ---- Boot -----------------------------------------------------------------

void (async () => {
  const pairing = await getPairing();
  if (pairing) await renderSettings();
  else renderIntro();
})();
