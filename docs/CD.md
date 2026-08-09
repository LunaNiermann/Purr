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

When you're ready, enroll, then add these secrets (all base64 where noted):

| Secret | What it is |
|---|---|
| `APPLE_TEAM_ID` | 10-char team id from developer.apple.com → Membership |
| `IOS_DIST_CERT_P12_BASE64` | your Apple **Distribution** certificate exported as `.p12`, base64 |
| `IOS_DIST_CERT_PASSWORD` | the `.p12` export password |
| `IOS_PROVISIONING_PROFILE_BASE64` | an App Store provisioning profile for `nl.notfinal.twofa`, base64 |
| `APPSTORE_ISSUER_ID` | App Store Connect API → Keys → Issuer ID |
| `APPSTORE_KEY_ID` | the API key's Key ID |
| `APPSTORE_PRIVATE_KEY` | contents of the API key `.p8` file |

The presence of `APPSTORE_KEY_ID` flips the workflow from validation to a real
signed build + TestFlight upload. Before the first run you must also, once, in
App Store Connect: create the app record (bundle id `nl.notfinal.twofa`) so
there's something to upload builds to.

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
