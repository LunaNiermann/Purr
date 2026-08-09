# Authenticator App Pain-Point Research Report

Research on real-world user complaints, reviews, breach reports, and community discussions for existing 2FA apps. Compiled 2026-08-09.

---

## 1. Twilio Authy — the cautionary tale

### 1.1 Desktop app shutdown (2024)
- Twilio announced in January 2024 that Authy desktop apps (Windows/macOS/Linux) would die in August 2024, then **killed them early on March 19, 2024** — earlier than promised ([Android Police](https://www.androidpolice.com/authy-kill-desktop-apps-early/), [MacRumors](https://www.macrumors.com/2024/02/15/authy-desktop-apps-end-of-life-march-2024/)).
- Users were force-logged-out; anyone who hadn't migrated to mobile was **locked out of their codes entirely**, and some who did migrate hit broken sync ([XDA](https://www.xda-developers.com/authy-desktop-app-end/), [TechFinitive](https://www.techfinitive.com/authy-desktop-2fa-app-shuts-down-leaving-many-users-in-perilous-position/)).
- The only stated reason was corporate: to "streamline our focus" — no user-benefit justification, which amplified the sense of betrayal ([TechTimes](https://www.techtimes.com/articles/307007/20240802/twilio-ends-support-authy-desktop-application-what-happened-users.htm), [Cyber Express](https://thecyberexpress.com/authy-desktop-app-alternate-options-for-users/)).

### 1.2 Export lockout — the #1 grievance
- Authy has **never offered any export** of TOTP secrets; the format is locked and proprietary. After the desktop app died, even the community workaround (a Go tool that talked to the desktop app's local store, pinned to old version 2.2.3) stopped being viable ([alexzorin/authy on GitHub](https://github.com/alexzorin/authy), [gboudreau gist](https://gist.github.com/gboudreau/94bb0c11a6209c82418d01a59d958c93), [bentasker.co.uk migration writeup](https://www.bentasker.co.uk/posts/blog/general/switching-to-aegis-for-totp-codes.html)).
- Hacker News, on a 2025 incident where Authy corrupted a user's backup: *"They've done everything to trap customers into their broken platform, primarily by never allowing the user to export their tokens."* Commenters also reported Authy refusing to run on GrapheneOS and support responses that ignored the described problem ([HN thread](https://news.ycombinator.com/item?id=44041892)).
- Extra lock-in layer: services built on the Authy TOTP SDK (Gemini, Twitch, SendGrid, Twilio itself) mean users **can't even delete their Authy account** after migrating without risking lockout from those services ([Stratum wiki](https://stratumauth.com/wiki/import-from-authy), [AuthenticatorPro wiki](https://github.com/jamie-mh/AuthenticatorPro/wiki/Importing-from-Authy)).

### 1.3 Phone-number identity model and the 2024 breach
- Authy accounts are keyed to a **phone number**, so account identity inherits every weakness of the telco system (SIM swap, number recycling, SMS phishing).
- July 2024: ShinyHunters abused an **unauthenticated API endpoint** to verify/enumerate **33,420,546 phone numbers** linked to Authy accounts (plus account IDs, status, device counts) and leaked the CSV — directly enabling targeted phishing and SIM-swapping against people known to use 2FA ([BleepingComputer](https://www.bleepingcomputer.com/news/security/hackers-abused-api-to-verify-millions-of-authy-mfa-phone-numbers/), [CPO Magazine](https://www.cpomagazine.com/cyber-security/twilio-data-breach-that-exposed-33-million-authy-phone-numbers-caused-by-unsecured-api-endpoint/), [Forbes](https://www.forbes.com/sites/kateoflahertyuk/2024/07/04/authy-warns-33-million-users-update-your-ios-or-android-app-now/), [The Hacker News](https://thehackernews.com/2024/07/twilios-authy-app-breach-exposes.html)). Twilio faced a class-action investigation ([PR Newswire](https://www.prnewswire.com/news-releases/privacy-alert-twilio-under-investigation-for-data-breach-of-over-33-million-authy-mfa-users-302191245.html)).

### 1.4 Backup-password and sync fragility
- The backups password is client-side only (good), but unrecoverable if forgotten, and users report **silent backup corruption** — codes present but undecryptable, fixed only by a later app update ([Twilio help](https://help.twilio.com/articles/19753577376155-Reconfigure-Authy-After-a-Lost-or-Forgotten-Backups-Password), [HN: "Authy corrupted my 2FA backup"](https://news.ycombinator.com/item?id=44041892)).

---

## 2. Google Authenticator

### 2.1 2023 cloud sync without E2EE
- April 2023: Google finally added cloud sync — then Mysk researchers found synced secrets were **not end-to-end encrypted**: Google could read the TOTP seeds on its servers, and there was **no passphrase option** ([MacRumors](https://www.macrumors.com/2023/04/27/google-authenticator-cloud-sync-no-e2e/), [SC Media](https://www.scworld.com/news/google-authenticators-syncing-security-concerns)). Mysk advised users to leave sync off.
- Google promised E2EE "down the line" in 2023 ([BleepingComputer](https://www.bleepingcomputer.com/news/google/google-will-add-end-to-end-encryption-to-google-authenticator/), [Malwarebytes](https://www.malwarebytes.com/blog/news/2023/05/google-will-eventually-add-end-to-end-encryption-to-google-authenticator)) — and as of late 2025 it **still had not shipped**; Google account sync remains not-E2EE ([CyberInsider](https://cyberinsider.com/google-authenticators-cloud-sync-security-not-up-to-the-task/), [guptadeepak.com 2026 comparison](https://guptadeepak.com/tools/top-5-two-factor-authentication-apps-2026/)). Users are forced to choose: recoverability with Google-readable secrets, or local-only with loss risk.

### 2.2 Historical data-loss horror stories
- The archetypal failure: for ~13 years the app had **no backup at all**. Break/lose the phone → lose every code → per-service account recovery (days for Coinbase, up to weeks for smaller exchanges) ([Avast guide](https://www.avast.com/c-lost-phone-google-authenticator), [Daito](https://www.daito.io/how-to-log-in-with-2FA-when-you-lose-your-phone-eg-for-google-authenticator/), [AnandTech forums](https://forums.anandtech.com/threads/what-happens-if-you-use-google-authenticator-for-3rd-party-services-and-lose-your-phone.2559199/post-39773059)).
- A 2013 iOS update **wiped all stored accounts on install** with no warning — an infamous incident still cited as why people distrust authenticator updates ([TNW](https://thenextweb.com/news/google-authenticator-for-ios-update-reportedly-wipes-all-existing-user-accounts), [TechCrunch](https://techcrunch.com/?p=871591)). Similar "update wiped my codes" threads recur on Google's own support forum ([example](https://support.google.com/accounts/thread/223711607/ios-google-authenticator-update-wiped-all-codes?hl=en), [GitLab forum case](https://forum.gitlab.com/t/google-auth-removed-my-code-when-i-got-new-phone-recover-codes-not-working/104151)).

### 2.3 Migration pain
- Phone-to-phone transfer requires both phones side-by-side scanning "export accounts" QR codes (multiple QRs for many accounts); failures come from outdated app versions, no biometric enrolled, etc. ([TechRadar how-to](https://www.techradar.com/how-to/how-to-transfer-google-authenticator-to-a-new-phone), [helpdeskgeek](https://helpdeskgeek.com/how-to-move-google-authenticator-to-a-new-phone-without-losing-access/)). No desktop app, no watch app; Play Store rating (~3.6) sits far below Aegis (~4.8) ([Yahoo Tech/aegis piece](https://tech.yahoo.com/general/articles/aegis-authenticator-200000321.html)).

---

## 3. Microsoft Authenticator

### 3.1 Backup/restore failure epidemic
- Microsoft Q&A is saturated with "no backup found" / "your backup is not stored with this email" / "Begin Recovery shows nothing" threads after phone changes ([1](https://learn.microsoft.com/en-us/answers/questions/1865655/microsoft-authenticator-no-backup-found-after-chan), [2](https://learn.microsoft.com/en-us/answers/questions/1206671/backup-restore-failed-on-new-phone-your-backup-is), [3](https://learn.microsoft.com/en-us/answers/questions/2286302/unable-to-restore-microsoft-authenticator-cloud-ba), [4](https://learn.microsoft.com/en-us/answers/questions/840924/microsoft-authenticator-unable-to-recover-backup)). If the backup account itself is inaccessible, support cannot recover anything.
- Root confusion: on iOS the backup lived in **iCloud but was keyed to a personal Microsoft account** (work/school accounts not allowed), and **iOS backups cannot be restored on Android** or vice versa ([cloudcoffee.ch](https://www.cloudcoffee.ch/microsoft-365/backup-and-restore-microsoft-authenticator-app/), [Microsoft support doc](https://support.microsoft.com/en-us/authenticator/back-up-your-accounts-in-microsoft-authenticator)). Microsoft only redesigned this in Sept–Oct 2025, moving iOS fully to iCloud/Keychain ([BleepingComputer](https://www.bleepingcomputer.com/news/microsoft/microsoft-authenticator-on-ios-moves-backups-fully-to-icloud/), [ourcloudnetwork.com](https://ourcloudnetwork.com/microsoft-to-remove-personal-account-requirement-for-microsoft-authenticator-backup/)).
- Restoring also doesn't fully restore: Entra/work accounts come back as dead placeholders needing re-registration — a detail that surprises users mid-migration.

### 3.2 The 8-year account-overwrite flaw (2024)
- Adding a new account via QR **silently overwrote any existing account with the same username** (usually an email address), locking users out of the older account. Every other authenticator disambiguates by issuer; Microsoft didn't. Microsoft initially called it user error / "a feature," and fixed it only in late 2024 after CSO Online coverage — roughly **eight years** after first complaints ([CSO Online report](https://www.csoonline.com/article/3480918/design-flaw-has-microsoft-authenticator-overwriting-mfa-accounts-locking-users-out.html), [CSO Online: fixed](https://www.csoonline.com/article/3526573/microsoft-fixes-authenticator-design-flaw-after-eight-years-overwriting-accounts.html), [Slashdot](https://it.slashdot.org/story/24/08/05/1849249/design-flaw-has-microsoft-authenticator-overwriting-mfa-accounts-locking-users-out)).

### 3.3 Strategy whiplash
- 2023: killed the **Apple Watch app** ("incompatible with security features"), angering users who wanted phone-free approvals ([TechRadar](https://techradar.com/news/microsoft-authenticator-is-dropping-apple-watch-support), [Microsoft Q&A complaint](https://learn.microsoft.com/en-us/answers/questions/1139957/why-is-microsoft-removing-authentication-from-appl)).
- 2025: **removed password autofill/password storage** from the app to push users to Edge; corporate users who had standardized on it felt burned: *"All this to just push Edge on people… it took years to get people to use it."* ([The Hacker News](https://thehackernews.com/2025/07/microsoft-removes-password-management.html), [Windows Central](https://www.windowscentral.com/software-apps/microsoft-authenticator-is-losing-autofill-but-the-tech-giant-already-has-a-replacement)).
- Chronic small-trust erosion: wrong/changed account icons ([Q&A](https://learn.microsoft.com/en-us/answers/questions/5604341/wrong-icons-in-authenticator-app)), and users asking how to wipe data entirely.

---

## 4. Bitwarden (Authenticator + main app)

### 4.1 Standalone Bitwarden Authenticator (launched May 2024)
- Launched open-source and free ([alternativeto news](https://alternativeto.net/news/2024/5/bitwarden-launches-standalone-open-source-authenticator-app-for-two-factor-authentication)), but early reviews flagged: **no cloud backup, no multi-device sync, no desktop version**, and initially weak import support ([alternativeto listing](https://alternativeto.net/software/bitwarden-authenticator), [justuseapp reviews](https://justuseapp.com/en/app/6497335175/bitwarden-authenticator/reviews)).
- The most-requested feature was **sync with TOTPs already in the Bitwarden vault**; it arrived only in mid-2025 (v2025.7.0), inconsistently, and initially not on Android ([justuseapp reviews](https://justuseapp.com/en/app/6497335175/bitwarden-authenticator/reviews), [vaultwarden discussion](https://github.com/dani-garcia/vaultwarden/discussions/6090)).
- Import bug worth remembering: exporting vault TOTPs and importing into the Authenticator **silently dropped entries whose TOTP keys contained spaces** — silent data loss during migration ([justuseapp reviews](https://justuseapp.com/en/app/6497335175/bitwarden-authenticator/reviews)).

### 4.2 Main Bitwarden app 2FA complaints
- TOTP storage in the vault is a **paid (Premium) feature**, and the perennial criticism is architectural: passwords + TOTP seeds in one vault is a **single point of failure** that "defeats the whole purpose of 2FA" — a long-running community-forum debate ([forum thread 1](https://community.bitwarden.com/t/using-the-totp-within-bitwarden-risky/58975), [thread 2](https://community.bitwarden.com/t/concerns-about-security-single-point-of-failure/87924), [thread 3](https://community.bitwarden.com/t/security-risks-of-using-bitwarden-as-authenticator-and-password-manager/17028?page=4)). The standalone app exists precisely to answer this.

---

## 5. The well-loved ones: 2FAS, Aegis, Ente Auth

### 5.1 2FAS
**Praised for:** free, no subscription, open source, clean minimal UI, iCloud/Google Drive backup, export/import, and the browser-extension flow where the phone approves a push to deliver a code to the desktop browser ([Product Hunt reviews](https://www.producthunt.com/products/2fas-2fa-authentication-app/reviews), [App Store reviews](https://apps.apple.com/us/app/2fa-authenticator-2fas/id1217793794?see-all=reviews)).
**Still criticized for:**
- Browser extension **requires the phone every time** — some users just want codes on the desktop ([Firefox add-on reviews](https://addons.mozilla.org/en-US/firefox/addon/2fas-two-factor-authentication/reviews/)).
- iCloud backup was **not user-passphrase E2EE** for a long time; users filed GitHub issues asking for client-side encryption with their own password ([twofas/2fas-ios#43](https://github.com/twofas/2fas-ios/issues/43)).
- Sync limited to the platform cloud (iCloud on iOS, Drive on Android) — **no true cross-platform sync**; moving iOS→Android is manual export/import.
- No real desktop app (extension only).

### 5.2 Aegis (Android-only)
**Praised for:** highest rating of any authenticator on Play (~4.8 vs Google's ~3.6); free, open source, no ads/trackers; vault **encrypted at rest with password/biometric unlock**; rich icon packs; powerful **import from nearly every other app and export to plaintext or encrypted JSON**; automatic local backups ([Yahoo Tech](https://tech.yahoo.com/general/articles/aegis-authenticator-200000321.html), [alternativeto](https://www.alternativeto.net/software/aegis-authenticator/about/)).
**Still criticized for:** **Android-only** — no iOS, no desktop; no built-in cloud sync (relies on Android backup or user-managed files, which techies like and normies fumble); minor organization gaps (group renaming, multiple groups per entry) ([saashub](https://www.saashub.com/aegis-authenticator), [alternativeto](https://alternativeto.net/software/aegis-authenticator/)).

### 5.3 Ente Auth
**Praised for:** truly cross-platform (Android, iOS, desktop, web), **E2EE sync by default**, open source, works fully **offline and without an account** if you skip sync, shows the **next code** so you don't get caught by rollover, good Authy-refugee onboarding ([Ente FAQ](https://help.ente.io/auth/faq/), [justuseapp reviews](https://justuseapp.com/en/app/6444121398/ente-auth/reviews), [alternativeto](https://alternativeto.net/software/ente-authenticator/)).
**Still criticized for:** no Apple Watch app ([justuseapp](https://justuseapp.com/en/app/6444121398/ente-auth/reviews)); occasional sync-not-triggering bugs ([ente#6000](https://github.com/ente-io/ente/issues/6000), [discussion #3934](https://github.com/ente-io/ente/discussions/3934)); desktop client freezes ([#3898](https://github.com/ente-io/ente/issues/3898)); wrong codes when the system clock drifts, and **offline mode can't auto-correct clock drift** ([FAQ](https://help.ente.io/auth/faq/), [discussion #3434](https://github.com/ente/ente/discussions/3434)); logout requiring API access breaks self-hosted server switching ([#8772](https://github.com/ente-io/ente/issues/8772)).

---

## 6. Cross-cutting themes

1. **Phone loss = life lockout.** The dominant horror story across all apps: no backup → per-service recovery grind (Coinbase 48–72h ID queue, Binance ~a week, small exchanges a month; a Facebook lockout that lasted over a year) ([plisio](https://plisio.net/cybersecurity/google-authenticator-transfer), [brandingbytes Facebook story](https://brandingbytes.com/regain-facebook-access-lost-google-authenticator/), [Google support thread](https://support.google.com/accounts/thread/355191057/locked-out-of-google-account-2fa-loop-need-recovery?hl=en)).
2. **Backup vs. security tension.** Every app picks a corner: Google (convenient, not E2EE), Authy (E2EE but unrecoverable password + corruptible), Aegis (local, user-managed), Ente/2FAS (E2EE cloud). Users punish both extremes: no backup and readable backup.
3. **Cloud-sync distrust.** Mysk's Google findings plus the Authy breach made "who can read my seeds, and what metadata does the vendor hold" a mainstream user question, not just a nerd one.
4. **Scam clones and subscription resentment.** App stores are flooded with fake "Authenticator App" clones charging $3.99/week or $40/year for free functionality — some **steal scanned QR seeds and exfiltrate them** ([9to5Mac](https://9to5mac.com/2023/06/22/scam-authenticator-app/), [Bitdefender](https://www.bitdefender.com/en-us/blog/hotforsecurity/shady-authenticator-apps-flood-apple-and-google-app-stores-after-twitter-shifts-from-sms-based-2fa), [ghacks](https://www.ghacks.net/2023/02/23/attackers-are-using-fake-authenticator-apps-on-app-store-to-scam-users/)). Users are conditioned to distrust any paywall in an authenticator; free-and-open-source is itself a trust signal.
5. **Organization at scale.** With 30–100 tokens, users complain about missing search, folders/groups, custom icons, and entries that are unidentifiable without icons ([Microsoft Q&A icon complaints](https://learn.microsoft.com/en-us/answers/questions/2280871/why-are-there-weird-new-icons-in-my-authenticator), 2FAS/Aegis feature requests). Google only added search in 2023's v7 redesign ([TechRadar](https://www.techradar.com/pro/google-authenticator-adds-new-features-and-a-complete-redesign)).
6. **Wearables are wanted, then abandoned.** Microsoft killed its Apple Watch app; users explicitly resent having to fetch the phone ([macobserver](https://www.macobserver.com/news/microsoft-authenticator-app-to-drop-apple-watch-support/)); Ente users request Watch support.
7. **Vendor mortality.** Authy desktop, Microsoft autofill, Raivo (went paid after acquisition — same genre) — users have learned that an authenticator can be discontinued or enshittified under them, so **exit rights (export) are now a purchase criterion**.

---

## Design Commandments for a New Open Authenticator

**Data ownership & portability**
1. **DO always allow export** — both plaintext (otpauth:// URIs / JSON) and encrypted formats, on every platform, forever. Lock-in is the single most hated behavior in this category (Authy). Support `otpauth-migration://` import from Google, and importers for Aegis/2FAS/Ente/Bitwarden formats.
2. **DON'T ever tie identity to a phone number.** No SMS, no phone-number registration, no SMS-based recovery. Use an email or no account at all. (Authy's model caused both SIM-swap exposure and a 33M-record enumeration breach.)
3. **DO make the app fully usable with zero account** — offline-first, local vault; account/sync strictly opt-in (Ente's model is the one users praise).
4. **DON'T silently drop or overwrite entries.** Never overwrite on name collision (Microsoft's 8-year flaw) — disambiguate by issuer+label and prompt to rename. Never skip entries on import (Bitwarden's space-in-key bug); validate and report every row of an import with an explicit success/failure count.

**Backup & sync**
5. **DO E2EE everything that leaves the device, from day one** — user-held key, zero-knowledge server. Shipping sync without E2EE and promising it "later" (Google, 2023→still absent) is a reputation wound that never closes.
6. **DO layer recovery**: encrypted cloud sync + user-downloadable encrypted file backup + printable recovery kit (key/mnemonic). Warn loudly, repeatedly, when a user has exactly one copy of their vault.
7. **DON'T make the backup password silently unrecoverable-and-untested.** Verify the passphrase can decrypt (periodic "prove you still know it" check or key-file escrow the user controls), and integrity-check backups so corruption is detected at write time, not at restore time (Authy's corruption incident).
8. **DO make sync cross-platform and cloud-agnostic** — same vault on Android, iOS, desktop, web/extension. Don't chain iOS users to iCloud and Android users to Drive with no bridge (2FAS, Microsoft's iOS↔Android wall).
9. **DO treat migration to a new phone as a first-class, one-tap flow** — restore from sync or file, not phone-to-phone QR chains that require the old (possibly dead) phone.

**Security engineering**
10. **DO encrypt the vault at rest** with password/biometric unlock and hide codes until unlock (Aegis's most-praised behavior); add a privacy screen and screenshot blocking by default with an opt-out.
11. **DON'T expose any unauthenticated API endpoint that confirms account existence** — rate-limit and authenticate everything; assume enumeration attacks (the Authy breach was exactly this).
12. **DO minimize server-side metadata**: no plaintext issuer/account names server-side; encrypt labels and icons, not just seeds — the vendor should not know which services a user has.
13. **DO handle clock drift**: NTP-based time offset correction with a visible "your clock is off" warning, working even without an account (Ente's offline gap).
14. **DO show the next code** alongside the current one and generous copy affordances, so rollover never invalidates a half-typed code (Ente's most-loved small feature).

**Product & trust**
15. **DON'T charge for core security functionality** and never use subscriptions for basic TOTP — the category is poisoned by scam clones charging weekly fees; free + open source + reproducible builds is the trust baseline. Fund via optional paid sync tiers or donations, never by paywalling scan/backup/export.
16. **DO invest in organization at scale**: instant search, folders/tags, pinned favorites, a large community icon pack plus custom icons, and drag reordering — the top quality-of-life complaint for users with 30+ tokens.
17. **DO ship desktop (and browser) parity that can generate codes standalone**, without requiring a phone approval round-trip for every login (2FAS extension's top complaint; Authy's desktop shutdown proves demand).
18. **DO support wearables** (Apple Watch / Wear OS) for code display, with a sane security story rather than abandonment (Microsoft's retreat left a vacuum users still complain about).
19. **DON'T break trust on updates**: migrations must be transactional with automatic pre-update local backup (Google's 2013 wipe and repeated "update ate my codes" threads created lasting update-phobia). If a feature must be sunset, give long timelines, in-app export prompts, and never move the date earlier (Authy did).
20. **DO publish a security/incident posture users can verify**: open source, third-party audits, a clear statement of what the server can and cannot see — because after Mysk and ShinyHunters, "trust us" no longer works in this category.

---

### Key sources index
Authy: [XDA](https://www.xda-developers.com/authy-desktop-app-end/) · [Android Police](https://www.androidpolice.com/authy-kill-desktop-apps-early/) · [BleepingComputer breach](https://www.bleepingcomputer.com/news/security/hackers-abused-api-to-verify-millions-of-authy-mfa-phone-numbers/) · [HN backup corruption](https://news.ycombinator.com/item?id=44041892) · [authy export tool](https://github.com/alexzorin/authy)
Google: [MacRumors/Mysk](https://www.macrumors.com/2023/04/27/google-authenticator-cloud-sync-no-e2e/) · [BleepingComputer E2EE promise](https://www.bleepingcomputer.com/news/google/google-will-add-end-to-end-encryption-to-google-authenticator/) · [TNW 2013 wipe](https://thenextweb.com/news/google-authenticator-for-ios-update-reportedly-wipes-all-existing-user-accounts)
Microsoft: [CSO overwrite flaw](https://www.csoonline.com/article/3480918/design-flaw-has-microsoft-authenticator-overwriting-mfa-accounts-locking-users-out.html) · [Q&A "no backup found"](https://learn.microsoft.com/en-us/answers/questions/1865655/microsoft-authenticator-no-backup-found-after-chan) · [BleepingComputer iCloud change](https://www.bleepingcomputer.com/news/microsoft/microsoft-authenticator-on-ios-moves-backups-fully-to-icloud/) · [Hacker News autofill removal](https://thehackernews.com/2025/07/microsoft-removes-password-management.html)
Bitwarden: [community SPOF thread](https://community.bitwarden.com/t/using-the-totp-within-bitwarden-risky/58975) · [justuseapp reviews](https://justuseapp.com/en/app/6497335175/bitwarden-authenticator/reviews)
Loved apps: [Aegis (Yahoo Tech)](https://tech.yahoo.com/general/articles/aegis-authenticator-200000321.html) · [2FAS iCloud E2EE issue](https://github.com/twofas/2fas-ios/issues/43) · [Ente FAQ](https://help.ente.io/auth/faq/) · [Ente reviews](https://justuseapp.com/en/app/6444121398/ente-auth/reviews)
Cross-cutting: [9to5Mac scam clones](https://9to5mac.com/2023/06/22/scam-authenticator-app/) · [Bitdefender clone flood](https://www.bitdefender.com/en-us/blog/hotforsecurity/shady-authenticator-apps-flood-apple-and-google-app-stores-after-twitter-shifts-from-sms-based-2fa/) · [MacObserver Watch removal](https://www.macobserver.com/news/microsoft-authenticator-app-to-drop-apple-watch-support/)
