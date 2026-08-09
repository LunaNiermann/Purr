# Google Play readiness — Purr (`nl.notfinal.twofa`)

## Signing

Play uses Play App Signing; you upload with an **upload key**. Generate it once.

macOS / Linux:

```bash
keytool -genkey -v -keystore ~/twokeys-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Windows PowerShell (use `$HOME`, not `~` — PowerShell doesn't expand `~` in
arguments passed to `keytool`, so `~/...` fails with FileNotFoundException):

```powershell
keytool -genkey -v -keystore "$HOME\twokeys-upload.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Keep the store and key passwords safe — losing them means you can never ship
another update signed with this key.

Then create `app/android/key.properties` (git-ignored):

```properties
storePassword=<store password>
keyPassword=<key password>
keyAlias=upload
storeFile=/absolute/path/to/twokeys-upload.jks
```

`build.gradle.kts` reads this automatically; without it, release builds fall
back to the debug key so `flutter run --release` still works locally.

Build the upload artifact:

```bash
flutter build appbundle --release
```

Output: `app/build/app/outputs/bundle/release/app-release.aab`.

## Data safety form

Purr is local-first and zero-knowledge. Declare precisely:

| Question | Answer |
|---|---|
| Does the app collect or share user data? | **Yes** (a device pairing + encrypted backup blob transit the relay) |
| Data types collected | **Device or other IDs** (an opaque FCM token + random pairing id). No names, emails, phone numbers, contacts, location, or financial info. |
| Is TOTP secret / vault data collected? | **No** — it never leaves the device except as ciphertext the server cannot read; encrypted blobs are not "collected data" the developer can access, but disclose the encrypted backup transit honestly in the listing. |
| Is data encrypted in transit? | **Yes** (TLS) |
| Is data encrypted at rest / end-to-end? | **Yes** — client-side keys; server stores only ciphertext |
| Can users request deletion? | **Yes** — in-app "Unpair" and kit rotation delete server-side rows; plus a public deletion URL (below) |
| Data used for tracking / ads? | **No** |
| Third-party SDKs sharing data? | Firebase Cloud Messaging (delivery only; payload is an opaque request id) |

**Account deletion (required since 2024):** the app has no accounts, but the
backup blob and pairing rows count. Provide:
- In-app: Security → Unpair (deletes the pairing) and kit rotation / "Move to
  another app" then wipe (retires the backup blob).
- Public web URL: a page on the landing-page domain describing how to delete —
  since blobs are addressed by a kit-derived id only the user holds, deletion
  is self-service via the app; the page states this and gives a support
  contact for manual purge by id if needed.

## Sensitive / restricted permissions

- `CAMERA` — QR scan only; requested at moment of intent (design 5a→5b), never
  at launch. Store listing must explain: "to read the setup QR code."
- `POST_NOTIFICATIONS` — approval pushes; requested only after first account +
  pairing (design 5d→5g).
- `USE_BIOMETRIC` — local unlock.
- No `RECEIVE_BOOT_COMPLETED`, no location, no contacts, no `QUERY_ALL_PACKAGES`.

## Store listing notes

- **Category:** Tools. **Content rating:** Everyone.
- Lead with the wedge, not jargon: "Your codes stay on your phone. Sign in on
  your computer with one tap." Avoid "TOTP", "OTP", "seed" (per the design).
- Screenshots: use `docs/screens/` (onboarding, vault, security, approval,
  recovery). They are captured from debug builds where FLAG_SECURE is off;
  release builds block screenshots, so capture store assets from a debug build.
- Free, no ads, no subscription, no trackers — say so; it is a trust signal in
  a category full of scam clones (see `docs/RESEARCH-complaints.md`).

## Pre-launch checklist

- [ ] `flutter build appbundle --release` succeeds with the real upload key
- [ ] Bump `version:` in `app/pubspec.yaml` per release (versionCode auto-increments from `+N`)
- [ ] FLAG_SECURE confirmed on release (screenshots blocked in-app)
- [ ] Data safety form matches the table above
- [ ] Deletion URL live on the landing domain
- [ ] `NSCameraUsageDescription` equivalent set for the eventual iOS build:
      "To read the setup QR code a site shows you. Photos are never taken or stored."
- [ ] Relay deployed at `https://2fa.apps.not-final.com` with a valid cert
- [ ] FCM service account uploaded to the relay volume (or accept poll-only)
