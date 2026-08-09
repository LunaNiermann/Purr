# Purr — Build Plan

Working order. Each milestone leaves the repo in a working, testable state.

## M0 — Foundations (docs, research, toolchain)
- [x] Study design handoff (README + both prototype HTML files, all screens 1a–5g)
- [x] Architecture doc (`docs/ARCHITECTURE.md`)
- [x] Research: `docs/RESEARCH-complaints.md` (what users hate/love in Authy, Google/Microsoft Authenticator, Bitwarden, 2FAS, Aegis, Ente) and `docs/RESEARCH-technical.md` (TOTP/Keystore/backup/push/MV3/pairing engineering)
- [ ] Flutter SDK installed, `flutter doctor` clean for Android, empty app builds an APK

### Research-derived commitments (binding for this codebase)
From the complaints report ("design commandments") and the technical checklist:
1. **Exit rights forever**: plaintext export (otpauth:// list) + encrypted export, plus `otpauth-migration://` import AND export. No lock-in, ever (the Authy lesson). Export UI lives in Security, styled in the design's idiom.
2. **No phone numbers, no accounts, no email** anywhere in the system (matches the design's "no account to make" promise; avoids Authy's enumeration breach class entirely). No unauthenticated endpoint may confirm existence of anything (backup GETs need proof-of-knowledge, rate limiting).
3. **Never silently drop or overwrite an entry.** Same issuer+username → save as a distinguishable second entry with a rename prompt; every import reports per-row success/failure.
4. **E2EE from day one** for everything that leaves the phone; server stores only ciphertext + routing metadata (no plaintext issuer names server-side).
5. **Aegis-style key slots**: biometric/Keystore invalidation must never cost data — password and recovery wraps always remain. Catch `KeyPermanentlyInvalidatedException` and fall back gracefully.
6. **Backups verified at write time**: after upload, download + decrypt + compare digest (Authy's silent corruption lesson); versioned envelope with KDF params.
7. **Clock drift handled**: NTP-style offset check with a visible, friendly warning ("your phone's clock is a bit off — codes may be rejected").
8. **Argon2id, never weak PBKDF2** for the password KEK (2FAS shipped PBKDF2@10k; OWASP says 600k — we use libsodium Argon2id moderate).
9. **Vault excluded from OS backup and device-to-device transfer** via `dataExtractionRules` (allowBackup=false is not enough on Android 12+); our encrypted backup is the only backup.
10. **Clipboard hygiene**: `EXTRA_IS_SENSITIVE` flag + self-clear after ~45 s.
11. **Extension holds no long-term secrets** (already the design); popup-owned UI only, no injected DOM chrome (DEF CON 33 clickjacking class); strict origin binding before offering a fill.
12. **Push = wake-up hint only**: FCM data-only, high priority, payload is `{requestId, pairingId}`; app polls pending requests on open so a dropped push degrades to "open the app", which the design's 5f banner already frames.
13. **Push-fatigue posture**: our approval releases a code only to the paired, E2E-keyed browser — an attacker spamming pushes can't receive codes. Keep: rich context in A11, deny as first-class, per-site mute, per-pairing rate limits, auto-cooldown after repeated denies.
14. **Free core, no subscription, no ads, no trackers** — the category is poisoned by scam clones; trust is the product.

## M1 — App core (offline, no server needed)
The app must be fully useful with zero network — that's a design promise ("works on a plane").
1. Design system: tokens (color/type/spacing/radius/motion) as Dart constants + shared widgets (buttons, cards, chips, toggle rows, progress pills, section labels, tab bar)
2. TOTP engine + otpauth parsing + `otpauth-migration` import, with RFC test vectors
3. Crypto core: Argon2id, XChaCha20-Poly1305 vault, DEK wrapping (password / Keystore / recovery), unit-tested roundtrips
4. Onboarding A1–A4 (password → biometrics → kit), lock screen A10, biometric unlock
5. Vault A5–A9: empty state, list/cards layouts, search, copy-with-feedback, hide-codes, account detail A8, security tab A9
6. Add account A17/A18: camera scan (permission beats 5a–5c) + manual entry with live "That code works" validation
7. Recovery kit generation + printed sheet (C6) as PDF via platform print

## M2 — Server (relay + backup store)
Fastify + SQLite, Dockerfile, deployable to Coolify at `https://2fa.apps.not-final.com`.
Pairing, approval-request relay with 60 s TTL, FCM data-only push, backup blob store, rate limiting, tests.

## M3 — Extension
Pairing B1, autofill B2 (field detection → ready → awaiting phone → filled), popup vault B3 (display via request, holds no secrets), locked B4, unmatched B5, failure popups B6, settings B7.
"Touch your key": real route per the original product brief — E2EE vault replica in the extension unlocked by WebAuthn PRF, decrypt-single-entry at fill time. Ships **after** the phone route (M5+); until it lands the option is hidden — never a dead button. YubiKey HMAC-SHA1 fallback deferred further.

## M4 — Approval flow end-to-end
Phone A11–A16 (request, biometric, approved, denied, code-only, intrusion aftermath, mute-until-midnight) + FCM in app + notifications permission beats 5d–5g.

## M5 — Recovery end-to-end
Encrypted backup upload/restore, lost-phone storyboard C1–C5, kit rotation (old kit retired on use/reprint).

## M6 — Hardening & Play readiness
- Unit + widget tests green; manual emulator pass of every storyboard
- FLAG_SECURE, clipboard sensitivity, screenshot suppression on kit screen
- Release build: R8, signing config (keystore supplied by owner), versioning
- Play data-safety worksheet + store listing draft (`docs/PLAY.md`)

## Deliberate deviations from the handoff
- Android first: "Face ID" copy becomes a platform-aware biometric label; system permission dialogs are Android's own (M3 dialog per 5g).
- The prototype's "Replay" tab affordance is not shipped (per handoff).
- Security-key ("BEST") paths: shown in designs, but hardware-key restore/unlock is a stretch goal — UI copy adapts so no path dead-ends. Rationale in RESEARCH.md once agents report.

## Decisions log
- 2026-08-09 Flutter chosen for app; TS/MV3 for extension; Fastify+SQLite for server (see ARCHITECTURE.md).
- 2026-08-09 Long-poll over WebSocket for extension↔relay (MV3 service-worker lifetime).
- 2026-08-09 No account/no email design preserved: backups addressed by kit-derived id, not user identity.
