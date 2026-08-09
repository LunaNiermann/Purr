# Purr relay server

E2EE relay + encrypted backup store for the Purr authenticator.
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

### 1. Create the resource
New resource → **Dockerfile** application from this repo. Set **Base Directory**
to `/server` (so Coolify uses `server/Dockerfile` and builds in that folder).

### 2. Domain & port
- Domain: `https://2fa.apps.not-final.com` (Coolify/Traefik terminates TLS).
- **Ports Exposes:** `3000`. The container listens on 3000; Traefik maps 443→3000.
  You do **not** need to publish a host port.

### 3. Persistent volume (the SQLite database)
The app writes `twokeys.sqlite` (+ `-wal`/`-shm`) to `/app/data`. Add a
**named** volume so it survives redeploys:

- Coolify → your app → **Storages** → **Add** → **Volume Mount**.
- **Name:** `twokeys-data` (anything).
- **Destination Path:** `/app/data`  ← must match exactly.
- **Source Path:** leave **empty**. This is the important bit — an empty source
  makes it a *named Docker volume*, and Docker seeds it with the image's
  directory ownership (`node:node`, uid 1000). If you instead type a host path
  it becomes a *bind mount* that comes in **root-owned**, and the container
  (which runs as the non-root `node` user) can't write → you'll see
  `SQLITE_CANTOPEN`. If you must use a host bind mount, `chown -R 1000:1000`
  that host directory first.

The `VOLUME /app/data` line in the Dockerfile is only a fallback (anonymous
volume); declaring the named volume here is what actually persists across
deploys, and it overrides the anonymous one.

Verify after first deploy: open the app's **Terminal** in Coolify and run
`ls -la /app/data` — you should see `twokeys.sqlite` owned by `node`.

### 4. Firebase push (optional)
Push is optional. Without it the server logs `FCM not configured — push
disabled, phones must poll` and everything still works: phones fetch pending
requests when the app opens (design 5f). Add it when you want instant delivery.

The service account is **JSON**, and you can't paste JSON into a plain env var
cleanly, so the server accepts it three ways (first match wins):

**Recommended — base64 in an env var (no file mounts):**
1. In the Firebase console for the `nl.notfinal.twofa` project → Project
   settings → Service accounts → **Generate new private key** → downloads a
   `.json`.
2. Base64-encode it (one line, no newlines):
   - macOS/Linux: `base64 -w0 service-account.json` (macOS: `base64 -i service-account.json`)
   - PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("service-account.json"))`
3. Coolify → **Environment Variables** → add `FCM_SERVICE_ACCOUNT_JSON` = that
   base64 string. Mark it a **build-time? no — runtime** secret. Redeploy.

   (Raw JSON also works if your env editor preserves newlines — the loader
   detects a leading `{` and takes it as-is, otherwise base64-decodes.)

**Alternative — a file on the volume:**
1. Put the `.json` in the `/app/data` volume (upload via the Coolify terminal,
   or `docker cp`).
2. Set `FCM_SERVICE_ACCOUNT=/app/data/fcm-service-account.json`.

A malformed or incomplete key is logged and ignored (push stays disabled)
rather than crashing the server.

### 5. Other env
- `PORT` defaults to `3000`, `LOG_LEVEL` to `info` — leave unset unless changing.
- `DB_PATH` is already `/app/data/twokeys.sqlite` (set in the Dockerfile); only
  override if you mount the volume somewhere else.

### 6. Health check
The container has a built-in `HEALTHCHECK` hitting `/healthz`. Coolify shows the
app healthy once it returns `{"ok":true}`. You can also curl
`https://2fa.apps.not-final.com/healthz` after deploy.

## Develop

```bash
npm install
npm run dev     # tsx watch, port 3000
npm test        # vitest (in-memory SQLite)
npm run typecheck
```
