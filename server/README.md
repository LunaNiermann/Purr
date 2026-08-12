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

## Marketing site (purr2fa.app)

The same container serves the static marketing site from `site/`:
`/` (landing), `/privacy`, plus `robots.txt`, `sitemap.xml`, `social-card.png`
and `/assets/*` (self-hosted fonts, images). Point the `purr2fa.app` domain at
this app in Coolify (add it as an additional domain; Traefik handles TLS) and
the API keeps working unchanged under `/v1` and `/healthz`. If `site/index.html`
is missing the static routes are simply not registered. Override the directory
with `SITE_DIR` if needed.

## Deploy on Coolify

### 1. Create the resource
New resource → application from this repo with build pack **Nixpacks** and
**Base Directory** `/server` — this is how the live instance is set up. Nixpacks
detects a Node app and runs `npm ci` / `npm run build` / `npm start`;
`nixpacks.toml` adds python3 + build-essential so better-sqlite3 can compile
from source when its prebuilt-binary download flakes. Set
`NIXPACKS_NODE_VERSION=22`.

(`Dockerfile` in this folder is *not* used by Coolify — it's kept for plain
`docker build`/`docker run` deploys and mirrors the same behavior.)

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
  directory ownership. If you instead type a host path it becomes a *bind
  mount* that comes in **root-owned** — harmless under Nixpacks (its container
  runs as root) but fatal for the Dockerfile build, whose non-root `node` user
  can't write → `SQLITE_CANTOPEN`. If you must use a host bind mount with the
  Dockerfile build, `chown -R 1000:1000` that host directory first.

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
- `DB_PATH` defaults to `data/twokeys.sqlite`, which resolves to
  `/app/data/twokeys.sqlite` in the container (Nixpacks workdir is `/app`; the
  Dockerfile sets the same path explicitly). Only override if you mount the
  volume somewhere else.

### 6. Health check
`GET /healthz` returns `{"ok":true,"push":<bool>}`. Point Coolify's health
check at it (the Nixpacks image has no baked-in `HEALTHCHECK`; only the
Dockerfile build carries one). You can also curl
`https://2fa.apps.not-final.com/healthz` after deploy.

## Develop

```bash
npm install
npm run dev     # tsx watch, port 3000
npm test        # vitest (in-memory SQLite)
npm run typecheck
```
