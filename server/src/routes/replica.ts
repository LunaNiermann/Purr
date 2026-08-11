import type { FastifyInstance } from "fastify";
import type { AppContext } from "../app.js";
import type { PairingRow, ReplicaRow } from "../db.js";
import { bearer, isB64Within, tokenMatches } from "../util.js";

// Vault replica sync for the "touch your key" desktop route.
//
//   PUT  /replica-key  (ext)   publish the sealed replica master key K
//   GET  /replica-key  (phone) read K to enroll the route
//   PUT  /replica      (phone) push the vault replica encrypted under K
//   GET  /replica      (ext)   read the replica to cache and decrypt at fill
//
// The server stores opaque ciphertext for both fields and enforces only auth
// and which side may read/write which. It can read neither the key nor the
// replica.
export function registerReplicaRoutes(
  app: FastifyInstance,
  ctx: AppContext,
): void {
  const { db } = ctx;
  const getPairing = db.prepare("SELECT * FROM pairings WHERE id = ?");
  const getReplica = db.prepare("SELECT * FROM replicas WHERE pairing_id = ?");

  function pairingFor(
    header: string | undefined,
    pairingId: string,
  ): { side: "ext" | "phone"; pairing: PairingRow } | null {
    const pairing = getPairing.get(pairingId) as PairingRow | undefined;
    if (!pairing?.completed_at) return null;
    const token = bearer(header);
    if (!token) return null;
    if (tokenMatches(token, pairing.ext_token_hash)) return { side: "ext", pairing };
    if (pairing.phone_token_hash && tokenMatches(token, pairing.phone_token_hash))
      return { side: "phone", pairing };
    return null;
  }

  const idOf = (req: { params: unknown }) => (req.params as { id: string }).id;

  // Ext → phone: publish the sealed replica master key at enrollment. A new key
  // invalidates any replica encrypted under the old one, so the replica is
  // cleared in the same write.
  app.put(
    "/v1/pairings/:id/replica-key",
    { config: { rateLimit: { max: 30, timeWindow: "1 minute" } } },
    async (req, reply) => {
      const id = idOf(req);
      const auth = pairingFor(req.headers.authorization, id);
      if (!auth || auth.side !== "ext")
        return reply.code(404).send({ error: "not found" });
      const { keyBlob } = (req.body ?? {}) as Record<string, unknown>;
      if (!isB64Within(keyBlob, 1024))
        return reply.code(400).send({ error: "bad keyBlob" });

      db.prepare(
        `INSERT INTO replicas (pairing_id, key_blob, key_updated_at, replica_blob, replica_updated_at)
         VALUES (?, ?, ?, NULL, NULL)
         ON CONFLICT(pairing_id) DO UPDATE SET
           key_blob = excluded.key_blob,
           key_updated_at = excluded.key_updated_at,
           replica_blob = NULL,
           replica_updated_at = NULL`,
      ).run(id, keyBlob, Date.now());
      ctx.waiters.notify(`replica-key:${id}`);
      return reply.code(204).send();
    },
  );

  // Phone reads the sealed master key to enroll (unseals it with the pairing
  // session key it already holds).
  app.get("/v1/pairings/:id/replica-key", async (req, reply) => {
    const id = idOf(req);
    const auth = pairingFor(req.headers.authorization, id);
    if (!auth || auth.side !== "phone")
      return reply.code(404).send({ error: "not found" });
    const row = getReplica.get(id) as ReplicaRow | undefined;
    if (!row?.key_blob) return reply.code(404).send({ error: "not found" });
    return reply.send({ keyBlob: row.key_blob, keyUpdatedAt: row.key_updated_at });
  });

  // Phone → ext: push the encrypted vault replica. Rejected until a key has
  // been enrolled, so a replica can never be orphaned without a key to open it.
  app.put(
    "/v1/pairings/:id/replica",
    { config: { rateLimit: { max: 60, timeWindow: "1 minute" } } },
    async (req, reply) => {
      const id = idOf(req);
      const auth = pairingFor(req.headers.authorization, id);
      if (!auth || auth.side !== "phone")
        return reply.code(404).send({ error: "not found" });
      const { replicaBlob } = (req.body ?? {}) as Record<string, unknown>;
      if (!isB64Within(replicaBlob, 300_000))
        return reply.code(400).send({ error: "bad replicaBlob" });
      const row = getReplica.get(id) as ReplicaRow | undefined;
      if (!row?.key_blob)
        return reply.code(409).send({ error: "no replica key enrolled" });

      db.prepare(
        "UPDATE replicas SET replica_blob = ?, replica_updated_at = ? WHERE pairing_id = ?",
      ).run(replicaBlob, Date.now(), id);
      ctx.waiters.notify(`replica:${id}`);
      return reply.code(204).send();
    },
  );

  // Ext reads the replica to cache locally.
  app.get("/v1/pairings/:id/replica", async (req, reply) => {
    const id = idOf(req);
    const auth = pairingFor(req.headers.authorization, id);
    if (!auth || auth.side !== "ext")
      return reply.code(404).send({ error: "not found" });
    const row = getReplica.get(id) as ReplicaRow | undefined;
    if (!row?.replica_blob) return reply.code(404).send({ error: "not found" });
    return reply.send({
      replicaBlob: row.replica_blob,
      replicaUpdatedAt: row.replica_updated_at,
    });
  });
}
