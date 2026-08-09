# Push notifications (FCM)

Push is **optional and best-effort** — a wake-up hint, never the source of
truth. If it's off or a message is dropped, the phone still shows waiting
requests when the app is opened (design 5f). The payload is routing-only
(`{type, requestId, pairingId}`); it never contains the domain, account, or
code, because FCM is not end-to-end encrypted.

It has two halves, both pointing at the **same Firebase project**:

| Half | Needs | Where |
|---|---|---|
| App **receives** | `google-services.json` | `app/android/app/google-services.json` |
| Relay **sends** | a service-account key | `FCM_SERVICE_ACCOUNT_JSON` on Coolify (see `server/README.md`) |

## App side — `google-services.json`

1. Firebase console → your project → add an **Android app** with package
   `nl.notfinal.twofa` (if not already), download `google-services.json`.
2. Drop it at `app/android/app/google-services.json`.

The build activates Firebase **only when that file exists** (a conditional
`apply` in `app/android/app/build.gradle.kts`), so the app still builds and
runs without it — push is simply disabled. At runtime `PushService.init()` is
wrapped in a try/catch for the same reason.

The file is **git-ignored**. For CI to produce push-enabled builds, add it as a
secret:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("app\android\app\google-services.json"))
```

→ GitHub secret `GOOGLE_SERVICES_JSON_BASE64`. The Android release workflow
decodes it before building; without the secret, releases build fine but without
push.

## Relay side — service account

The relay needs the Firebase **service account** (a different file) to call FCM.
See `server/README.md` → "Firebase push". Both halves must be the same Firebase
project (`fa-app-43f7a`).

## How it flows

1. Phone registers its FCM token with the relay (`PUT /v1/pairings/:id/fcm-token`),
   on pairing and on every app start / token refresh.
2. Extension asks for a code → relay creates the request and sends a data-only,
   high-priority FCM message carrying just the request id.
3. Phone wakes: in the background it shows a local notification ("Your browser
   needs a code"); tapping it opens the app, which fetches the pending request
   and shows the approval screen (A11).

## Testing notes

- FCM only works on devices/emulators **with Google Play services** (a "Google
  APIs" or "Play Store" system image — not a plain AOSP emulator).
- The notification permission is requested via the design's 5d priming sheet,
  the first time a computer is paired *and* an account exists.
- iOS push (APNs) is a later step; it needs `GoogleService-Info.plist` and the
  Apple Developer Program. The Dart code is already cross-platform.
