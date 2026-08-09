# Browser extension — testing & distribution

## Build it

```bash
cd extension
npm install
npm run build      # outputs dist/  (this is the unpacked extension)
npm run watch      # rebuild on change while developing
```

`dist/` is the loadable extension. A ready-to-upload `twokeys-extension.zip`
is also produced by CI on every tag (see `docs/CD.md`).

## Load it for testing

### Chrome / Edge / Brave (Chromium)
1. Go to `chrome://extensions` (Edge: `edge://extensions`).
2. Turn on **Developer mode** (top right).
3. **Load unpacked** → select the `extension/dist` folder.
4. The options page opens on install — that's the first-run pairing screen (B1).

After a rebuild, click the **reload** ↻ icon on the extension card. With
`npm run watch` running you just rebuild + reload; no re-selecting the folder.

### Firefox
1. Go to `about:debugging#/runtime/this-firefox`.
2. **Load Temporary Add-on** → pick `extension/dist/manifest.json`.
3. Note: temporary add-ons are removed when Firefox restarts, and Firefox is
   stricter about MV3 background service workers — treat Firefox as a
   secondary target and test the Chromium build first.

## What to click

- **Pair:** the options page (opens on install, or via the extension's
  Settings link) shows the QR / pairing code. On the phone: Security → Pair a
  computer → scan. The popup then shows "Ready when you are."
- **Approve a login:** open the popup on a page with a 2FA field → "Ask my
  phone" → approve on the phone → the code fills in.
- The extension already points at the **live relay**
  (`https://2fa.apps.not-final.com`), so pairing/approval work end to end with
  no config. To point a dev build at a local relay instead, change `RELAY_URL`
  in `extension/src/lib/relay.ts` and rebuild. (Say the word and I'll wire this
  to a build-time env var like the app's `--dart-define`.)

## Debugging

| Surface | How to open its devtools |
|---|---|
| Background service worker | `chrome://extensions` → the extension → **service worker** link → Inspect. It sleeps after ~30s idle; that's expected (MV3). |
| Popup | Right-click the toolbar icon → **Inspect popup** |
| Options page | Open it, then normal page devtools (F12) |
| Content script | The page's own devtools → Console; content-script logs appear there |
| Network to the relay | Inspect the popup/service worker → Network tab |

---

## Distribution options (for later)

You do not have to pick one — the same MV3 package can go to all three stores.

| Channel | Cost | Review | Private/beta option | Auto-update |
|---|---|---|---|---|
| **Chrome Web Store** | $5 one-time dev fee | hours–days | **Unlisted** (link-only) or **Trusted testers** allowlist | Yes |
| **Microsoft Edge Add-ons** | Free | days | Hidden/unlisted | Yes |
| **Firefox AMO** | Free | automated + sometimes manual | Self-distribution: AMO signs an `.xpi` you host yourself | Yes |
| **Self-host (Chromium)** | Free | none | Enterprise policy / `.crx` + update manifest — clunky, not for consumers | Manual-ish |

Notes and recommendations:
- **Chrome Web Store is the primary target** (matches your Play-first plan).
  Start **Unlisted** or with **Trusted testers** for a private beta, then flip
  to Public when ready. Chromium requires MV3 — ours already is.
- **Edge** accepts the *same* zip; submitting there is nearly free effort and
  covers Edge users. Worth doing at launch.
- **Firefox** requires every add-on to be **signed by AMO**, even for
  self-distribution — you upload the zip, AMO signs it, then you either list it
  on AMO or host the signed `.xpi` yourself. Our `manifest.json` uses an MV3
  `service_worker` background, which recent Firefox supports; still, test it
  explicitly before promising Firefox support.
- **Avoid raw self-hosting on Chrome** for end users — Chrome blocks
  side-loaded extensions outside the store for normal profiles; it only works
  via enterprise policy. Fine for your own testing (Load unpacked), not for
  distribution.
- **Store assets you'll need:** icon (have it), 1–3 screenshots, a short + long
  description, and a privacy policy URL. Reuse the honest framing from the app
  listing (no accounts, codes stay on the phone, no trackers).

### Releasing the extension from CI

The extension has its **own** workflow, separate from the app:
[`release-extension.yml`](../.github/workflows/release-extension.yml). It fires
on `ext-v*` tags (the app uses plain `v*`), so the two ship independently:

```bash
git tag ext-v0.1.0 && git push origin ext-v0.1.0
```

That builds the zip, sets `manifest.json`'s version to the tag (Chrome requires
each published version to be higher than the last), attaches the zip to a
GitHub Release, and — if the Chrome Web Store secrets are present — uploads and
publishes automatically. Without secrets it just builds the zip.

### Chrome Web Store publishing setup

You've paid the $5 developer fee — here's the rest, one time.

**1. Create the listing (once, manually).** The API can only *update* an
existing item, not create the first one.
- Go to the [Developer Dashboard](https://chrome.google.com/webstore/devconsole),
  **Add new item**, and upload `twokeys-extension.zip` (grab it from the
  v-tag's GitHub Release, or `npm run build` + zip `extension/dist`).
- Fill the store listing: description, at least one screenshot, an icon, a
  category, and a **privacy policy URL** (required because we touch the
  network). Reuse the honest framing — no accounts, codes stay on the phone,
  no trackers.
- Save. Copy the **Item ID** from the URL — that's `CHROME_EXTENSION_ID`.

**2. Create API credentials for automated uploads.**
- In [Google Cloud Console](https://console.cloud.google.com): create (or pick)
  a project → **APIs & Services** → enable the **Chrome Web Store API**.
- **OAuth consent screen**: set it up (External is fine; add yourself as a test
  user so the refresh token doesn't expire on an unverified app).
- **Credentials → Create credentials → OAuth client ID → Desktop app.**
  Note the **Client ID** and **Client secret**.
- Get a **refresh token** (one time). Easiest is the maintained helper:
  ```bash
  npx @plasmohq/chrome-webstore-refresh-token
  ```
  It walks you through the Google consent screen with your client id/secret and
  prints a refresh token. (Or do the manual OAuth `code`→`token` exchange with
  scope `https://www.googleapis.com/auth/chromewebstore`.)

**3. Add the four repo secrets** (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `CHROME_EXTENSION_ID` | the Item ID from step 1 |
| `CHROME_CLIENT_ID` | OAuth client id |
| `CHROME_CLIENT_SECRET` | OAuth client secret |
| `CHROME_REFRESH_TOKEN` | the refresh token from step 2 |

After that, `git tag ext-v0.1.1 && git push origin ext-v0.1.1` uploads and
submits the new version. Note Chrome still **reviews** each submission (minutes
to a few days); `--auto-publish` means "publish once approved," not "skip
review." The first published version can't be Unlisted→Public flipped by the
API — set visibility (Public / Unlisted / Trusted testers) in the dashboard.

**Edge** later, if you want it, is the same zip + a similar API; say the word
and I'll add an Edge step to the same workflow.
