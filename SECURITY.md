# Security policy

Purr is a 2FA authenticator, so security reports matter more here than
anywhere else. Thank you for taking the time.

## Reporting a vulnerability

Please report vulnerabilities **privately** — not in a public issue:

- Preferred: [GitHub private vulnerability reporting](https://github.com/LunaNiermann/Purr/security/advisories/new)
  ("Report a vulnerability" on the repo's Security tab).
- Or email: **luna@not-final.com** (subject starting with `[Purr security]`).

Include what you found, where (app / extension / relay), and how to reproduce
it. A proof of concept helps; a fix suggestion is welcome but not expected.

You can expect an acknowledgement within a few days. This is a solo,
donation-funded project — there is no bug bounty, but reports are taken
seriously, fixed with priority, and credited in the release notes if you want.

## Scope

- The Flutter app (`app/`), the browser extension (`extension/`), and the
  relay server (`server/`), including the deployed relay at
  `https://2fa.apps.not-final.com`.
- Especially interesting: anything that breaks the zero-knowledge design —
  plaintext TOTP secrets or codes reaching the relay, the extension, or any
  log; backup blobs decryptable without the kit or master password; pairing
  or approval flows that release a code to an unpaired party.

Out of scope: denial of service against the public relay, reports requiring a
rooted/compromised device, and social engineering.

## Supported versions

Only the latest release of each surface is supported. There is no LTS; fixes
ship as a new release.
