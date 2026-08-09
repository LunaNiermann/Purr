import type { FastifyInstance } from "fastify";
import type { AppContext } from "../app.js";
import type { PairingRow, RequestRow } from "../db.js";
import { bearer, isB64Within, newId, tokenMatches } from "../util.js";

const REQUEST_TTL_MS = 60_000; // design contract: requests expire after a minute

/**
 * Approval requests. The blob is sealed by the extension for the phone
 * (domain, browser, timestamp inside); the answer blob is sealed by the
 * phone for the extension (the six digits, or a denial verdict). This
 * server can read neither — it enforces only lifecycle: 60 s TTL,
 * single pending request per pairing, answer-once.
 */
export function registerRequestRoutes(app: FastifyInstance, ctx: AppContext): void {
  const { db, waiters, pusher } = ctx;

  const getPairing = db.prepare("SELECT * FROM pairings WHERE id = ?");
  const getRequest = db.prepare("SELECT * FROM requests WHERE id = ?");

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

  app.post("/v1/requests", {
    config: { rateLimit: { max: 10, timeWindow: "1 minute" } },
  }, async (req, reply) => {
    const { pairingId, requestBlob } = (req.body ?? {}) as Record<string, unknown>;
    if (typeof pairingId !== "string")
      return reply.code(400).send({ error: "bad pairingId" });
    const auth = pairingFor(req.headers.authorization, pairingId);
    if (!auth || auth.side !== "ext")
      return reply.code(404).send({ error: "not found" });
    if (!isB64Within(requestBlob, 4096))
      return reply.code(400).send({ error: "bad requestBlob" });

    const now = Date.now();
    // One live request per pairing: a new ask supersedes the old one, so a
    // stale prompt on the phone can never release a code for a dead request.
    db.prepare(
      "DELETE FROM requests WHERE pairing_id = ? AND status = 'pending'",
    ).run(pairingId);

    const id = newId();
    db.prepare(
      `INSERT INTO requests (id, pairing_id, request_blob, created_at, expires_at)
       VALUES (?, ?, ?, ?, ?)`,
    ).run(id, pairingId, requestBlob, now, now + REQUEST_TTL_MS);
    db.prepare("UPDATE pairings SET last_used_at = ? WHERE id = ?").run(now, pairingId);

    let pushed = false;
    if (auth.pairing.fcm_token) {
      // Payload is routing data only — FCM must never see request content.
      pushed = await pusher.send(auth.pairing.fcm_token, {
        type: "approval_request",
        requestId: id,
        pairingId,
      });
    }
    // Diagnostic: makes it obvious in the logs whether the phone registered a
    // push token and whether a push was actually sent.
    req.log.info(
      {
        pairingId,
        hasFcmToken: !!auth.pairing.fcm_token,
        pushConfigured: pusher.configured,
        pushed,
      },
      "approval request created",
    );
    waiters.notify(`pending:${pairingId}`);
    return reply.code(201).send({ requestId: id, expiresAt: now + REQUEST_TTL_MS, pushed });
  });

  // Phone: list pending (poll-on-open fallback for dropped pushes).
  app.get("/v1/requests", async (req, reply) => {
    const pairingId = (req.query as Record<string, unknown>).pairingId;
    if (typeof pairingId !== "string")
      return reply.code(400).send({ error: "bad pairingId" });
    const auth = pairingFor(req.headers.authorization, pairingId);
    if (!auth || auth.side !== "phone")
      return reply.code(404).send({ error: "not found" });
    const rows = db
      .prepare(
        `SELECT id, request_blob, created_at, expires_at FROM requests
         WHERE pairing_id = ? AND status = 'pending' AND expires_at > ?
         ORDER BY created_at DESC`,
      )
      .all(pairingId, Date.now()) as Pick<
      RequestRow,
      "id" | "request_blob" | "created_at" | "expires_at"
    >[];
    return reply.send({
      requests: rows.map((r) => ({
        requestId: r.id,
        requestBlob: r.request_blob,
        createdAt: r.created_at,
        expiresAt: r.expires_at,
      })),
    });
  });

  app.get("/v1/requests/:id", async (req, reply) => {
    const row = getRequest.get((req.params as { id: string }).id) as
      | RequestRow
      | undefined;
    if (!row) return reply.code(404).send({ error: "not found" });
    const auth = pairingFor(req.headers.authorization, row.pairing_id);
    if (!auth) return reply.code(404).send({ error: "not found" });
    if (row.expires_at < Date.now())
      return reply.code(410).send({ error: "expired" });
    return reply.send({
      requestId: row.id,
      requestBlob: row.request_blob,
      status: row.status,
      createdAt: row.created_at,
      expiresAt: row.expires_at,
    });
  });

  // Phone answers exactly once. The verdict (approved-with-code vs denied)
  // lives inside the sealed blob; the server only knows "answered".
  app.post("/v1/requests/:id/answer", async (req, reply) => {
    const row = getRequest.get((req.params as { id: string }).id) as
      | RequestRow
      | undefined;
    if (!row) return reply.code(404).send({ error: "not found" });
    const auth = pairingFor(req.headers.authorization, row.pairing_id);
    if (!auth || auth.side !== "phone")
      return reply.code(404).send({ error: "not found" });
    if (row.status !== "pending") return reply.code(409).send({ error: "answered" });
    if (row.expires_at < Date.now())
      return reply.code(410).send({ error: "expired" });

    const { answerBlob } = (req.body ?? {}) as Record<string, unknown>;
    if (!isB64Within(answerBlob, 4096))
      return reply.code(400).send({ error: "bad answerBlob" });

    db.prepare(
      "UPDATE requests SET answer_blob = ?, status = 'answered', answered_at = ? WHERE id = ? AND status = 'pending'",
    ).run(answerBlob, Date.now(), row.id);
    waiters.notify(`answer:${row.id}`);
    return reply.code(204).send();
  });

  // Extension long-polls for the answer. Single-use: the answer is deleted
  // on first delivery — a relayed code can never be fetched twice.
  app.get("/v1/requests/:id/wait", async (req, reply) => {
    const id = (req.params as { id: string }).id;
    let row = getRequest.get(id) as RequestRow | undefined;
    if (!row) return reply.code(404).send({ error: "not found" });
    const auth = pairingFor(req.headers.authorization, row.pairing_id);
    if (!auth || auth.side !== "ext")
      return reply.code(404).send({ error: "not found" });

    if (row.status === "pending") {
      const remaining = row.expires_at - Date.now();
      if (remaining > 0) {
        await waiters.wait(`answer:${id}`, Math.min(remaining, 25_000));
        row = getRequest.get(id) as RequestRow | undefined;
      }
    }
    if (!row) return reply.code(404).send({ error: "not found" });
    if (row.status === "answered") {
      db.prepare("DELETE FROM requests WHERE id = ?").run(id);
      return reply.send({ status: "answered", answerBlob: row.answer_blob });
    }
    if (row.expires_at < Date.now()) {
      db.prepare("DELETE FROM requests WHERE id = ?").run(id);
      return reply.send({ status: "expired" });
    }
    return reply.send({ status: "pending", expiresAt: row.expires_at });
  });

  // Phone long-polls for new pending requests while the app is open
  // (foreground path that needs no FCM at all — "works on a plane" honesty).
  app.get("/v1/requests/wait-pending", async (req, reply) => {
    const pairingId = (req.query as Record<string, unknown>).pairingId;
    if (typeof pairingId !== "string")
      return reply.code(400).send({ error: "bad pairingId" });
    const auth = pairingFor(req.headers.authorization, pairingId);
    if (!auth || auth.side !== "phone")
      return reply.code(404).send({ error: "not found" });

    const pending = () =>
      db
        .prepare(
          `SELECT id, request_blob, created_at, expires_at FROM requests
           WHERE pairing_id = ? AND status = 'pending' AND expires_at > ?`,
        )
        .all(pairingId, Date.now()) as Pick<
        RequestRow,
        "id" | "request_blob" | "created_at" | "expires_at"
      >[];

    let rows = pending();
    if (rows.length === 0) {
      await waiters.wait(`pending:${pairingId}`, 25_000);
      rows = pending();
    }
    return reply.send({
      requests: rows.map((r) => ({
        requestId: r.id,
        requestBlob: r.request_blob,
        createdAt: r.created_at,
        expiresAt: r.expires_at,
      })),
    });
  });
}
