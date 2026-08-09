# Handoff — Cross-platform 2FA authenticator (Authy replacement)

> Build brief for Claude Code. This describes a TOTP authenticator built around one
> hard security rule and one signature convenience feature. Read the whole thing before
> writing code — the crypto design and the "two separate devices" rule are load-bearing
> and shape every decision.

---

## 1. What we're building

A two-factor (TOTP) authenticator with two client surfaces:

- **Browser extension** — the hero surface. Detects 2FA login pages, identifies the right
  entry by domain, and autofills the six-digit code.
- **Mobile app (iOS + Android)** — companion + the "separate second device" for users
  without a hardware key.

**No standalone desktop app in v1.** Add one later only if users hit needs outside the
browser (desktop programs, VPN clients). The extension is the whole desktop experience for now.

The pain we're killing: the ritual of finding your phone, unlocking it, opening the app,
scrolling to the right entry, squinting at a code, typing it before it expires, and putting
the phone away. We delete that.

---

## 2. Non-negotiable principles

These are not optional and must survive every implementation decision:

1. **Two factors always live on two physically separate devices — never collapsed onto one
   machine.** On a computer, the second factor is always either a hardware key plugged in,
   OR the phone acting as the separate device. **A master password alone on the same machine
   as the browser is never sufficient.** (This is the mistake Authy/Bitwarden make; we refuse it.)

2. **Zero-knowledge storage.** TOTP secrets are encrypted on-device. The server only ever
   holds unreadable encrypted blobs + routing metadata. We never hold the decryption key.
   A full server breach must leak only ciphertext.

3. **The server is a dumb pipe.** It stores encrypted blobs and relays encrypted messages
   between paired devices. It never sees a plaintext secret or a plaintext code. Keep the
   backend attack surface as small as possible.

4. **Biometrics (Face ID / Touch ID / Windows Hello) are a local unlock only** — they do NOT
   count as the separate second factor. They gate a key that already lives on that device.

---

## 3. V1 scope

**In:**
- Browser extension (Chrome first) with page detection, domain matching, autofill.
- Mobile app (iOS + Android): vault, QR-scan add-entry, approval push handling, onboarding, recovery.
- Zero-knowledge sync backend.
- Two desktop unlock paths: key-first (YubiKey/FIDO2) and phone-handoff.
- End-to-end encrypted backup + offline recovery kit.

**Out (defer):**
- Standalone native desktop app.
- Watch app / other second-device form factors.
- Team/family shared vaults.

---

## 4. Architecture

Four backend pieces, all deliberately minimal:

1. **Sync API + database** — accounts, device registry, per-user encrypted vault blob.
   The blob is encrypted client-side; the server cannot open it.
2. **Push dispatch** — FCM (Android) + APNs (iOS) to wake the phone when the browser
   requests a code.
3. **Handoff relay** — a realtime channel (WebSocket) passing messages between a paired
   extension and phone. Messages are **end-to-end encrypted with a pairing key the two
   devices share**, so the relay forwards ciphertext it can't read.
4. **Client-side crypto layer** — not infrastructure but load-bearing (see §6).

**The code path (important):** a TOTP code is never stored and never comes from the server.
The extension holds the encrypted vault locally and generates codes offline:
reconstruct decryption key → decrypt blob → pull the entry's TOTP secret →
`HMAC(secret, current_time)` → six digits → autofill. All local.

---

## 5. Tech stack (recommended — adjust if you have a strong reason)

- **Language:** TypeScript across extension + backend (shared crypto/types).
- **Backend:** Node.js. Hosting on **Render** (user already uses Render web services + Postgres).
- **Database:** Postgres.
- **Crypto lib:** libsodium (`libsodium-wrappers`) — XChaCha20-Poly1305 for encryption,
  Argon2id for password KDF, BLAKE2b for derivations.
- **Extension:** Manifest V3, Chrome first. WebAuthn (incl. PRF extension) is browser-native.
- **Mobile:** pick one — React Native (code-share with the TS stack) or native Swift/Kotlin
  (better secure-enclave + APNs/FCM ergonomics). Flag the tradeoff to the user before committing.
- **Realtime:** WebSocket (e.g. `ws` on the backend). Keep messages E2E-encrypted end to end.

---

## 6. Crypto design (the load-bearing part)

### Vault encryption
- Vault (all TOTP secrets) is a JSON structure encrypted as one blob with XChaCha20-Poly1305.
- The vault key is derived, never stored. Never persist the vault key or plaintext to disk.

### Deriving the vault key — three unlock methods
1. **Master password** — Argon2id(password, salt) → vault key. Password never leaves the device,
   never sent to the server. (This is the fallback / mobile-local unlock, and always the base layer.)
2. **FIDO2 PRF** (modern, browser-native, preferred for the extension) — WebAuthn's PRF extension
   returns a stable 32-byte secret for a fixed challenge (same challenge → same output). Feed it
   through a KDF → vault key. Chrome supports this directly, no native helper needed.
3. **YubiKey HMAC-SHA1 challenge-response** (the KeePassXC approach) — send a fixed challenge,
   the key HMACs it with a secret that never leaves the hardware, returns a stable response →
   KDF → vault key. In a pure extension this needs WebUSB or a native-messaging helper, so
   **prefer PRF where available; offer HMAC challenge-response as the fallback for older keys.**

The key's ONLY job is reconstructing the decryption key. It never holds the code or the secret.

### Storing the encrypted blob locally is safe — here's why
Storing the *encrypted* blob on disk is fine **because the decryption key is never stored next
to it.** The key is reconstructed from the physical device (YubiKey / FIDO2) at unlock time and
never persisted. An attacker who remotely breaches the laptop and exfiltrates the blob still has
unreadable garbage — they'd need to physically touch the key in the USB port. This is exactly why
the "two separate devices" rule holds even though the blob sits on the same machine: the ciphertext
is one thing, the physical key is the separate factor.

### Device pairing
- Pairing the extension ↔ phone happens once via QR scan and establishes a shared **pairing key**.
- The handoff relay only ever forwards messages encrypted with this pairing key.

### Recovery kit
- At onboarding, generate an **offline recovery key** capable of decrypting the vault if every
  device is lost. User stores it themselves (print / save).
- **Sharp edge:** in a true zero-knowledge system, if the recovery kit is lost AND all devices are
  gone, the vault is genuinely unrecoverable — we cannot decrypt it for them. Design this moment
  carefully and communicate it clearly in-product.

---

## 7. Data model (sketch)

- `users` — id, auth credentials for sync access only (NOT the vault key), created_at.
- `devices` — id, user_id, type (extension | ios | android), public key / pairing metadata,
  push token (FCM/APNs), last_seen.
- `vault_blobs` — user_id, ciphertext, nonce, version, updated_at. (Opaque to the server.)
- `pairings` — links a device pair; stores only what's needed to route, never the pairing key.
- No table ever contains a plaintext TOTP secret or a plaintext code.

---

## 8. Core flows to implement

**Onboarding**
Create account → set master password (never sent up) → register this device → generate + save
offline recovery kit → pair a second device by QR (also establishes the extension↔phone pairing key).

**Add a 2FA entry**
Scan the QR on the phone (or paste in the extension) → secret encrypts locally → encrypted vault syncs.

**Desktop login — key-first (no phone)**
Extension detects the 2FA field and reads the domain → finds the matching entry in the locally-synced
encrypted vault → prompts "touch your key" → key reconstructs the vault key → vault decrypts locally →
code generated in the extension → autofilled. No phone, no server round-trip for the code.

**Desktop login — phone-handoff (no key)**
Extension detects field + domain → sends push through the relay → phone opens straight to the correct
entry showing "Approve login to `<domain>`?" → user approves with biometrics → phone generates the code
and sends ONLY the six digits, E2E-encrypted, back through the relay → extension autofills. The secret
never leaves the phone; the laptop receives one throwaway code.

**Recovery**
Lost phone but another device registered → re-pair a replacement. Lost everything → recovery kit
decrypts a fresh install. Surface this loudly and reassuringly in the UI — calm recovery is a
differentiator, not fine print.

---

## 9. Suggested build order

1. Crypto core (vault encrypt/decrypt, Argon2id KDF, blob format) — as a shared, unit-tested module.
2. Sync backend (accounts, device registry, blob upload/download) on Render + Postgres.
3. Mobile app: onboarding, add-entry (QR), local vault, master-password + biometric unlock.
4. Extension: vault sync, page detection, domain matching, TOTP generation, autofill (password unlock first).
5. FIDO2 PRF unlock in the extension (key-first path).
6. Handoff relay + push (phone-handoff path) end to end.
7. Recovery kit generation + restore flow.
8. YubiKey HMAC challenge-response fallback (WebUSB / native helper).

---

## 10. Security caveats to respect

- **Decrypt only the single needed entry**, not the whole vault, at autofill time.
- **Never keep the vault decrypted in the background.** Require a fresh key touch per use or a short
  session timeout.
- At the instant of code generation the plaintext secret is briefly in browser memory — unavoidable
  for any autofill authenticator. Minimize the window; don't persist.
- Note the honest tradeoff: the phone-handoff path is stricter (secret never touches the laptop);
  the key-first local path trades a sliver of that for needing no phone. Both are acceptable; keep
  the distinction visible in design/docs.
- Backups must be truly end-to-end encrypted (contrast: 2FAS's iCloud backup is not).

---

## 11. Competitive context (for judgment calls, not a feature list)

Each competitor does a piece; none assemble all of it:
- **Yubico Authenticator** — key-first, secrets on the key, but no browser autofill and no phone fallback.
- **2FAS** — has the phone push-back flow, but forces a phone tap every time, no key-first path, and
  its iCloud backup isn't E2E encrypted.
- **Bitwarden / 1Password** — autofill TOTP, but collapse both factors into one vault on one device.

Our wedge: browser-initiated, domain-aware, key-first with phone fallback, on top of the never-one-device
rule and zero-knowledge storage. When a design tradeoff is ambiguous, favor the option that preserves
device separation and keeps the server blind.

---

## 12. Open questions to resolve with the user

- Product name / branding.
- Mobile framework choice (React Native vs native) — flag the secure-enclave/push tradeoff.
- Which browsers beyond Chrome for v1 (Firefox uses a different WebAuthn/extension story).
- Monetization / account model (does sync require a paid account?).
