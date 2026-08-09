import type { FastifyInstance } from "fastify";
import type { AppContext } from "../app.js";
import type { PairingRow } from "../db.js";
import { bearer, hashToken, isB64Within, newId, newToken, tokenMatches } from "../util.js";

/**
 * Pairing: the extension opens a pairing and renders its half of the QR
 * (relay url, pairing id, its X25519 public key, and a pairing secret that
 * NEVER touches this server — it rides only in the QR). The phone joins by
 * depositing its public key. Key agreement and MitM protection happen
 * entirely client-side; this server just matchmakes and stores routing data.
 */
export function registerPairingRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { db, waiters } = ctx;

  const getPairing = db.prepare("SELECT * FROM pairings WHERE id = ?");

  function authed(pairing: PairingRow | undefined, header: string | undefined):
    | { side: "ext" | "phone"; pairing: PairingRow }
    | null {
    if (!pairing) return null;
    const token = bearer(header);
    if (!token) return null;
    if (tokenMatches(token, pairing.ext_token_hash)) return { side: "ext", pairing };
    if (pairing.phone_token_hash && tokenMatches(token, pairing.phone_token_hash))
      return { side: "phone", pairing };
    return null;
  }

  app.post("/v1/pairings", async (req, reply) => {
    const { extPub, extNameBlob } = (req.body ?? {}) as Record<string, unknown>;
    if (!isB64Within(extPub, 64) || extPub.length < 32)
      return reply.code(400).send({ error: "bad extPub" });
    if (extNameBlob !== undefined && !isB64Within(extNameBlob, 512))
      return reply.code(400).send({ error: "bad extNameBlob" });

    const id = newId();
    const extToken = newToken();
    db.prepare(
      `INSERT INTO pairings (id, ext_pub, ext_token_hash, ext_name_blob, created_at)
       VALUES (?, ?, ?, ?, ?)`,
    ).run(id, extPub, hashToken(extToken), extNameBlob ?? null, Date.now());
    return reply.code(201).send({ pairingId: id, extToken });
  });

  // Phone joins. No bearer yet — possession of the pairing id (fresh, random,
  // 10-minute TTL, from the QR) is the credential for this single call.
  app.post("/v1/pairings/:id/complete", async (req, reply) => {
    const pairing = getPairing.get((req.params as { id: string }).id) as
      | PairingRow
      | undefined;
    if (!pairing || pairing.completed_at)
      return reply.code(404).send({ error: "not found" });

    const { phonePub, phoneNameBlob, fcmToken } = (req.body ?? {}) as Record<
      string,
      unknown
    >;
    if (!isB64Within(phonePub, 64) || phonePub.length < 32)
      return reply.code(400).send({ error: "bad phonePub" });
    if (phoneNameBlob !== undefined && !isB64Within(phoneNameBlob, 512))
      return reply.code(400).send({ error: "bad phoneNameBlob" });
    if (fcmToken !== undefined && typeof fcmToken !== "string")
      return reply.code(400).send({ error: "bad fcmToken" });

    const phoneToken = newToken();
    db.prepare(
      `UPDATE pairings SET phone_pub = ?, phone_token_hash = ?, phone_name_blob = ?,
       fcm_token = ?, completed_at = ? WHERE id = ?`,
    ).run(
      phonePub,
      hashToken(phoneToken),
      phoneNameBlob ?? null,
      typeof fcmToken === "string" ? fcmToken : null,
      Date.now(),
      pairing.id,
    );
    waiters.notify(`pairing:${pairing.id}`);
    return reply.send({ phoneToken, extPub: pairing.ext_pub });
  });

  // Extension long-polls until the phone joins.
  app.get("/v1/pairings/:id/wait", async (req, reply) => {
    const pairing = getPairing.get((req.params as { id: string }).id) as
      | PairingRow
      | undefined;
    const auth = authed(pairing, req.headers.authorization);
    if (!auth) return reply.code(404).send({ error: "not found" });

    let row = auth.pairing;
    if (!row.completed_at) {
      await waiters.wait(`pairing:${row.id}`, 25_000);
      row = getPairing.get(row.id) as PairingRow;
    }
    if (!row.completed_at) return reply.send({ completed: false });
    return reply.send({
      completed: true,
      phonePub: row.phone_pub,
      phoneNameBlob: row.phone_name_blob,
    });
  });

  app.get("/v1/pairings/:id", async (req, reply) => {
    const pairing = getPairing.get((req.params as { id: string }).id) as
      | PairingRow
      | undefined;
    const auth = authed(pairing, req.headers.authorization);
    if (!auth) return reply.code(404).send({ error: "not found" });
    const p = auth.pairing;
    return reply.send({
      pairingId: p.id,
      completed: !!p.completed_at,
      extPub: p.ext_pub,
      phonePub: p.phone_pub,
      extNameBlob: p.ext_name_blob,
      phoneNameBlob: p.phone_name_blob,
      createdAt: p.created_at,
      lastUsedAt: p.last_used_at,
    });
  });

  // Either side can unpair ("Unpairing only affects this browser. Your codes
  // stay on your phone, untouched.")
  app.delete("/v1/pairings/:id", async (req, reply) => {
    const pairing = getPairing.get((req.params as { id: string }).id) as
      | PairingRow
      | undefined;
    const auth = authed(pairing, req.headers.authorization);
    if (!auth) return reply.code(404).send({ error: "not found" });
    db.prepare("DELETE FROM pairings WHERE id = ?").run(auth.pairing.id);
    return reply.code(204).send();
  });

  // Phone registers/rotates its FCM token.
  app.put("/v1/pairings/:id/fcm-token", async (req, reply) => {
    const pairing = getPairing.get((req.params as { id: string }).id) as
      | PairingRow
      | undefined;
    const auth = authed(pairing, req.headers.authorization);
    if (!auth || auth.side !== "phone")
      return reply.code(404).send({ error: "not found" });
    const { fcmToken } = (req.body ?? {}) as Record<string, unknown>;
    if (typeof fcmToken !== "string" || fcmToken.length > 4096)
      return reply.code(400).send({ error: "bad fcmToken" });
    db.prepare("UPDATE pairings SET fcm_token = ? WHERE id = ?").run(
      fcmToken,
      auth.pairing.id,
    );
    return reply.code(204).send();
  });
}
