import { existsSync } from "node:fs";
import path from "node:path";
import Fastify, { type FastifyInstance } from "fastify";
import rateLimit from "@fastify/rate-limit";
import fastifyStatic from "@fastify/static";
import type Database from "better-sqlite3";
import { cleanup, openDb } from "./db.js";
import { createPusher, type Pusher } from "./fcm.js";
import { Waiters } from "./waiter.js";
import { registerPairingRoutes } from "./routes/pairings.js";
import { registerRequestRoutes } from "./routes/requests.js";
import { registerBackupRoutes } from "./routes/backups.js";
import { registerReplicaRoutes } from "./routes/replica.js";

export interface AppContext {
  db: Database.Database;
  pusher: Pusher;
  waiters: Waiters;
}

export interface AppOptions {
  dbPath?: string;
  fcmServiceAccount?: string | undefined;
  fcmServiceAccountJson?: string | undefined;
  trustProxy?: boolean;
  siteDir?: string;
}

export async function buildApp(opts: AppOptions = {}): Promise<FastifyInstance> {
  const app = Fastify({
    logger: { level: process.env.LOG_LEVEL ?? "info" },
    trustProxy: opts.trustProxy ?? true, // behind Coolify's Traefik
    bodyLimit: 512 * 1024,
  });

  // Some clients send `content-type: application/json` on bodyless requests
  // (e.g. DELETE /v1/pairings/:id for unpair). Fastify's default parser 400s
  // on an empty body — tolerate it by treating empty as `undefined`.
  app.addContentTypeParser(
    "application/json",
    { parseAs: "string" },
    (_req, body, done) => {
      const text = (body as string).trim();
      if (text.length === 0) {
        done(null, undefined);
        return;
      }
      try {
        done(null, JSON.parse(text));
      } catch (err) {
        (err as { statusCode?: number }).statusCode = 400;
        done(err as Error, undefined);
      }
    },
  );

  const ctx: AppContext = {
    db: openDb(opts.dbPath ?? process.env.DB_PATH ?? "data/twokeys.sqlite"),
    pusher: createPusher(
      {
        json: opts.fcmServiceAccountJson ?? process.env.FCM_SERVICE_ACCOUNT_JSON,
        path: opts.fcmServiceAccount ?? process.env.FCM_SERVICE_ACCOUNT,
      },
      app.log,
    ),
    waiters: new Waiters(),
  };

  await app.register(rateLimit, {
    max: 240,
    timeWindow: "1 minute",
    // Long-poll /wait endpoints legitimately reconnect ~every 25 s from both
    // sides; they're cheap (they mostly block) so they're exempt from the
    // global limit. The write endpoints that matter keep their own tight
    // per-route limits (see requests.ts / backups.ts).
    allowList: (req) => req.url.includes("/wait"),
  });

  // `push` reflects whether a valid FCM service account is loaded — a quick
  // way to confirm push is configured without reading logs.
  app.get("/healthz", async () => ({ ok: true, push: ctx.pusher.configured }));

  registerPairingRoutes(app, ctx);
  registerRequestRoutes(app, ctx);
  registerBackupRoutes(app, ctx);
  registerReplicaRoutes(app, ctx);

  // Marketing site for purr2fa.app — the domain points at this same container.
  // Static files live in `site/` (copied into the image); the API stays under
  // /v1 and /healthz, so there is no route overlap.
  const siteDir = path.resolve(
    opts.siteDir ?? process.env.SITE_DIR ?? "site",
  );
  if (existsSync(path.join(siteDir, "index.html"))) {
    await app.register(fastifyStatic, {
      root: siteDir,
      index: "index.html",
      setHeaders(res, filePath) {
        // Fonts/images/CSS may cache for a day; HTML revalidates quickly so
        // policy or copy fixes propagate.
        res.header(
          "cache-control",
          filePath.endsWith(".html")
            ? "public, max-age=300"
            : "public, max-age=86400",
        );
      },
    });
    app.get("/privacy", (_req, reply) => reply.sendFile("privacy.html"));
  }

  const sweeper = setInterval(() => cleanup(ctx.db), 30_000);
  sweeper.unref();
  app.addHook("onClose", async () => {
    clearInterval(sweeper);
    ctx.db.close();
  });

  return app;
}
