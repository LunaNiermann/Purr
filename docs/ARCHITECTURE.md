# Two Keys — Architecture

Product: a TOTP authenticator for non-technical people, per `design_handoff_two_keys/README.md`.
Three surfaces: mobile app (Android first, iOS later), browser extension, printable recovery kit.
Plus one deployable service: an end-to-end-encrypted relay API at `https://2fa.apps.not-final.com`.

App id: `nl.notfinal.twofa` · Name: **Two Keys**

## Repository layout

```
app/          Flutter app (Android + iOS from one codebase)
extension/    Browser extension, Manifest V3, TypeScript + Vite
server/       Relay API, TypeScript (Node 22, Fastify), Dockerfile for Coolify
docs/         This documentation
design_handoff_two_keys/   Design source of truth (do not edit)
```

## Stack choices and why

| Surface | Stack | Why |
|---|---|---|
| Mobile | **Flutter** (Dart) | One codebase for both platforms; the design is fully custom (paper/ink visual language, custom type, bespoke components) so a pixel-owned renderer beats native widget skinning; first-class Android today, iOS later without a rewrite. Platform channels cover the native bits (Keystore, BiometricPrompt, FLAG_SECURE, FCM). |
| Extension | **TypeScript + Vite**, WebExtension MV3 | Chrome/Edge first (matches Google Play-first strategy), Firefox-compatible API surface kept in mind. No framework — the popup is small; plain TS + a tiny DOM helper keeps the bundle honest. |
| Server | **Node 22 + Fastify + SQLite** (better-sqlite3), Docker | Coolify-friendly single container + volume. The server is a dumb encrypted relay — SQLite is more than enough and keeps ops at zero. Postgres migration path documented but not needed. |

Fonts: Instrument Sans + JetBrains Mono, bundled (no Google Fonts at runtime).

## Security model

The one-sentence version: **secrets never leave the phone; the server and the extension only ever see ciphertext or a single six-digit code that the user explicitly approved.**

### Key hierarchy (phone)

```
master password ──Argon2id──▶ KEK_pw ─────┐
Android Keystore key (biometric-gated) ───┼── each wraps ──▶ DEK (random 32 B)
recovery phrase (12 BIP39 words) ─HKDF─▶ KEK_rec ──┘            │
                                                                ▼
                                              vault blob: XChaCha20-Poly1305
                                              (TOTP secrets, names, usernames, settings)
```

- **DEK** — random 32-byte data-encryption key, generated once at onboarding. Encrypts the vault file. Never stored in plaintext.
- **KEK_pw** — Argon2id(master password, salt; m=64 MiB, t=3, p=1). Wraps DEK. The "I'll type my password" path.
- **Keystore wrap** — a hardware-backed AES key in Android Keystore, `setUserAuthenticationRequired(true)` (biometric or device credential), wraps DEK for the fast-unlock path. Invalidated by biometric enrollment changes by design; the password path always remains. After device restart the Keystore path may require re-auth — matches the design copy "you'll need it after a restart".
- **KEK_rec** — HKDF from the 128-bit entropy behind the 12 BIP39 words. Wraps DEK too. This is what makes the paper kit sufficient on its own.

Losing the master password is survivable (kit). Losing the kit is survivable (password + phone). Losing both phone and kit means starting over — stated honestly on the printed sheet.

### Encrypted backup

- Backup blob = vault snapshot encrypted with a key derived from the recovery entropy (HKDF, distinct info string from KEK_rec).
- Upload address: `backupId = HKDF(entropy, "twokeys/backup-id")` — the server indexes ciphertext by an identifier only the kit holder can compute. No account, no email, matching "no account to make".
- **Kit rotation** ("this sheet stops working the moment you use it" / "Replaces all earlier kits"): restoring or printing a new kit generates fresh entropy, re-wraps the DEK, re-uploads under the new `backupId`, and deletes the old blob. The old words then unlock nothing.
- Restore (C1–C5): type 12 words → compute `backupId` → fetch blob → decrypt locally → re-wrap with a new password/Keystore. "This all happens on this phone" is literally true.

### Pairing (extension ⇄ phone)

WhatsApp-Web-style QR pairing, E2EE from the first byte:

1. Extension generates an X25519 keypair and a pairing id; shows QR = `{v, relayUrl, pairingId, extPubKey}` plus the typeable fallback (`MOSS-TIDE-9417` style word-word-digits encoding of the same payload, short-lived, server-mediated).
2. Phone scans, generates its own X25519 keypair, computes the shared secret (X25519 → HKDF → session keys, separate send/receive keys), and POSTs `{pairingId, phonePubKey, deviceName-ciphertext}` to the relay.
3. Extension receives `phonePubKey` via the relay, derives the same secret. From here every payload between the two is XChaCha20-Poly1305 sealed; the relay stores and forwards opaque blobs.
4. Either side can unpair; the relay just deletes the pairing row.

### Approval request lifecycle (the core flow)

```
extension                     relay                          phone
   │ POST /v1/requests          │                              │
   │ {pairingId, box(domain,    │  FCM data-only push          │
   │  browser, ts)}             │ ────────────────────────────▶│ fetch + decrypt request
   │                            │                              │ show A11 (60 s TTL)
   │  SSE/long-poll for answer  │                              │ approve → biometric →
   │ ◀──────────────────────────│ ◀────────────────────────────│ POST box(6-digit code)
   │ decrypt, autofill (B2)     │                              │ A14 "You're in."
```

- Requests expire server-side and client-side at **60 s**; responses are single-use and deleted on delivery.
- Deny → phone posts an encrypted "denied" verdict → extension shows the denied popup; **no code is generated**. The phone records the event for the A16 intrusion screen ("Mute requests for this site today" = suppress until local midnight).
- "Just show me the code" → phone answers nothing; the request simply expires on the desktop.
- FCM payload contains **only** `{requestId, pairingId}` — never the domain, account, or code. Data-only message, `priority: high`.
- The push contains nothing sensitive, and the relay can't read what it forwards; the worst a compromised relay can do is deny service.

### What each party can never see

| Party | Never sees |
|---|---|
| Relay server | TOTP secrets, vault contents, domains, usernames, codes, push text — only ciphertext, pairing ids, FCM tokens, timestamps |
| Extension | TOTP secrets, the vault. It receives exactly one six-digit code per approved request |
| Google (FCM) | Only `{requestId, pairingId}` |

## Server API (v1)

```
POST   /v1/pairings                begin pairing (extension)
POST   /v1/pairings/:id/complete   phone joins, deposits pubkey blob
GET    /v1/pairings/:id/wait       extension waits for completion (long-poll)
DELETE /v1/pairings/:id            unpair (either side, bearer = pairing secret)

POST   /v1/requests                extension creates approval request (E2EE blob)
GET    /v1/requests/:id            phone fetches request blob
POST   /v1/requests/:id/answer     phone answers: approved blob | denied
GET    /v1/requests/:id/wait       extension waits for answer (long-poll, 60 s cap)

PUT    /v1/devices/fcm-token       phone registers/rotates its FCM token (per pairing)

PUT    /v1/backups/:backupId       upload encrypted backup (idempotent overwrite)
GET    /v1/backups/:backupId       fetch encrypted backup
DELETE /v1/backups/:backupId       retire a kit's blob

GET    /healthz
```

Rate-limited per IP and per pairing. All bodies are small JSON with base64 ciphertext. Long-poll chosen over WebSocket deliberately: MV3 service workers die after ~30 s idle; short long-polls survive worker restarts with no keepalive gymnastics.

## App state (mirrors the handoff)

The handoff's state sketch maps to Riverpod providers:

- `vault: List<Account>` — decrypted in memory only while unlocked
- `layout: list|cards`, `hideCodes: bool` — persisted (non-secret prefs)
- `copiedId + 2 s timer`, `tick (1 Hz)` — transient
- `screen` routing incl. full-screen states (request / codeOnly / biometric / approved / denied / locked)
- `pendingRequest` with `expiresAt`
- `permissions: camera/notifications: unasked|granted|denied` — ask at moment of intent only
- `onboarding: {step, hasMasterPassword, biometricsEnabled, kitPrinted}`

Android specifics: `FLAG_SECURE` on recovery-kit and code screens; clipboard writes flagged `IS_SENSITIVE` (Android 13+); no `allowBackup` for the vault (our encrypted backup is the only backup); codes copied as six bare digits.

## TOTP engine

RFC 6238 over RFC 4226, SHA-1/256/512, 6–8 digits, configurable period (default 30 s), tolerant otpauth:// parser (padding-less/lowercase/spaced base32, issuer-prefix duplication), plus `otpauth-migration://` import (Google Authenticator export). Display always `NNN NNN`; clipboard always bare digits. All accounts tick on the shared epoch boundary.

## iOS later

Flutter target already builds the same UI; the platform channels get Darwin twins (Keychain/Secure Enclave, LocalAuthentication/Face ID, APNs via FCM). The design was drawn iOS-first, so terminology swaps (Face ID ⇄ fingerprint/face unlock) are handled by a `BiometricLabel` helper from day one.
