import type { FastifyInstance } from "fastify";
import type { AppContext } from "../app.js";
import type { BackupRow } from "../db.js";
import { hashToken, tokenMatches } from "../util.js";

const MAX_BACKUP_BYTES = 256 * 1024;
const ID_RE = /^[A-Za-z0-9_-]{22,64}$/;

/**
 * Encrypted backup store. No accounts: the client derives both the locator
 * (backupId) and a bearer secret (backupAuth) from the recovery-kit entropy
 * via HKDF with distinct info strings. Every verb — including GET — requires
 * backupAuth, and unknown ids and wrong auth return an identical 404, so the
 * store cannot be used to confirm that any backup exists (the Authy
 * enumeration lesson). Content is ciphertext the server cannot open; the
 * digest lets clients verify integrity at write time, not restore time.
 */
export function registerBackupRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { db } = ctx;
  const getBackup = db.prepare("SELECT * FROM backups WHERE backup_id = ?");

  function authedBackup(
    id: string,
    authHeader: string | undefined,
  ): BackupRow | null {
    const row = getBackup.get(id) as BackupRow | undefined;
    if (!row) return null;
    if (!authHeader?.startsWith("Bearer ")) return null;
    const presented = authHeader.slice(7).trim();
    return tokenMatches(presented, row.auth_hash) ? row : null;
  }

  app.put("/v1/backups/:id", {
    config: { rateLimit: { max: 20, timeWindow: "1 minute" } },
  }, async (req, reply) => {
    const id = (req.params as { id: string }).id;
    if (!ID_RE.test(id)) return reply.code(400).send({ error: "bad id" });

    const { blob, digest, backupAuth } = (req.body ?? {}) as Record<string, unknown>;
    if (typeof blob !== "string" || typeof digest !== "string" || typeof backupAuth !== "string")
      return reply.code(400).send({ error: "bad body" });
    if (backupAuth.length < 22 || backupAuth.length > 128)
      return reply.code(400).send({ error: "bad auth" });
    const bytes = Buffer.from(blob, "base64");
    if (bytes.length === 0 || bytes.length > MAX_BACKUP_BYTES)
      return reply.code(413).send({ error: "too large" });

    const existing = getBackup.get(id) as BackupRow | undefined;
    if (existing && !tokenMatches(backupAuth, existing.auth_hash))
      return reply.code(404).send({ error: "not found" });

    db.prepare(
      `INSERT INTO backups (backup_id, auth_hash, blob, digest, updated_at)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(backup_id) DO UPDATE SET blob = excluded.blob,
         digest = excluded.digest, updated_at = excluded.updated_at`,
    ).run(id, existing?.auth_hash ?? hashToken(backupAuth), bytes, digest, Date.now());
    return reply.send({ digest, size: bytes.length });
  });

  app.post("/v1/backups/:id/fetch", {
    config: { rateLimit: { max: 10, timeWindow: "1 minute" } },
  }, async (req, reply) => {
    const id = (req.params as { id: string }).id;
    if (!ID_RE.test(id)) return reply.code(400).send({ error: "bad id" });
    const { backupAuth } = (req.body ?? {}) as Record<string, unknown>;
    const row =
      typeof backupAuth === "string"
        ? authedBackup(id, `Bearer ${backupAuth}`)
        : null;
    if (!row) return reply.code(404).send({ error: "not found" });
    return reply.send({
      blob: row.blob.toString("base64"),
      digest: row.digest,
      updatedAt: row.updated_at,
    });
  });

  // Kit rotation retires the old blob ("Replaces all earlier kits").
  app.delete("/v1/backups/:id", async (req, reply) => {
    const id = (req.params as { id: string }).id;
    if (!ID_RE.test(id)) return reply.code(400).send({ error: "bad id" });
    const row = authedBackup(id, req.headers.authorization);
    if (!row) return reply.code(404).send({ error: "not found" });
    db.prepare("DELETE FROM backups WHERE backup_id = ?").run(id);
    return reply.code(204).send();
  });
}
