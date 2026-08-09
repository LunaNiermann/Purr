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

### Publishing from CI (optional, later)
CI already builds `twokeys-extension.zip`. The Chrome Web Store and Edge both
have publish APIs; once you have store credentials we can add a job that
uploads the zip on tag (mirroring the Play step). I left this out for now
because it needs a created store listing + API keys first — same pattern as
Play in `docs/CD.md`.
