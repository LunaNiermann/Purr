# Two Keys — Build Plan

Working order. Each milestone leaves the repo in a working, testable state.

## M0 — Foundations (docs, research, toolchain)
- [x] Study design handoff (README + both prototype HTML files, all screens 1a–5g)
- [x] Architecture doc (`docs/ARCHITECTURE.md`)
- [ ] Research report on existing 2FA apps' failures → `docs/RESEARCH.md` (two agents running)
- [ ] Flutter SDK installed, `flutter doctor` clean for Android, empty app builds an APK

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
"Touch your key" (WebAuthn/CTAP2 route) ships as a visible option only if a real security-key story lands; otherwise the option is hidden — never a dead button.

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
