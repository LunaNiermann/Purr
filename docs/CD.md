# Continuous delivery — building & shipping from GitHub

You never build locally. Two release workflows run on GitHub's runners:

| Workflow | Runner | Produces |
|---|---|---|
| `release.yml` | Ubuntu (free-ish) | Android AAB + APK, extension zip |
| `release-ios.yml` | macOS | iOS build (validation now, TestFlight when signed) |

**How to cut a release:** bump `version:` in `app/pubspec.yaml`, commit, then
tag and push:

```bash
git tag v0.2.0
git push origin v0.2.0
```

Both workflows fire on the `v*` tag. The tag's version (minus the `v`) becomes
the app's version name; the GitHub run number becomes the build number, so it
always increases. You can also run either workflow manually from the **Actions**
tab (produces downloadable artifacts without making a release).

Nothing below is required to get **testable APKs** — those build with the debug
key if no secrets are set. Secrets only matter for Play/TestFlight store uploads.

---

## Android

### Sideload testing (zero setup)
Push a tag (or run the workflow manually). Download `app-release.apk` from the
run's artifacts or the GitHub Release, and install it on any device
(Settings → allow install from this source). Good enough for testers.

### Signed release for Google Play
Generate an upload keystore once (see `docs/PLAY.md`), then add these repo
secrets (**Settings → Secrets and variables → Actions → New repository secret**):

| Secret | What it is |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 upload.jks` (one line) |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | e.g. `upload` |
| `ANDROID_KEY_PASSWORD` | key password |

With these set, the AAB is properly signed. To also **auto-publish to Play**,
add:

| Secret | What it is |
|---|---|
| `PLAY_SERVICE_ACCOUNT_JSON` | a Google Play service-account JSON with "Release apps to testing tracks" permission |

One-time Play setup before the first automated upload:
1. Create the app in the Play Console (package `nl.notfinal.twofa`) and upload
   **one** AAB manually — Play won't accept API uploads until the app exists.
2. Play Console → Setup → API access → link a Google Cloud project → create a
   service account → grant it release permissions → download its JSON key →
   paste into `PLAY_SERVICE_ACCOUNT_JSON`.

After that, tag pushes upload to the **internal** track. Change the track by
running the workflow manually and typing one (`internal`, `alpha`, `beta`,
`production`).

---

## iOS (no Mac required)

The macOS runner *is* the Mac. Without any secrets, `release-ios.yml` compiles
a `--no-codesign` build on every tag — this proves the app builds for iOS, but
Apple requires a signed build to install anywhere (including TestFlight), and
that requires the **Apple Developer Program** ($99/yr).

The project's identifiers (all non-secret) are already set:

| | |
|---|---|
| Bundle ID | `nl.notfinal.twofa` |
| Apple Team ID | `5858K3V8JQ` — baked into `release-ios.yml`'s ExportOptions |
| App Store Connect Apple ID | `6803663064` |

When you're ready, enroll, then add these secrets (all base64 where noted):

| Secret | What it is |
|---|---|
| `IOS_DIST_CERT_P12_BASE64` | your Apple **Distribution** certificate exported as `.p12`, base64 |
| `IOS_DIST_CERT_PASSWORD` | the `.p12` export password |
| `IOS_PROVISIONING_PROFILE_BASE64` | an App Store provisioning profile for `nl.notfinal.twofa` **including the Push Notifications entitlement**, base64 |
| `APPSTORE_ISSUER_ID` | App Store Connect API → Keys → Issuer ID |
| `APPSTORE_KEY_ID` | the API key's Key ID |
| `APPSTORE_PRIVATE_KEY` | contents of the API key `.p8` file |
| `GOOGLE_SERVICE_INFO_PLIST_BASE64` | Firebase iOS `GoogleService-Info.plist`, base64 — restored by CI so builds can bundle it (enables push) |

The presence of `APPSTORE_KEY_ID` flips the workflow from validation to a real
signed build + TestFlight upload. The app record already exists (bundle id
`nl.notfinal.twofa`, Apple ID `6803663064`).

### Push notifications (one-time setup)

1. **Apple Developer** — App ID `nl.notfinal.twofa` needs the **Push
   Notifications** capability, and the provisioning profile above must be
   regenerated to include it.
2. **Xcode** (`app/ios/Runner.xcworkspace`, needs a Mac) — add the **Push
   Notifications** capability (this creates `Runner.entitlements` and wires the
   `.pbxproj`) and enable **Background Modes → Remote notifications**. Drag the
   Firebase `GoogleService-Info.plist` into the **Runner target** so it's
   bundled, and commit the `.pbxproj` reference. The plist itself stays
   gitignored and is restored in CI from the secret above.
3. **Firebase** — register an iOS app (bundle id `nl.notfinal.twofa`), download
   `GoogleService-Info.plist`, and upload an **APNs Auth Key (.p8)** under
   Project Settings → Cloud Messaging. Without the `.p8`, FCM cannot deliver to
   iOS at all.

Tip: generating the cert/profile by hand is fiddly. If it becomes a chore,
switch the iOS job to **fastlane match**, which stores signing assets in a
private git repo and regenerates them automatically — worth it once you iterate
on iOS regularly.

---

## What each secret can and can't do
All of these are store-publishing credentials. None of them touch the app's
zero-knowledge crypto — losing one lets someone publish a build under your
name, not read anyone's vault. Rotate them if leaked; never commit them (the
repo `.gitignore` already blocks `*.jks`, `*.p12`, `key.properties`, and
`service-account*.json`).
