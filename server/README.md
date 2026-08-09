# Two Keys relay server

E2EE relay + encrypted backup store for the Two Keys authenticator.
The server never sees a TOTP secret, a code, a domain, or an account name —
only ciphertext blobs, pairing ids, FCM tokens, and timestamps.

## Endpoints

See `docs/ARCHITECTURE.md` at the repo root. Summary:

- `POST /v1/pairings` · `POST /v1/pairings/:id/complete` · `GET /v1/pairings/:id[/wait]` · `DELETE /v1/pairings/:id` · `PUT /v1/pairings/:id/fcm-token`
- `POST /v1/requests` · `GET /v1/requests` (pending, phone) · `GET /v1/requests/:id[/wait]` · `POST /v1/requests/:id/answer` · `GET /v1/requests/wait-pending`
- `PUT /v1/backups/:id` · `POST /v1/backups/:id/fetch` · `DELETE /v1/backups/:id`
- `GET /healthz`

Approval requests expire after 60 s, are single-pending per pairing, and answers
are deleted on first delivery. Backups require proof-of-knowledge (`backupAuth`,
HKDF-derived from recovery-kit entropy) on every verb, with uniform 404s so
existence can't be probed.

## Deploy on Coolify

1. New resource → Dockerfile app pointing at `server/` of this repo.
2. Domain: `2fa.apps.not-final.com` (HTTPS via Coolify/Traefik).
3. Persistent volume mounted at `/app/data`.
4. Env (optional, for push): `FCM_SERVICE_ACCOUNT=/app/data/fcm-service-account.json`
   — upload a Firebase service-account key for the `nl.notfinal.twofa` Firebase
   project into the volume. Without it, everything works except proactive push;
   phones poll pending requests when the app opens (the design's 5f behavior).
5. `PORT` defaults to 3000; `LOG_LEVEL` defaults to `info`.

## Develop

```bash
npm install
npm run dev     # tsx watch, port 3000
npm test        # vitest (in-memory SQLite)
npm run typecheck
```
