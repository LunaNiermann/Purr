import QRCode from "qrcode";

import { getUiLang, initI18n, setUiLang, t, UI_LANGUAGES } from "../lib/i18n";
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
import { deriveKek, registerKey, webauthnAvailable } from "../lib/webauthn";
import {
  addTouchedKey,
  disableKeyRoute,
  enrollFirstKey,
  isEnrolled,
} from "../lib/keyroute";

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
      <span class="step-label">${t("optStepOf", [step])}</span>
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
          <div class="pair-hero">${t("optIntroHero")}</div>
          <div class="pair-copy">${t("optIntroCopy")}</div>
          <div class="tick-list">
            <div class="tick"><div class="mark">✓</div><div class="text">${t("optTick1")}</div></div>
            <div class="tick"><div class="mark">✓</div><div class="text">${t("optTick2")}</div></div>
            <div class="tick"><div class="mark">✓</div><div class="text">${t("optTick3")}</div></div>
          </div>
          <div class="pair-actions">
            <button class="btn large" id="start">${t("pairMyPhone")}</button>
          </div>
        </div>
        <div class="pair-side">
          <div style="width:132px;height:246px;border-radius:26px;border:2.5px solid rgba(27,26,23,.22);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px">
            <div class="brand-tile" style="width:34px;height:34px;border-radius:11px;font-size:15px">2</div>
            <div style="font-size:12.5px;color:rgba(27,26,23,.45);text-align:center;line-height:1.45;padding:0 16px">${t("optGetApp")}</div>
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
          <div class="pair-hero" style="font-size:28px">${t("optScanErrTitle")}</div>
          <div class="pair-copy">${t("optScanErrCopy")}</div>
          <div class="pair-actions"><button class="btn large" id="retry">${t("tryAgain")}</button></div>
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
          <div class="pair-hero" style="font-size:30px">${t("optScanTitle")}</div>
          <div class="pair-copy" style="font-size:15.5px;max-width:360px">${t(
            "optScanCopy",
            [`<b style="color:var(--ink);font-weight:600">${t("optScanPath")}</b>`],
          )}</div>
          <div class="waiting-line">
            <div class="waiting-dot"></div>
            ${t("optWaitingPhone")}
          </div>
          <button class="btn ghost" id="back" style="margin-top:26px;padding-left:0">${t("optBack")}</button>
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
    let phoneName = t("optDefaultPhone");
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
    // A new pairing rotates the session key, so any prior key-route state (the
    // wrapped master key + the cached replica) is orphaned and would fill stale
    // codes. Clear it; the person re-enables key sign-in to get a fresh vault.
    await disableKeyRoute();
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
        <div class="paired-title">${t("optPairedTitle", [esc(pairing.phoneName)])}</div>
        <div class="paired-copy">${t("optPairedCopy")}</div>
        <div class="device-row">
          <div class="tile">${esc(pairing.phoneName[0]?.toUpperCase() ?? "P")}</div>
          <div class="grow">
            <div class="title">${esc(pairing.phoneName)}</div>
            <div class="subtitle">${t("optPairedJustNow")}</div>
          </div>
          <div class="badge">${t("optActive")}</div>
        </div>
        <div class="pair-actions">
          <button class="btn large" id="done">${t("optDone")}</button>
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
  const keyEnrolled = await isEnrolled();
  const uiLang = await getUiLang();
  const langOptions = [
    `<option value="auto"${uiLang === "auto" ? " selected" : ""}>${t("optLanguageAuto")}</option>`,
    ...UI_LANGUAGES.map(
      (l) =>
        `<option value="${l.code}"${uiLang === l.code ? " selected" : ""}>${esc(l.name)}</option>`,
    ),
  ].join("");

  const agoDays = Math.floor((Date.now() - pairing.pairedAt) / 86_400_000);
  const months = Math.floor(agoDays / 30);
  const pairedAgo =
    agoDays === 0
      ? t("optToday")
      : agoDays === 1
        ? t("optYesterday")
        : agoDays < 30
          ? t("optDaysAgo", [agoDays])
          : months === 1
            ? t("optMonthAgo", [months])
            : t("optMonthsAgo", [months]);

  const ruleLabel = {
    "always-phone": t("optRuleAlwaysPhone"),
    "never-autofill": t("optRuleNeverAutofill"),
  } as const;

  page.replaceChildren(
    el(`<div>
      <div class="page-head">
        <div class="brand-tile">2</div>
        <div class="page-title">${t("optSettingsTitle")}</div>
      </div>

      <div class="section-label">${t("optSecWhenAsks")}</div>
      <div class="card">
        <div class="row">
          <div class="grow">
            <div class="title">${t("optFillAuto")}</div>
            <div class="subtitle">${t("optFillAutoSub")}</div>
          </div>
          <button class="toggle${settings.autofill ? " on" : ""}" data-key="autofill"><div class="knob"></div></button>
        </div>
        <div class="row">
          <div class="grow">
            <div class="title">${t("optSubmit")}</div>
            <div class="subtitle">${t("optSubmitSub")}</div>
          </div>
          <button class="toggle${settings.autoSubmit ? " on" : ""}" data-key="autoSubmit"><div class="knob"></div></button>
        </div>
        ${
          keyEnrolled
            ? `<div class="row">
          <div class="grow">
            <div class="title">${t("optLeadKey")}</div>
            <div class="subtitle">${t("optLeadKeySub")}</div>
          </div>
          <button class="toggle${settings.preferKey ? " on" : ""}" data-key="preferKey"><div class="knob"></div></button>
        </div>`
            : ""
        }
      </div>

      <div class="section-label">${t("optLanguage")}</div>
      <div class="card">
        <div class="row">
          <div class="grow">
            <div class="title">${t("optLanguage")}</div>
            <div class="subtitle">${t("optLanguageSub")}</div>
          </div>
          <select class="vault-search" id="ui-lang" style="max-width:190px">${langOptions}</select>
        </div>
      </div>

      <div class="section-label">${t("optSecSiteRules")}</div>
      <div class="card" id="rules"></div>

      <div class="section-label">${t("optSecKeys")} <span style="opacity:.6;font-weight:500">${t("optExperimental")}</span></div>
      <div class="card" id="security-keys"></div>
      <div class="sub" style="margin-top:10px">${t("optKeysBlurb")}</div>

      <div class="section-label">${t("optSecDevices")}</div>
      <div class="card">
        <div class="row">
          <div class="device-row" style="margin:0;background:none;padding:0">
            <div class="tile">${esc(pairing.phoneName[0]?.toUpperCase() ?? "P")}</div>
            <div class="grow">
              <div class="title">${esc(pairing.phoneName)}</div>
              <div class="subtitle">${t("optPaired", [pairedAgo])}${pairing.lastUsedAt ? ` · ${t("optLastUsed")}` : ""}</div>
            </div>
            <button class="small-outline" id="unpair">${t("unpair")}</button>
          </div>
        </div>
      </div>
      <div class="sub" style="margin-top:10px">${t("optUnpairNote")}</div>
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

  // Display language: browser by default, or a manual pick. Never the phone's.
  document.getElementById("ui-lang")!.addEventListener("change", async (e) => {
    await setUiLang((e.target as HTMLSelectElement).value);
    void renderSettings(); // re-render in the newly chosen language
  });

  // Site rules
  const rules = document.getElementById("rules")!;
  const entries = Object.entries(settings.siteRules);
  if (entries.length === 0) {
    rules.appendChild(
      el(`<div class="subtitle" style="font-size:13.5px;color:var(--ink-55)">
        ${t("optNoRules")}</div>`),
    );
  }
  for (const [domain, rule] of entries) {
    const row = el(`<div class="row">
      <div class="grow"><div class="title" style="font-size:14.5px">${esc(domain)}</div></div>
      <div class="subtitle">${ruleLabel[rule]}</div>
      <button class="small-outline">${t("remove")}</button>
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
    <input class="vault-search" id="rule-domain" placeholder="${t("optRulePlaceholder")}" style="max-width:280px">
    <button class="small-outline" id="add-never">${t("optRuleNeverAutofill")}</button>
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
    await disableKeyRoute(); // drop the wrapped key + cached replica with the pairing
    renderIntro();
  });
}

// ---- "Touch your key": register + validate security keys -------------------

/** (Re)build the security-keys card: registered keys, add, and a touch test
 * that confirms a touch unlocks the vault on the real hardware. */
async function populateSecurityKeys(): Promise<void> {
  const card = document.getElementById("security-keys");
  if (!card) return;
  card.replaceChildren();

  if (!webauthnAvailable()) {
    card.appendChild(
      el(`<div class="subtitle" style="font-size:13.5px;color:var(--ink-55)">
        ${t("optNoWebauthn")}</div>`),
    );
    return;
  }

  const status = el(
    `<div class="subtitle" style="font-size:13px;color:var(--ink-55);margin-top:6px"></div>`,
  );

  const keys = await getSecurityKeys();
  for (const k of keys) {
    const state = k.prfConfirmed
      ? `<span style="color:var(--green)">${t("optKeyReady")}</span>`
      : `<span style="color:var(--ink-55)">${t("optKeyNotConfirmed")}</span>`;
    const row = el(`<div class="row">
      <div class="tile">⚿</div>
      <div class="grow">
        <div class="title" style="font-size:14.5px">${esc(k.label)}</div>
        <div class="subtitle">${t("optAddedOn", [new Date(k.addedAt).toLocaleDateString()])} · ${state}</div>
      </div>
      <button class="small-outline">${t("remove")}</button>
    </div>`);
    row.querySelector("button")!.addEventListener("click", async () => {
      await removeSecurityKey(k.credentialIdB64);
      await populateSecurityKeys();
    });
    card.appendChild(row);
  }

  const addRow = el(`<div class="row">
    <input class="vault-search" id="sk-label" placeholder="${t("optKeyNamePlaceholder")}" style="max-width:240px">
    <button class="small-outline" id="sk-add">${t("optAddKey")}</button>
  </div>`);
  addRow.querySelector("#sk-add")!.addEventListener("click", async () => {
    const label =
      (document.getElementById("sk-label") as HTMLInputElement).value.trim() ||
      t("optDefaultKeyLabel");
    status.textContent = t("optTouchKey");
    try {
      const res = await registerKey(label);
      await addSecurityKey({
        credentialIdB64: res.credentialIdB64,
        label,
        addedAt: Date.now(),
        prfConfirmed: false,
      });
      status.textContent = res.prfSupported
        ? t("optKeyRegistered", [label])
        : t("optKeyRegisteredWarn", [label]);
      await populateSecurityKeys();
    } catch (e) {
      status.textContent = t("optRegisterFailed", [(e as Error).message]);
    }
  });
  card.appendChild(addRow);

  if (keys.length > 0) {
    const testRow = el(`<div class="row">
      <div class="grow"><div class="subtitle" style="font-size:13.5px">${t("optConfirmTouch")}</div></div>
      <button class="small-outline" id="sk-test">${t("optTestUnlock")}</button>
    </div>`);
    testRow.querySelector("#sk-test")!.addEventListener("click", async () => {
      status.textContent = t("optTouchKey");
      try {
        const ids = (await getSecurityKeys()).map((k) => k.credentialIdB64);
        const { credentialIdB64 } = await deriveKek(ids);
        await confirmSecurityKey(credentialIdB64);
        const used = (await getSecurityKeys()).find(
          (k) => k.credentialIdB64 === credentialIdB64,
        );
        status.textContent = t("optUnlockOk", [used?.label ?? t("optYourKey")]);
        await populateSecurityKeys();
      } catch (e) {
        status.textContent = t("optUnlockFailed", [(e as Error).message]);
      }
    });
    card.appendChild(testRow);
  }

  // Enable / manage the actual sign-in route (needs a confirmed key).
  const confirmed = keys.filter((k) => k.prfConfirmed);
  if (confirmed.length > 0 && !(await isEnrolled())) {
    const enableRow = el(`<div class="row">
      <div class="grow"><div class="subtitle" style="font-size:13.5px">${t("optTurnOnKeySignin")}</div></div>
      <button class="small-outline" id="sk-enable">${t("optEnableKeySignin")}</button>
    </div>`);
    enableRow.querySelector("#sk-enable")!.addEventListener("click", async () => {
      status.textContent = t("optTouchKey");
      try {
        const { label } = await enrollFirstKey();
        status.textContent = t("optKeySigninOn", [label]);
        await populateSecurityKeys();
      } catch (e) {
        status.textContent = t("optEnableFailed", [(e as Error).message]);
      }
    });
    card.appendChild(enableRow);
  } else if (confirmed.length > 0) {
    const onRow = el(`<div class="row">
      <div class="grow">
        <div class="title" style="font-size:14.5px;color:var(--green)">${t("optKeySigninIsOn")}</div>
        <div class="subtitle">${t("optKeySigninIsOnSub")}</div>
      </div>
    </div>`);
    card.appendChild(onRow);

    for (const k of confirmed.filter((c) => !c.wrappedKB64)) {
      const addToRow = el(`<div class="row">
        <div class="grow"><div class="subtitle" style="font-size:13.5px">${t("optAddBackup", [esc(k.label)])}</div></div>
        <button class="small-outline">${t("optAddToSignin")}</button>
      </div>`);
      addToRow.querySelector("button")!.addEventListener("click", async () => {
        status.textContent = t("optTouchEnrolledThenNew");
        try {
          const { label } = await addTouchedKey(k.credentialIdB64);
          status.textContent = t("optBackupAdded", [label]);
          await populateSecurityKeys();
        } catch (e) {
          status.textContent = t("optAddFailed", [(e as Error).message]);
        }
      });
      card.appendChild(addToRow);
    }

    const offRow = el(`<div class="row">
      <div class="grow"></div>
      <button class="small-outline" id="sk-off">${t("optTurnOffKeySignin")}</button>
    </div>`);
    offRow.querySelector("#sk-off")!.addEventListener("click", async () => {
      await disableKeyRoute();
      status.textContent = t("optKeySigninOff");
      await populateSecurityKeys();
    });
    card.appendChild(offRow);
  }

  card.appendChild(status);
}

// ---- Boot -----------------------------------------------------------------

void (async () => {
  await initI18n(); // resolve the chosen (or browser) language before rendering
  const pairing = await getPairing();
  if (pairing) await renderSettings();
  else renderIntro();
})();
