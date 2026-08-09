# Handoff: Two Keys — authenticator app (iOS) + browser extension

## Overview

Two Keys is a two-factor authentication product for non-technical people. It has three surfaces:

1. **An iOS app** that holds TOTP secrets, shows codes, and answers approval requests.
2. **A browser extension** on the desktop that detects a 2FA field, matches it to a saved account, and gets a code — either from a plugged-in security key or by asking the phone.
3. **A printed recovery kit** — a single sheet with twelve words that can restore everything onto a new device.

The design brief was: *easy to understand for an average computer user, friendly tone, avoid AI-typical design patterns.* Copy carries that load — the interface explains what is happening in plain language at every step, and never uses the words "token", "seed", "OTP", or "entropy". Preserve the copy verbatim; it is the product.

## About the Design Files

The files in this bundle are **design references created in HTML** — prototypes showing the intended look and behavior. They are **not production code to copy directly.**

The task is to **recreate these designs in the target codebase's existing environment** (SwiftUI for the iOS app, whatever the extension is built in for the desktop surface) using its established patterns, component library, and conventions. If no environment exists yet, choose the most appropriate stack and implement the designs there.

Two specific things in the HTML must **not** be reproduced literally:

- **Device frames.** The iPhone bezels, status bars, and browser chrome in the prototypes are presentation scaffolding (`ios-frame.jsx`, `android-frame.jsx`, `browser-window.jsx`). The real app draws only the screen content.
- **System permission dialogs.** Screens `5b`, `5e`, and `5g` draw the OS's own permission alerts for context only. Build these by calling the platform permission API (`AVCaptureDevice.requestAccess`, `UNUserNotificationCenter.requestAuthorization`). **Never render a look-alike.** The only part that is ours is the wording of the camera purpose string (the `NSCameraUsageDescription` value), given below.

## Fidelity

**High-fidelity.** Final colors, typography, spacing, copy, and interactions. Recreate pixel-accurately using the codebase's own primitives. Where a native platform control exists (toggles, alerts, sheets, keyboards), prefer the native control over a hand-drawn replica — the visual spec below describes intent, not a mandate to reimplement UIKit.

Phone screens are designed at **402 × 874 pt** (iPhone 16 Pro logical size). The extension popup is **360 px wide**, height content-driven. The extension settings page is a normal web page with a 760 px max content width.

---

## Design Tokens

### Color

| Token | Hex | Use |
|---|---|---|
| `paper` | `#F7F5F1` | App background, light screens |
| `paper-sunk` | `#F2EFE9` | Inset panels, secondary chips, quiet cards |
| `paper-field` | `#EDEAE3` | Search field fill |
| `surface` | `#FFFFFF` | Cards, rows, popup body |
| `ink` | `#1B1A17` | Primary text, dark screens, avatar tiles |
| `ink-dark-grad` | `#1B1A17` → `#221F1B` | Vertical gradient on request/lock screens |
| `ink-darkest` | `#12110F` | Camera scan screen background |
| `green` | `#2F6F5B` | Primary action, accent, success, secure state |
| `green-hover` | `#38826B` | Primary hover (desktop only) |
| `green-bright` | `#3E9A76` | Primary action **on dark backgrounds** |
| `green-bright-hover` | `#4CB187` | Its hover |
| `green-pale` | `#E4EFE9` | Success chip fill, light-on-green badges |
| `green-tint` | `#F1F7F4` | Copied-row fill |
| `mint` | `#7FD1AC` | Accent on dark: pulse rings, scan corners, live dots |
| `mint-pale` | `#B8E0CE` | Success mark on green backgrounds |
| `green-deep` | `#1B4636` | Text on `mint-pale`, text on `paper` over green |
| `danger` | `#8A3123` | Destructive text, denied popup accent |
| `danger-bg` | `#7A2E22` | Full-screen blocked/intrusion background |
| `ink-70` | `rgba(27,26,23,.7)` | Body text on paper |
| `ink-60` | `rgba(27,26,23,.6)` | Secondary body |
| `ink-50` | `rgba(27,26,23,.5)` | Tertiary / metadata |
| `ink-45` | `rgba(27,26,23,.45)` | Section labels, disabled |
| `ink-16` | `rgba(27,26,23,.16)` | Secondary button border, off-toggle track |
| `ink-06` | `rgba(27,26,23,.06)` | Card hairline border |
| `paper-85` | `rgba(247,245,241,.85)` | Body text on dark |
| `paper-55` | `rgba(247,245,241,.55)` | Secondary text on dark |
| `paper-20` | `rgba(247,245,241,.2)` | Secondary button border on dark |

Two backgrounds only: paper and ink. Green is reserved for *approve*, *secure*, and *success* — it never appears as decoration. Red appears only when something was blocked or is destructive.

### Typography

- **UI face:** Instrument Sans (400/500/600/700). Substitute the codebase's humanist sans if one is already in use; do not substitute Inter or Roboto by default — the warmth is deliberate.
- **Codes:** JetBrains Mono (400/500/700). Any monospace with clearly distinguished `0`/`O` and `1`/`l` is acceptable. **All six-digit codes are rendered as `NNN NNN` with a single space** — the space is presentational only; clipboard writes the six bare digits.

| Role | Size / weight / tracking |
|---|---|
| Screen title (hero) | 32–34 px / 600 / -.028em / line-height 1.14–1.18 |
| Screen title (standard) | 26–29 px / 600 / -.024em / 1.2 |
| Page heading (`Codes`, `Security`) | 32 px / 600 / -.02em |
| Card title | 16–17 px / 600 / -.01em |
| Body | 14.5–16 px / 400 / line-height 1.55–1.6 |
| Secondary body | 13–13.5 px / 400 / 1.5 |
| Metadata | 12.5 px / 400 |
| Section label | 11.5 px / 400 / .08em / uppercase / `ink-45` |
| Badge | 10.5 px / 700 / .06em / uppercase |
| Code, list row | 19 px / 500 / .04em, mono |
| Code, card grid | 22 px / 500 / .02em, mono |
| Code, detail hero | 38 px / 500 / .03em, mono |
| Code, "show me" screen | 52 px / 500 / .04em, mono |
| Primary button | 16.5 px / 700 |
| Secondary button | 15.5–16 px / 600 |

### Spacing, radius, shadow

- Screen padding: `74–78px` top / `22–26px` sides / `40–44px` bottom. The top value clears the status bar and notch; use safe-area insets in the real build rather than the literal number.
- Card list: `8px` between rows, `14px` outer inset (rows are wider than the screen's text gutter — this is intentional).
- Radii: pill `99px` · button/card `18px` · large card `20–22px` · row/panel `14–16px` · field `12–14px` · tile `10–13px` · chip `7–8px`.
- Elevation is used sparingly: popup `0 24px 60px rgba(27,26,23,.22), 0 0 0 1px rgba(27,26,23,.07)`; bottom sheet `0 -20px 60px rgba(27,26,23,.25)`. Cards use a 1px hairline, never a shadow.
- Hit targets: every tappable row and button is ≥ 44 pt tall.

### Motion

- `riseIn` — full-screen state entry: `translateY(18px) → 0`, `opacity 0 → 1`, **320 ms ease-out** (280–300 ms for success/denied screens).
- `pulseRing` — waiting indicator: a ring at `scale(1) opacity .5` → `scale(1.35) opacity 0` over **1.3–2.2 s ease-out, infinite**. Faster (1.3–1.5 s) for "act now" (touch your key), slower (1.6–2.2 s) for "we're waiting on something else".
- Copy feedback, toggles, layout swaps: **180 ms ease** on background and border-color.
- The 30-second countdown bar animates `width` with **900 ms linear** so it moves continuously against a 1 s tick.
- No spring physics, no bounce, no parallax, no confetti.

---

## Screens

Every screen below maps to a numbered option in `Authenticator Mobile.dc.html` (`1a`, `2a`, `4f`…). The prototype is organized in reverse-chronological "turns"; the ids are stable.

### A. iOS app

#### A1 · First launch (`4a`)
Cold-start explainer. Ink-green logo tile 48 px, hero title *"A password isn't enough on its own."*, a paragraph, then three ticks: nothing leaves this phone but six digits / works on a plane, with no signal / no account to make, no email to give. Primary **Set it up — about two minutes**, secondary **I already have a recovery kit** (routes to recovery, C1).

#### A2 · Master password (`4b`)
Step 1 of 3. Progress is three pills (active = 22 × 6 px green, inactive = 7 × 6 px `ink-16`) plus "Step 1 of 3". Title *"Pick one password to lock this app"*. Guidance: *three unrelated words beat one word with symbols.* Masked field (green border when focused) with a **Show** affordance, a strength bar (green fill, label "Strong — good"), a confirm field, then a `paper-sunk` note: *"If you forget it, we can't reset it for you — we never see it. Your recovery kit is the way back."* Continue is disabled until both fields match and strength ≥ strong.

#### A3 · Face ID (`4c`)
Step 2 of 3. Title *"Use your face instead of typing it"*. Crucial copy, keep verbatim: *"Face ID just opens the app faster. Your password still exists underneath, and you'll need it after a restart."* Primary **Turn on Face ID**, secondary **I'll type my password** — declining is a first-class path.

#### A4 · Recovery kit (`4d`)
Step 3 of 3. Twelve words in a 2-column grid, each `paper` chip with a `10.5px` ordinal and a mono word. Warning: *"Don't screenshot these. A photo in your camera roll is a copy anyone who unlocks your phone can read."* Primary **Print my kit**, secondary **I wrote them down by hand**. Suppress screenshots on this screen where the platform allows.

#### A5 · Empty vault (`4e`)
Dashed 66 px placeholder, *"No accounts yet"*, and instructions phrased in the user's terms: *"Go to a site's security settings, choose 'authenticator app', and point this phone at the QR code it shows you."* Two buttons: **Scan a QR code** / **Type a setup code instead**.

#### A6 · Vault (`1a`, Codes tab)
The main screen. Header `Codes` + account count. Search field (`paper-field`, 14 px radius). A refresh row: label **"Tap to copy · Ns"** and a 3 px progress bar that empties over the 30 s window.

Two layouts, user-switchable in Security (A9):

- **One per row** (default): 42 px avatar tile in the account's brand color, name + username stacked, the code right-aligned at 19 px mono, then a **32–38 px copy button** at the far right (`paper-sunk` fill, `ink-55` glyph).
- **Two-up cards**: 2-column grid, 20 px radius cards; dot + name, then the code with a 32 px copy button beside it, then the username.

The copy glyph is two offset 12 × 14 sheets — back sheet top-left at 55% opacity, front sheet bottom-right filled with the button's own background so it occludes cleanly.

**Copy behavior:** tapping *anywhere* on the row (or the button) writes the six bare digits to the clipboard. For 2 s the row fills `green-tint`, its border turns green, the copy button inverts (green fill, paper glyph), and the username line is replaced by **"Copied"** in green 600. Then it reverts. Only one row can be in the copied state at a time.

**Hide codes until tapped** (Security toggle): codes render as `••• •••` and reveal only in the copied state.

Bottom tab bar floats over a `paper`-to-transparent gradient: **Codes** / **Security**, plus a **Replay** affordance that exists only in the prototype — do not ship it.

#### A7 · Search (`4i`)
Filtered list with the matched substring highlighted in `green-pale`. Result count reads *"1 of 6 accounts"*. Footer note: *"Searching looks at the site name and your username — not the codes themselves."*

#### A8 · Account detail (`4j`)
Header with 52 px tile, name, username. A code card: 38 px mono code, countdown row, full-width **Copy code**. Then *Where this lives* — which devices hold this secret, phrased as reassurance: *"Two copies — you're covered if one goes missing."* Then Rename / Move to top / **Remove this account**, the last in `danger` with the consequence spelled out: *"Turn off two-step on GitHub first, or you'll lock yourself out of it."*

#### A9 · Security (`1a`, Security tab)
Top card, full green: a `mint-pale` status dot, label **YOU'RE COVERED**, then *"Your two factors live on two separate devices."* and *"If someone steals your laptop, they still can't get in. They'd need this phone or your security key too."*

*If you lose this phone* — Recovery kit row (with "Saved 12 Mar" and View / Print again) and Your other device (the paired security key).

*How your codes look* — two picker tiles (One per row / Two-up cards) that draw miniature layout diagrams; the selected one gets a green border plus a 1 px inset ring. Below, the **Hide codes until tapped** toggle, subtitled *"Good for cafés and open offices."*

*On this phone* — Unlock with Face ID (subtitle: *"Opens the app — not a second factor"*) and Encrypted backup (*"We store scrambled copies we can't read"*).

#### A10 · Locked (`4h`)
Dark gradient, lock glyph, *"Locked"*, *"Your codes are here and safe. Look at the phone to open up."* Primary **Unlock with Face ID** in `green-bright`, text link **Use my password**.

#### A11 · Incoming request (`1a`, push state)
Dark, `riseIn`. This is triggered **by the extension**, so the language is about the browser wanting something, never "login request":

- Header: app tile, *"Waiting for a code"* / **github.com**
- Title: **"Your browser needs a code. Send it?"**
- Detail block: Account / Browser (`Chrome · MacBook Air`) / Asked (`4 seconds ago · Lisbon`)
- **Send the code** (`green-bright`) · **I didn't ask for this** (outline) · **Just show me the code** (text) · footer *"Your codes stay on this phone. Only the six digits travel."*

#### A12 · Show the code instead (`1a`, codeOnly state)
The manual escape hatch. 52 px mono code, countdown, *"Nothing was sent to your browser. Type or paste it yourself."* **Copy code** primary (label flips to **Copied** for 2 s), **Send it to my browser instead** secondary.

#### A13 · Biometric confirm (`1a`, bio state)
Blurred dark scrim, a 96 px rounded square with a pulsing ring, *"Look at your phone"* / *"Confirming it's really you"*. Auto-advances on success. In the real build this is the system Face ID prompt with this screen behind it.

#### A14 · Approved (`1a`, done state)
Full green. `mint-pale` check, **"You're in."**, *"github.com is signing you in on your MacBook. Nothing left to type."*, then a note that the code expires in 30 seconds and is single-use. **Done**.

#### A15 · Denied (`1a`, denied state)
Full `danger-bg`. **"Blocked. Nothing was sent."** — *"Someone tried to sign in as you. Your codes never left this phone — they got nothing."* Offers to walk them through a password change. **Got it**.

#### A16 · Intrusion aftermath (`4k`)
The screen a person lands on later. Header *"Blocked · 2 minutes ago"*, title **"Someone has your GitHub password."**, then the honest framing: they couldn't get in, but the password is out there. Details: where from / browser / how many attempts. Buttons **Okay** and **Mute requests for this site today** (today = the current calendar day, resetting at local midnight — not a rolling 24 h).

#### A17 · Add an account, scan (`4f`)
Dark. Four 44 px mint corner brackets on a 244 px square. *"Hold the QR code inside the corners"* / *"It's on the site's security page, usually next to 'set up authenticator app'."* Always offer **Type the code by hand instead**.

#### A18 · Add an account, manual (`4g`)
Three labelled fields: Site or app / Your username there / Setup code — the long one, the last in mono with *"Spaces and capitals don't matter."* As soon as the secret parses, a `green-pale` confirmation appears: **That code works** with the first generated code shown. Primary **Save Ledgerly**.

#### A19 · Add a second device (`4l`)
Two options: **A security key** (marked BEST, green selected treatment) and **An old phone or tablet**. Framing throughout is loss-tolerance, not security theater: *"One device is one thing to lose."* Footer: *"Your paper kit already covers the worst case. This is about making the ordinary case painless."*

### B. Browser extension

#### B1 · First-run pairing (`2d`) — 3 steps in a card on a page
- **Intro:** *"Your phone is the key. This is the keyhole."* Three promises (codes stay on the phone / works offline, no account / unpair from either side). Primary **Pair my phone**, secondary text **I use a security key instead**.
- **Scan:** instructions naming the exact path (*Security → Pair a computer*), a 216 px QR block, a typeable fallback code `MOSS-TIDE-9417` in mono at 24 px / .14em, and a pulsing *"Waiting for your phone…"*.
- **Paired:** green check, *"Paired with 'Ada's iPhone'"*, the device row with an ACTIVE badge, and a dashed card nudging a backup device: *"One device is one thing to lose. Takes 30 seconds now, saves a bad afternoon later."*

Step indicator: dots that stretch to 18 px when reached, plus "Step N of 3".

#### B2 · Autofill (`2a`) — the core desktop flow
Anchored popup, 360 px, positioned under the toolbar with a 14 px rotated-square arrow. Header: brand tile, "Two Keys", **All codes** link.

Matched-entry chip is always visible: site tile, domain, username, **MATCHED** badge on `green-pale`.

States:
1. **Ready** — *"Ready when you are."* / *"Your code has to come from something you're holding — pick one."* Then **Touch your key** (green, primary) and **Ask my iPhone** (outline).
2. **Key waiting** — pulsing ring around a key glyph, *"Touch the key now"*, *"The little disc on your YubiKey. That's the whole password."*
3. **Phone waiting** — *"Sent to your iPhone"*, *"Approve it there and the code lands here. Your secret never leaves the phone."*, plus **Cancel**. This state fires the push in A11.
4. **Filled** — green check, *"Filled in for you."*, and a route-specific note (key: *"Your key unlocked the vault right here on this Mac. Your phone stayed in your pocket."*; phone: *"Your iPhone made the code and sent only those six digits. Nothing else crossed over."*).

On the page behind: six 52 × 62 px code boxes whose borders turn green as digits arrive, and a submit button that flips from disabled *Verify* to green **Signing you in…**.

#### B3 · Popup vault (`2b`)
Compact list — 30 px tiles, 14 px names, 16 px mono codes — with search and a shared countdown at the foot.

#### B4 · Locked popup (`2c`)
Ink background. *"Locked until you prove it's you"* / *"A password on this laptop isn't enough — that's the point. Use your key or your phone."* **Touch your key** / **Unlock with my iPhone**.

#### B5 · Unmatched site (`4m`)
*"You haven't saved ledgerly.com yet"* — suggests it may be filed under another name, offers **Pick from my accounts** and **Add ledgerly.com now**, and closes with *"Nothing about this site has been sent anywhere."*

#### B6 · Three failure popups (`4n`)
- **Didn't answer** — *"It might be asleep, out of signal, or face-down on a table. Nothing's wrong with your account."* Ask again / Touch my key instead / open the app and read the code.
- **Denied** — *"You turned this one down."* Ask again / **Change my password** (danger).
- **Expired** — *"That request ran out of time"*, explains the 60 s window exists so an old request can't be approved by accident, shows ask/expire timestamps, single **Ask again**.

#### B7 · Extension settings (`4o`)
Sections: *When a site asks for a code* (Fill it in for me automatically — on; Try my key before my phone — off; Submit the form once it's filled — on), *Sites with their own rules* (per-domain overrides + Add a site), *Paired devices* (device row + **Unpair**, with *"Unpairing only affects this browser. Your codes stay on your phone, untouched."*).

### C. Recovery

#### C1–C5 · Lost-phone storyboard (`3a`–`3f`)
1. **New phone, empty app** — *"Lost the phone with your codes on it?"* Reassure first: *"You can get everything back."*
2. **Which do you still have?** — Security key (FASTEST) / Recovery kit / **Neither, right now**, the last answered with *"That's OK — nothing is lost. Go get one of them and come back. We'll wait."*
3a. **Key route** — hold the key to the top of the phone, pulsing rings.
3b. **Paper route** — twelve word fields in a 2-column grid, filled ones bordered `ink-10`, the active one green; a disabled button counting down *"4 words to go"*.
4. **Restoring** — a progress bar and three plain checkpoints (found your encrypted backup / your words unlocked it / putting 6 accounts back), with *"This all happens on this phone."*
5. **Back** — *"All 6 accounts are back."*, the old phone is cut off, and one job left: **Print my new kit** (the old sheet is retired on use).

#### C6 · Printed recovery kit (`Recovery Kit.dc.html`)
One US-Letter page, portrait, `0.62in × 0.68in` margins, pure black-on-white so it photocopies. Structure: masthead with account + print date and *"Keep this on paper. Don't photograph it."* → what the sheet is → **the twelve words** in a 4 × 3 grid inside a 2.5 px black border → *How to use it* (4 numbered steps, the last being "print a fresh kit — this sheet stops working the moment you use it") beside *Good to know* (the words are not a password; anyone holding this can restore your codes; print another from Security → Recovery kit) → a dashed tear-off strip with a QR of the same secret, explicitly labelled as cuttable if the person would rather not keep a scannable copy. Footer carries Kit ID, account count, and "Replaces all earlier kits".

### D. Permissions (`5a`–`5g`)

Both permissions follow one rule: **never ask cold, ask at the moment of intent, always leave a way to finish the job after a refusal.**

**Camera** — requested only when the user taps Scan.
- `5a` **Priming sheet** (ours): *"The camera is only for reading QR codes"* — *"iPhone will ask for permission next. We use the camera to read the setup QR code a site shows you — nothing is photographed, saved, or sent anywhere."* **OK, ask me** / **I'll type the code by hand**. Tapping the secondary never triggers the system prompt, preserving the one-shot grant.
- `5b` **System alert** (Apple's). `NSCameraUsageDescription` = *"To read the setup QR code a site shows you. Photos are never taken or stored."*
- `5c` **Denied**: *"No camera — that's completely fine."* Explains every site also shows the code as text. Primary is **Type the code instead**; **Open iPhone Settings** is secondary. Denial must never block adding an account.

**Notifications** — deferred until there is at least one account *and* a paired browser, i.e. the first moment a push has something to say.
- `5d` **Priming** (ours): *"Want the code to come to you?"*, an inline preview of the exact push, and the promise *"That's the only kind of notification we send. No tips, no news, no nudges."* **Turn on notifications** / **Not now — I'll open the app myself**.
- `5e` **System alert** (Apple's).
- `5f` **Denied**: a dismissible banner at the top of the vault — *"Notifications are off, so open the app when your browser asks"* / *"Requests will be waiting here for a minute. Everything still works — it's just one extra step."* with **Turn them on** / **Keep them off**.
- `5g` Android equivalent (Material 3 runtime dialog) for the same beat.

---

## Interactions & Behavior

### TOTP timing
- Codes are 6 digits on a **30 s** window, aligned to Unix epoch (standard TOTP). All accounts roll simultaneously.
- Countdown copy: `Tap to copy · Ns` in the vault, `New code in Ns` on detail/manual screens.
- Progress bars animate width linearly over the remaining window; recompute on every tick rather than relying on CSS animation duration alone (the app can be backgrounded).

### Copy to clipboard
- Tap target is the entire row plus the explicit button.
- Write **six bare digits**, no space.
- Feedback lasts 2 s and is visual only — no toast, no haptic beyond a light impact.
- If `hideCodes` is on, copying temporarily reveals the code for that same 2 s.

### Approval request lifecycle
1. Extension detects a 2FA field, matches the domain against saved accounts.
2. User picks key or phone.
3. Phone route sends a push → A11. The request is valid for **60 s**, after which the extension shows B6-expired and the phone's screen dismisses.
4. Approve → biometric → the code is transmitted → A14 on the phone, filled state on the desktop.
5. Deny → A15 on the phone, denied popup on the desktop. **No code is generated or sent.**
6. "Just show me the code" → A12. The extension is told nothing; it eventually expires.

### Navigation
- Tab bar: Codes ⇄ Security, persistent.
- Full-screen states (request, approved, denied, code-only, biometric) cover the vault and dismiss back to it.
- Onboarding is linear with no skip on steps 1–2; step 3 (recovery kit) can be deferred but must re-nudge from Security.

### Empty, loading, error
- Empty vault → A5.
- Restoring → C4's checkpoint list; never a bare spinner.
- Manual entry validates the secret client-side and confirms with a live first code before saving.
- Network failure on the desktop → B6-didn't-answer, which is framed as normal, not as an error.

---

## State Management

**iOS app**
```
vault: Account[]            // id, siteName, username, brandColor, secret (Keychain / Secure Enclave)
layout: 'list' | 'cards'    // persisted
hideCodes: boolean          // persisted
copiedId: string | null     // transient, 2s timeout
screen: 'vault' | 'security' | 'request' | 'codeOnly' | 'biometric' | 'approved' | 'denied' | 'locked'
pendingRequest: { site, account, browser, device, location, askedAt, expiresAt } | null
tick: number                // 1 Hz, drives all countdowns
permissions: { camera: 'unasked'|'granted'|'denied', notifications: same }
onboarding: { step, hasMasterPassword, faceIdEnabled, kitPrinted }
```

**Extension**
```
pairedDevice: { name, pairedAt, lastUsed } | null
matchedAccount: Account | null      // from active tab's domain
flow: 'idle' | 'ready' | 'awaitingKey' | 'awaitingPhone' | 'filled' | 'denied' | 'expired' | 'unreachable'
via: 'key' | 'phone'
settings: { autofill, preferKey, autoSubmit, siteRules: Record<domain, rule> }
```

Secrets live in the platform keychain and never enter component state. The extension holds **no secrets at all** — it holds a pairing and a matched-account reference.

---

## Assets

None. Every mark in the prototypes is CSS: the brand tile is a rounded square with the letter "2"; account avatars are colored tiles with the site's initial; the copy, key, phone, lock, and camera glyphs are composed from bordered divs; QR codes are deterministic grids standing in for real ones.

For production: use real generated QR codes, and replace initial-tiles with fetched favicons where available (keeping the initial as fallback). The brand mark itself needs a designed icon — out of scope here and explicitly not designed.

Fonts load from Google Fonts in the prototype; bundle them in the real build.

---

## Files

| File | What it is |
|---|---|
| `Authenticator Mobile.dc.html` | Every app and extension screen. Organized in turns, newest first: **5** permissions · **4** remaining screens · **3** lost-phone storyboard · **2** extension · **1** the clickable core flow. Options carry stable ids (`1a`, `4f`…) referenced throughout this README. |
| `Recovery Kit.dc.html` | The printable recovery sheet. Prints to US Letter as-is. |
| `ios-frame.jsx`, `android-frame.jsx`, `browser-window.jsx` | Presentation-only device chrome. **Do not port.** |
| `doc-page.js` | Print shell for the recovery kit. Not part of the product. |
| `support.js` | Prototype runtime. Not part of the product. |

Open the HTML files directly in a browser. `1a`, `2a`, and `2d` are interactive — click through them; everything else is a static frame.
