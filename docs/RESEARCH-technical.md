# TOTP Authenticator App + Browser Extension: Technical Research Report

Research conducted 2026-08-09 via web search. Scope: Android-first TOTP authenticator with encrypted backup, push-approval login, companion browser extension, self-hosted backend.

---

## 1. TOTP Correctness (RFC 6238 and otpauth:// parsing)

### Algorithm edge cases
- RFC 6238 has three configurable parameters that must match between server and client or codes never align: **digits** (default 6, but 8 exists), **period** (default 30s, but 60s and even 15s occur in the wild), and **HMAC algorithm** (default SHA-1; SHA-256/SHA-512 are valid but break compatibility with apps that ignore the parameter). The RFC ships official test vectors for SHA1/SHA256/SHA512 — wire them into unit tests. ([RFC 6238](https://www.rfc-editor.org/rfc/rfc6238.html), [Authgear: 5 common TOTP mistakes](https://www.authgear.com/post/5-common-totp-mistakes/))
- Important nuance from the SHA-256/512 test vectors: the RFC test secrets are *different lengths* per algorithm (20/32/64 bytes). Many buggy implementations fail these vectors because they reuse the 20-byte seed. Implement HOTP truncation exactly (dynamic offset from low nibble of last byte, 31-bit masking, modulo 10^digits, left-pad with zeros — "007123" must display leading zeros).
- Compute the counter as `floor(unix_time / period)` using 64-bit math; show a countdown derived from `period - (time mod period)`, not a hardcoded 30.
- Clock skew: an authenticator app should surface a "time sync" feature (compare device time against NTP or your server) rather than silently generating wrong codes; skewed device clocks are the #1 support issue for authenticators.

### otpauth:// URI parsing quirks (all seen in real-world QR codes)
- **Secret encoding**: always Base32 (RFC 4648 alphabet A-Z2-7), but real QR codes contain **unpadded** secrets (padding "SHOULD be omitted" per the Key URI spec), **lowercase** letters, embedded **spaces/dashes**, and lengths not divisible by 8. Robust parsing: strip whitespace/dashes, uppercase, decode with padding disabled/tolerated. Do not reject on missing `=`. ([Key Uri Format wiki](https://github.com/google/google-authenticator/wiki/Key-Uri-Format), [Yubico URI format docs](https://docs.yubico.com/yesdk/users-manual/application-oath/uri-string-format.html), [draft-andesco-otpauth-uri](https://www.ietf.org/archive/id/draft-andesco-otpauth-uri-00.html))
- **Issuer duplication**: issuer can appear in the label prefix (`otpauth://totp/GitHub:alice@example.com`) and/or as `issuer=` query param. If both are present they should be equal but often aren't; prefer the query param, fall back to the label prefix, and don't display "GitHub: GitHub — alice". Handle URL-encoded colons (`%3A`) and spaces (`%20` and `+`) in labels.
- Accept-but-warn on unknown `algorithm` values; treat missing params as defaults (SHA1/6/30). Some providers (notably Steam) use nonstandard 5-character alphanumeric codes — decide explicitly whether to support `steam://` style entries (Aegis does).
- Support `otpauth://hotp/` with `counter=` if you want full import compatibility, even if you de-prioritize HOTP UX.

### otpauth-migration:// (Google Authenticator export)
- Format: `otpauth-migration://offline?data=<base64 protobuf>`. The `data` param is URL-encoded base64 — **URL-decode first** (a `+` mangled into a space is a classic import bug), then base64-decode, then parse a `MigrationPayload` protobuf. ([alexbakker.me deep dive](https://alexbakker.me/post/parsing-google-auth-export-qr-code.html), [qistoph/otp_export](https://github.com/qistoph/otp_export), [dim13/otpauth decoder](https://github.com/dim13/otpauth))
- Schema (reverse-engineered, no official definition): repeated `OtpParameters { bytes secret; string name; string issuer; Algorithm algorithm; DigitCount digits; OtpType type; int64 counter; }` plus batching fields `version`, `batch_size`, `batch_index`, `batch_id`. Enums include `UNSPECIFIED = 0` — map 0 to defaults (SHA1, 6 digits, TOTP). The secret arrives as **raw bytes**, not Base32 — re-encode to Base32 for internal storage consistency.
- Multi-QR exports: Google splits >10 accounts across several QR codes; use `batch_size`/`batch_index`/`batch_id` to drive a "scan 2 of 3" import UI and dedupe re-scans.
- Also implement the *export* side of this format — it's the de-facto interchange format between authenticators.

---

## 2. Android Specifics

### Keystore pitfalls
- `setInvalidatedByBiometricEnrollment(true)` (the default for biometric-bound keys) permanently invalidates keys when the user adds/removes a fingerprint or face. For an authenticator this is catastrophic **if the Keystore key is the only thing encrypting the vault** — the user loses all tokens. Architecture fix (this is what Aegis does): a random **master key** encrypts the vault; the Keystore/biometric key and the password-derived key are each independent "slots" that wrap a copy of the master key. Biometric invalidation then only forces password re-entry, never data loss. Handle `KeyPermanentlyInvalidatedException` and `UserNotAuthenticatedException` gracefully. ([Android Keystore docs](https://developer.android.com/privacy-and-security/keystore), [BiometricPrompt + CryptoObject](https://medium.com/androiddevelopers/using-biometricprompt-with-cryptoobject-how-and-why-aace500ccdb7), [Aegis vault design](https://github.com/beemdevelopment/Aegis/blob/master/docs/vault.md))
- Real-world device bugs: Pixel 4 face unlock "improves" its model on each unlock and triggered spurious key invalidation in Aegis ([Aegis issue #824](https://github.com/beemdevelopment/Aegis/issues/824)); Samsung devices have thrown `UnrecoverableKeyException` after OS/security updates ([Samsung dev forum](https://forum.developer.samsung.com/t/unrecoverablekeyexception-after-software-or-security-updates/5917)). Keystore keys are also non-exportable and do not survive to a new device — never treat Keystore as durable storage, only as a convenience unlock layer.
- **StrongBox** (`setIsStrongBoxBacked(true)`): dedicated secure element, stronger than TEE, but only on some devices, slower, and limited algorithm support — attempt StrongBox, catch `StrongBoxUnavailableException`, fall back to TEE. ([TEE vs StrongBox](https://www.comviva.com/blog/safeguarding-cryptographic-keys-implementing-tee-and-strongbox-in-android-applications/))

### Screenshot blocking
- Set `WindowManager.LayoutParams.FLAG_SECURE` on activities showing codes/secrets: blocks screenshots, screen recording, and the recents-screen thumbnail. Make it a setting (default on) — users legitimately need screenshots of QR export screens sometimes; Android 15 adds screen-record detection APIs as a complement.

### Backup rules
- `android:allowBackup="false"` is not sufficient on Android 12+: it disables cloud backup but **does not reliably disable device-to-device (D2D) transfer** on some OEMs. Use `android:dataExtractionRules` (API 31+) with separate `<cloud-backup>` and `<device-transfer>` sections, plus legacy `android:fullBackupContent` for API ≤ 30. ([Auto Backup docs](https://developer.android.com/identity/data/autobackup), [Backup best practices](https://developer.android.com/privacy-and-security/risks/backup-best-practices))
- Recommended posture: exclude the vault file and Keystore-related prefs from both cloud backup and D2D transfer; provide your own **explicitly encrypted** export/backup instead (Section 3). The USENIX study found unencrypted OS-level backup of TOTP secrets to be a widespread failure mode ([Gilsenan et al., USENIX Sec '23](https://www.usenix.org/system/files/usenixsecurity23-gilsenan.pdf)).

### Clipboard (Android 13+)
- When copying a code, set `ClipDescription.EXTRA_IS_SENSITIVE` (`android.content.extra.IS_SENSITIVE` for older APIs) so the code is hidden from clipboard preview UI and keyboard suggestion strips. Android 13 auto-clears the system clipboard after ~1 hour — too long for OTPs; schedule your own clear after ~30–60s (note: background clipboard clearing is restricted; clear on your own copied clip when app regains focus, or use a foreground-timed approach). Android 12+ shows a toast when other apps read the clipboard. ([Secure clipboard handling](https://developer.android.com/privacy-and-security/risks/secure-clipboard-handling), [Microsoft on Android clipboard exposure](https://www.microsoft.com/en-us/security/blog/2023/03/06/protecting-android-clipboard-content-from-unintended-exposure/))

### Google Play requirements
- **Data Safety form**: must accurately declare collection/sharing; for a local-first authenticator you can declare no collection only if analytics/crash SDKs are absent or disabled — third-party SDK data flows count as *your* collection.
- **Account deletion**: if your app supports account creation (your sync/push backend will), Play requires an **in-app account deletion path plus a public web URL** for deletion requests; enforced since April/May 2024. 2FA/OTP-based auth explicitly counts as an "account". ([Play Console help](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en), [Data Safety + deletion community guide](https://support.google.com/googleplay/android-developer/community-guide/246344978/about-the-data-safety-form-and-account-deletion?hl=en))

---

## 3. Encrypted Backup Design

### How the good open-source apps do it
- **Aegis** (best-documented design, [vault.md](https://github.com/beemdevelopment/Aegis/blob/master/docs/vault.md)): random 256-bit **master key** encrypts vault JSON with **AES-256-GCM** (96-bit random nonce). Multiple **slots** each hold the master key wrapped by a credential: (a) password slot via **scrypt N=2^15, r=8, p=1**, 256-bit random salt; (b) biometric slot via Android Keystore key. This slot design is the key takeaway: it decouples "what encrypts the data" from "how the user unlocks it".
- **2FAS**: backup encrypted with **AES-GCM + PBKDF2-HMAC-SHA256 at only 10,000 iterations** — far below OWASP's 600,000-iteration recommendation; a documented weakness to avoid copying. ([2fas-backup-decryptor](https://github.com/elliotwutingfeng/2fas-backup-decryptor), [2FAS backup safety FAQ](https://2fas.com/support/2fas-auth-security-privacy/is-2fas-backup-safe/))
- **Ente Auth**: full E2EE sync built on **libsodium**: `crypto_secretbox` (XSalsa20-Poly1305) / `crypto_pwhash` = **Argon2id v1.3 with SENSITIVE ops/mem limits** (adaptively halving memory and doubling ops if the device can't allocate); separate 256-bit masterKey and **recoveryKey**, mutually encrypting each other so either can recover the account. ([Ente architecture](https://github.com/ente-io/ente/blob/main/architecture/README.md), [Ente Auth](https://ente.com/auth/))
- The USENIX '23 study of 22 TOTP apps: most backup schemes reintroduce trust in passwords/SMS/email, several had outright crypto flaws or let developers read secrets in plaintext, and almost none warned users about plaintext exports. Design lesson: E2EE by default, no SMS/email recovery, warn loudly on any plaintext export. ([paper](https://www.usenix.org/system/files/usenixsecurity23-gilsenan.pdf), [artifacts repo](https://github.com/blues-lab/totp-app-analysis-public))

### 12-word recovery phrase (BIP39-style)
- BIP39 gives you: 128 bits of entropy → 12 words (checksummed word list), and a standard KDF: **PBKDF2-HMAC-SHA512, 2048 iterations, salt = "mnemonic"+passphrase** → 512-bit seed. ([BIP-39 explainers: Zelcore](https://zelcore.io/academy/security/seed-phrases-in-depth), [Ledger](https://www.ledger.com/academy/bip-39-the-low-key-guardian-of-your-crypto-freedom))
- Recommended pattern for an authenticator: generate a random 128-bit recovery entropy → display as 12 words → derive a **recovery key** (HKDF from the BIP39 seed) → use it to wrap the vault master key as an additional slot (Aegis-style) or to encrypt the masterKey server-side (Ente-style). The low PBKDF2 iteration count is fine here because the input is full-strength random entropy, not a human password — no stretching needed. The phrase is never stored by you; only the wrapped master key is.

### Recommended stack for a new implementation
libsodium everywhere (audited, cross-platform for Android/iOS/extension via WASM): Argon2id (interactive limits for unlock, moderate/sensitive for backup files), XChaCha20-Poly1305 for vault/backup AEAD, versioned JSON envelope `{version, kdf_params, salt, nonce, ciphertext}` so parameters can be raised later without breaking old backups.

---

## 4. Push-Approval Architecture

### Request lifecycle (Duo model)
- Server creates a signed auth transaction (`txid`); push notification wakes the phone app; app fetches transaction details over TLS from the API (not from the push payload); user approves/denies; relying party **long-polls `/auth_status`** with the txid; **push expires after 60 seconds** (Duo's contract; response info retained 120s server-side, then 404). Use async-create + poll rather than a blocking call. ([Duo Auth API](https://duo.com/docs/authapi), [Duo API guide](https://duo.com/docs/authapi-guide))
- Replay protection essentials: single-use txid, server-side state machine (pending → approved/denied/expired, no transitions out of terminal states), approval message **signed by a device-held private key** (registered at enrollment, ideally in Keystore/StrongBox) over `txid + decision + timestamp`, server verifies signature and freshness.

### Number matching (mandatory, not optional)
- **MFA fatigue / push bombing**: attacker with a valid password spams pushes until the victim approves. The Uber 2022 breach is the canonical case: an external contractor received ~40 pushes in 30 minutes, then the attacker posed as IT on WhatsApp and got an approval — full compromise followed. ([UpGuard analysis](https://www.upguard.com/blog/what-caused-the-uber-data-breach), [ManageEngine breakdown](https://www.manageengine.com/products/desktop-central/blog/uber-data-breach-2022-how-the-hacker-annoyed-his-way-into-the-network-and-our-learnings.html))
- Mitigation: **number matching** — the initiating device (browser extension) displays a 2–3 digit number the user must type/select in the phone app; a victim who didn't initiate the login can't complete it. CISA explicitly recommends it; Duo's "Verified Duo Push" and Microsoft Entra (default since 2023) implement it. Number matching alone isn't sufficient — combine with rate-limiting pushes per user, auto-lock after N denials, and showing rich context (geo/IP, browser, target site) in the approval screen. ([CISA fact sheet](https://www.cisa.gov/sites/default/files/publications/fact-sheet-implement-number-matching-in-mfa-applications-508c.pdf), [Duo Verified Push](https://duo.com/blog/verified-duo-push-makes-mfa-more-secure), [Authsignal: why number matching alone is not enough](https://www.authsignal.com/blog/articles/push-authentication-best-practices-and-why-number-matching-alone-is-not-enough))

### What should be E2EE between extension and phone
Since you control both endpoints, the approval *content* should be end-to-end encrypted with the pairing keys (Section 6), so your relay server sees only opaque blobs and routing metadata: the challenge/number, requesting site origin, browser fingerprint/context, and the signed approval response. The server's job is store-and-forward + expiry, never plaintext access — this also neutralizes server compromise as an approval-forgery vector.

**Purr note:** our approval releases a TOTP code only to the *paired, E2E-keyed browser* — an attacker spamming pushes can never receive the code on their own device, unlike Duo-style "approve this login" flows. Push-bombing is therefore an annoyance/social-engineering risk, not a direct account-takeover vector. Mitigations kept: rich context in A11, "I didn't ask for this" as a first-class deny, per-site mute, rate limiting per pairing.

---

## 5. Browser Extension (Manifest V3)

### Service worker constraints
- MV3 service workers are killed after **~30 seconds of inactivity** (hard cap 5 minutes for a single event); no persistent background page. Any in-memory state (decrypted vault, WebSocket, session keys) evaporates. ([SW lifecycle docs](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle))
- **WebSocket**: since Chrome 116, WebSocket activity resets the idle timer — exchange an application-level keepalive every ~20s to stay alive; on older Chrome the socket dies with the worker. Fallbacks: an **offscreen document** holding the socket, a content-script `chrome.runtime.connect()` port, or `chrome.alarms` (min ~30s/1min granularity) to periodically reconnect. ([Chrome 116 notes](https://developer.chrome.com/blog/chrome-116-beta-whats-new-for-extensions), [WebSockets in service workers guide](https://developer.chrome.com/docs/extensions/how-to/web-platform/websockets))
- Design consequence: **don't architect around a permanently-open connection**. Prefer: extension initiates (user clicks → connect → do the approval/fill → disconnect), state persisted in `chrome.storage.session` (memory-backed, cleared on browser exit, can be locked to trusted contexts) rather than SW globals.

### TOTP autofill (Bitwarden/1Password patterns)
- Bitwarden's approach: on login autofill, it (a) heuristically detects OTP inputs — `autocomplete="one-time-code"`, input `name`/`id` containing `otp|totp|2fa|code`, single-digit segmented inputs — and fills when confident, and (b) **copies the TOTP to the clipboard** as the universal fallback, because field detection is unreliable. TOTP autofill/copy is off by default or gated because auto-acting on untrusted pages is risky. ([Bitwarden autofill docs](https://bitwarden.com/help/auto-fill-browser/), [community threads](https://community.bitwarden.com/t/totp-autofill/13298))
- Fill via native input value setting + dispatching `input`/`change` events (React/Vue forms ignore raw `.value` writes); handle 6 separate one-digit boxes (fill sequentially, dispatch per-digit key events).
- **Origin binding is the security feature**: only offer/fill a code when the tab's origin matches the entry's associated domain — this makes the extension anti-phishing (a fake `github.co` page gets nothing), which is an advantage phone-only TOTP lacks.

### Security concerns for extensions holding secrets
- **DOM-based extension clickjacking** (Marek Tóth, DEF CON 33, Aug 2025): 10 of 11 tested password-manager extensions leaked credentials, and TOTP codes/passkeys were extractable in most, via invisible (opacity:0) injected autofill UI overlaid by fake cookie banners — ~40M users affected. Mitigations: render approval UI in extension-owned surfaces (popup, side panel) rather than injected DOM; if injecting, use closed shadow DOM, verify visibility/occlusion before acting, and require explicit user gesture per fill. ([marektoth.com writeup](https://marektoth.com/blog/dom-based-extension-clickjacking/), [The Hacker News](https://thehackernews.com/2025/08/dom-based-extension-clickjacking.html))
- Strong recommendation for your architecture: **the extension should not hold long-term TOTP secrets at all**. Keep secrets on the phone; the extension requests a *code* (or an approval) over the E2EE pairing channel per use. If you later add an "offline codes in browser" mode, encrypt at rest with a user passphrase (Argon2id) and treat it as a separate, opt-in trust level.

---

## 6. Pairing Protocol (Browser ↔ Phone)

### Reference designs
- **KeePassXC-browser** ([protocol doc](https://github.com/keepassxreboot/keepassxc-browser/blob/master/keepassxc-protocol.md)): NaCl `box` (X25519 + XSalsa20-Poly1305). Three key pairs: ephemeral host key, ephemeral client key (per session), and a **permanent client identification key** stored after the user explicitly "associates" — later sessions authenticate by proving possession of the ID key. Public keys exchanged in plaintext (acceptable there because transport is local native messaging, not a network).
- **WhatsApp Web** ([Security Whitepaper](https://www.whatsapp.com/security/WhatsApp-Security-Whitepaper.pdf)): the QR code shown by the browser contains a server routing reference + the companion's ephemeral/identity public keys + an **"adv" linking secret that never touches the server**; the phone scans it, and both devices then **cross-sign each other's identity keys** (account signature / device signature). Transport uses the **Noise Protocol Framework** with X25519. Key insights: (1) the QR is delivered *visually* — an out-of-band channel the relay server can't read or tamper with; (2) putting a secret in the QR means a malicious server can't MitM the pairing even though it relays everything.

### Recommended pattern for your product (E2EE relay, untrusted server)
1. Extension generates X25519 identity keypair + random 256-bit pairing secret; displays QR containing `{relay_url, pairing_id, extension_pubkey, pairing_secret}`.
2. Phone scans QR (camera = out-of-band channel), connects to relay, and runs a **Noise handshake** (e.g., `Noise_KK` or `Noise_XX` with PSK = pairing_secret; libsodium `crypto_kx` + the secret mixed in is a simpler equivalent) — the pairing secret authenticates both sides and defeats a MitM relay.
3. Both sides persist each other's static public keys (pinned identities, KeePassXC-style association); show matching emoji/short-auth-string fingerprints for optional verification.
4. All subsequent traffic (push approvals, code requests) = length-padded AEAD blobs over the relay; relay sees only `pairing_id`, timestamps, sizes. Use fresh ephemeral keys per session for forward secrecy; rotate/re-pair on demand; let either side revoke a pairing.
5. QR must be single-use with a short TTL (~1–2 min), and the extension should display pairing state changes prominently (new device linked = notification on both ends).

---

## 7. Push Delivery for a Self-Hosted Backend

### FCM from your own server
- FCM works fine from self-hosted backends via the HTTP v1 API with a service-account key; you do not need Firebase hosting/functions.
- Use **data-only messages** (no `notification` block) so your app code handles display — required for showing a rich approval UI and for suppressing notifications after the request is already resolved. Caveat: data-only messages are only delivered when the app can run; on iOS they're far less reliable (use APNs alerts or `content-available` carefully — separate problem for the iOS phase).
- **Priority**: high-priority messages punch through Doze and deliver immediately; normal priority is batched during Doze. Login approvals are user-visible and time-critical (60s expiry) — high priority is appropriate and consistent with Google's policy (misusing high priority for non-urgent traffic gets you deprioritized; Android 13+ evaluates your "high-priority acceptance rate"). ([FCM message priority](https://firebase.google.com/docs/cloud-messaging/android/message-priority), [Firebase blog: ensuring delivery on Android](https://firebase.blog/posts/2025/04/fcm-on-android/), [Android dev blog on FCM](https://android-developers.googleblog.com/2018/09/notifying-your-users-with-fcm.html))
- **Delivery is best-effort**: OEM battery killers (Xiaomi, Huawei, etc.) and Doze can still delay/drop. Always design push as a *wake-up hint*: on notification tap or app open, the app polls the server for pending transactions, so a dropped push degrades to "open the app" instead of a broken login.

### What must never go in the push payload
- FCM is TLS-encrypted to Google but **not end-to-end** — Google (and any notification-listener malware) can see payloads. Never include: TOTP secrets or codes, session tokens, the approval challenge/number, account identifiers beyond an opaque ID. Correct pattern: payload = `{type: "auth_request", txid: "<opaque>"}`; the app fetches the (E2EE) transaction details from your API. If you want payload content at all, encrypt it with the device's pairing key. ([FCM security overview](https://ptkd.com/journal/firebase-cloud-messaging-fcm-security), [Twilio on data-only FCM](https://help.twilio.com/articles/4411699713947-FCM-Push-Notifications-only-as-Data-messages))

### UnifiedPush
- [UnifiedPush](https://unifiedpush.org/news/20221218_unifiedpush/) is the open, self-hostable alternative (ntfy, NextPush distributors); ideal for de-Googled/F-Droid users. Recommended: abstract your push layer so FCM is the default and UnifiedPush is a build flavor/optional distributor — this is what Molly, Element, and others do. Fallback for neither: app-side polling/WebSocket while foregrounded.

---

## Final Engineering Checklist

**TOTP engine**
- [ ] HOTP/TOTP per RFC 4226/6238; support SHA1/SHA256/SHA512, 6/7/8 digits, arbitrary periods (15/30/60s); RFC test vectors (all three algorithms, correct per-algorithm seed lengths) in CI.
- [ ] Base32 decoder: case-insensitive, ignores whitespace/dashes, tolerates missing padding.
- [ ] otpauth:// parser: issuer precedence (param > label prefix), dedup, URL-decoding, defaults for missing params; otpauth-migration:// import **and export** (protobuf, multi-QR batching via batch_index/size/id, raw-byte secrets, UNSPECIFIED enums → defaults).
- [ ] NTP-based time-sync check surfaced in UI.

**Android vault**
- [ ] Aegis-style envelope: random 256-bit master key → XChaCha20-Poly1305 vault; slots for (a) Argon2id password key, (b) Keystore biometric key. Biometric invalidation must never lose data — only fall back to password.
- [ ] Try StrongBox, fall back to TEE; catch `KeyPermanentlyInvalidatedException` / `UnrecoverableKeyException` paths (tested).
- [ ] FLAG_SECURE on by default (toggleable); `EXTRA_IS_SENSITIVE` on clipboard copies + short self-clear.
- [ ] `dataExtractionRules` excluding vault from cloud backup **and** D2D transfer; own encrypted export instead; loud warning on any plaintext export.
- [ ] Play compliance: accurate Data Safety form; in-app account deletion + web deletion URL for the sync/push account.

**Backup/recovery**
- [ ] libsodium across all platforms; Argon2id (≥ moderate limits; never PBKDF2@10k like 2FAS); versioned backup envelope with stored KDF params.
- [ ] 12-word BIP39 recovery phrase = random 128-bit entropy → derived recovery key wraps master key (extra slot / server-side wrap, Ente-style). Phrase never stored; verify-phrase-on-creation flow.
- [ ] No SMS/email-based recovery of secrets, ever (headline failure mode in USENIX '23 study).

**Push approvals**
- [ ] Server txid state machine, single-use, 60s expiry; async create + poll/long-poll status; device-signed approvals (Keystore key registered at enrollment) with timestamp freshness.
- [ ] Push-fatigue mitigations: rich context (origin, browser, geo) in the approval sheet; rate-limit pushes; per-site mute; deny as first-class action. (Number matching noted; see Purr note in §4 for why the code-release-to-paired-browser model changes the calculus.)
- [ ] Approval content E2EE with pairing keys; relay/server sees opaque blobs only.

**Extension (MV3)**
- [ ] No long-term secrets in the extension by default — request codes/approvals from phone per use; `chrome.storage.session` for ephemeral state; assume SW death at any time (30s idle), WebSocket keepalive <30s on Chrome 116+, offscreen-document fallback.
- [ ] TOTP fill: `autocomplete=one-time-code` + name/id heuristics + segmented-input handling + clipboard fallback; strict origin binding before offering a fill; user gesture required.
- [ ] Anti-clickjacking: approval UI in popup/side panel, not injected DOM; if injecting, closed shadow root + occlusion checks (DEF CON 33 findings).

**Pairing**
- [ ] QR carries a server-invisible secret + extension static pubkey; Noise/libsodium X25519 handshake mixing that secret (MitM-proof against your own relay); pin static keys, WhatsApp-style cross-signing; single-use short-TTL QRs; per-device revocation UI.

**Push transport**
- [ ] FCM HTTP v1, data-only, high priority for auth requests; payload = opaque txid only, details fetched over API; app polls pending transactions on open (dropped-push fallback); push layer abstracted with UnifiedPush as an alternative distributor.

**Key sources**: [RFC 6238](https://www.rfc-editor.org/rfc/rfc6238.html) · [Key Uri Format](https://github.com/google/google-authenticator/wiki/Key-Uri-Format) · [otpauth-migration analysis](https://alexbakker.me/post/parsing-google-auth-export-qr-code.html) · [Aegis vault.md](https://github.com/beemdevelopment/Aegis/blob/master/docs/vault.md) · [Ente architecture](https://github.com/ente-io/ente/blob/main/architecture/README.md) · [USENIX Sec '23 2FA-app failures](https://www.usenix.org/system/files/usenixsecurity23-gilsenan.pdf) · [Android Keystore](https://developer.android.com/privacy-and-security/keystore) · [Auto Backup](https://developer.android.com/identity/data/autobackup) · [Clipboard security](https://developer.android.com/privacy-and-security/risks/secure-clipboard-handling) · [Play account deletion](https://support.google.com/googleplay/android-developer/answer/13327111?hl=en) · [Duo Auth API](https://duo.com/docs/authapi) · [CISA number matching](https://www.cisa.gov/sites/default/files/publications/fact-sheet-implement-number-matching-in-mfa-applications-508c.pdf) · [Uber breach analysis](https://www.upguard.com/blog/what-caused-the-uber-data-breach) · [MV3 SW lifecycle](https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle) · [MV3 WebSockets](https://developer.chrome.com/docs/extensions/how-to/web-platform/websockets) · [DOM extension clickjacking](https://marektoth.com/blog/dom-based-extension-clickjacking/) · [KeePassXC protocol](https://github.com/keepassxreboot/keepassxc-browser/blob/master/keepassxc-protocol.md) · [WhatsApp Security Whitepaper](https://www.whatsapp.com/security/WhatsApp-Security-Whitepaper.pdf) · [FCM priority](https://firebase.google.com/docs/cloud-messaging/android/message-priority) · [UnifiedPush](https://unifiedpush.org/news/20221218_unifiedpush/)
