# Purr

A two-factor (TOTP) authenticator for people who aren't security experts.
Your codes live on your phone; signing in on your computer is one tap.

Three surfaces + one small service:

| Path | What it is | Stack |
|---|---|---|
| `app/` | Mobile app (Android now, iOS later) | Flutter |
| `extension/` | Browser extension — "the keyhole" | TypeScript, Manifest V3 |
| `server/` | E2EE relay + encrypted backup store | Node 22, Fastify, SQLite |
| `docs/` | Architecture, plan, research, Play readiness | — |

App id: `nl.notfinal.twofa` · Relay: `https://2fa.apps.not-final.com` · Website: [purr2fa.app](https://purr2fa.app/)

**Get Purr:** [Google Play](https://play.google.com/store/apps/details?id=nl.notfinal.twofa) · [direct APK](https://github.com/LunaNiermann/Purr/releases/latest) · [Chrome extension](https://chromewebstore.google.com/detail/purr-2fa-authenticator/bfancenpneedgcnfjlajckcffpibjfkf) · [Edge extension](https://microsoftedge.microsoft.com/addons/detail/purr-2fa-authenticator/lgfjannafbclpekbiohccbnghhjacfhg)

## What makes it different

Built deliberately against the failures of existing authenticators
(`docs/RESEARCH-complaints.md`):

- **No account, no email, no phone number.** Works offline; nothing to sign up for.
- **Zero-knowledge.** TOTP secrets are encrypted on the phone with a random
  data key, wrapped by an Argon2id password slot *and* a 12-word recovery slot
  (Aegis-style — losing one unlock method never loses data). The relay and the
  extension only ever see ciphertext or a single approved six-digit code.
- **Recovery that actually works.** A printed 12-word kit restores every code
  onto a new phone even if you lose every device — verified end to end.
- **Exit rights forever.** Plaintext `otpauth://` export + Google Authenticator
  (`otpauth-migration://`) import. No lock-in.
- **The desktop moment.** The browser extension spots a 2FA field, matches the
  domain, and gets a code from your phone (or, later, a security key) — the code
  only ever reaches the paired, end-to-end-keyed browser.
- **Free, open, no ads, no trackers.**

See `docs/ARCHITECTURE.md` for the crypto and request-lifecycle design.

## Develop

**App** (needs Flutter + Android SDK):
```bash
cd app
flutter pub get
flutter test          # TOTP RFC vectors, crypto round-trips, cross-language pairing interop
flutter run           # on a device/emulator
```
Point at a local relay for testing:
`flutter run --dart-define=TWOKEYS_RELAY=http://10.0.2.2:3000`

**Server**:
```bash
cd server
npm install && npm test
npm run dev           # port 3000
```

**Extension**:
```bash
cd extension
npm install && npm run build   # load dist/ as an unpacked extension
```

## Deploy

- Server → Coolify (Dockerfile in `server/`, volume at `/app/data`). Live at `https://2fa.apps.not-final.com`. See `server/README.md`.
- App → built and released from GitHub Actions (no local build; iOS on GitHub's Mac runners). See `docs/CD.md`; Play specifics in `docs/PLAY.md`.
- Extension → testing and store distribution in `docs/EXTENSION.md`.
- The marketing site (`https://purr2fa.app/` — landing + privacy policy) is static HTML in `server/site/`, served by the relay container itself.

Releases are cut by tag, and the three surfaces ship independently:
- `v0.2.0` → Android (AAB/APK, optional Play upload) + iOS (validation, or TestFlight when signed)
- `ext-v0.2.0` → browser extension (zip, optional Chrome Web Store publish)

## Status

Verified on an Android emulator: onboarding, vault (list/cards, search, copy,
hide), add-by-QR/manual, account detail, security, **extension↔phone pairing
through the relay**, **approval request A11 with 60 s expiry**, and the **full
lost-phone recovery loop** (backup → wipe → 12 words → restored). **FCM push**
is wired into the app (optional; drop in `google-services.json` — see
`docs/PUSH.md`). Not yet done: iOS target and the WebAuthn "touch your key"
desktop route (design and plan in place; ships after the phone route). See
`docs/PLAN.md`.

## License

GPL-3.0 — see [`LICENSE`](LICENSE). Any fork must stay open source, which is
the point: for an authenticator, trust comes from code you can read. The
bundled fonts (Instrument Sans, JetBrains Mono) are under the SIL Open Font
License; their license texts sit next to the font files in `app/assets/fonts/`.

Found a security issue? Please report it privately — see [`SECURITY.md`](SECURITY.md).

## Translations

[![Crowdin](https://badges.crowdin.net/purr/localized.svg)](https://crowdin.com/project/purr)

Purr follows your device language by default and can be switched by hand in
Security → Language. It ships in English, Spanish, German, French, Italian,
Portuguese, Indonesian, Hindi, Arabic, Japanese, and Korean. Strings live in
`app/lib/l10n/*.arb` (app) and `extension/_locales/` (extension); corrections
and new languages are welcome via [Crowdin](https://crowdin.com/project/purr).

## Support

Purr is free, open, and has no ads or trackers. If it's useful to you and you
want to help keep it that way:

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/K3K01T7UXI)
