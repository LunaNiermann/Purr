import Fastify, { type FastifyInstance } from "fastify";
import rateLimit from "@fastify/rate-limit";
import type Database from "better-sqlite3";
import { cleanup, openDb } from "./db.js";
import { createPusher, type Pusher } from "./fcm.js";
import { Waiters } from "./waiter.js";
import { registerPairingRoutes } from "./routes/pairings.js";
import { registerRequestRoutes } from "./routes/requests.js";
import { registerBackupRoutes } from "./routes/backups.js";

export interface AppContext {
  db: Database.Database;
  pusher: Pusher;
  waiters: Waiters;
}

export interface AppOptions {
  dbPath?: string;
  fcmServiceAccount?: string | undefined;
  trustProxy?: boolean;
}

export async function buildApp(opts: AppOptions = {}): Promise<FastifyInstance> {
  const app = Fastify({
    logger: { level: process.env.LOG_LEVEL ?? "info" },
    trustProxy: opts.trustProxy ?? true, // behind Coolify's Traefik
    bodyLimit: 512 * 1024,
  });

  const ctx: AppContext = {
    db: openDb(opts.dbPath ?? process.env.DB_PATH ?? "data/twokeys.sqlite"),
    pusher: createPusher(
      opts.fcmServiceAccount ?? process.env.FCM_SERVICE_ACCOUNT,
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

  app.get("/healthz", async () => ({ ok: true }));

  registerPairingRoutes(app, ctx);
  registerRequestRoutes(app, ctx);
  registerBackupRoutes(app, ctx);

  const sweeper = setInterval(() => cleanup(ctx.db), 30_000);
  sweeper.unref();
  app.addHook("onClose", async () => {
    clearInterval(sweeper);
    ctx.db.close();
  });

  return app;
}
