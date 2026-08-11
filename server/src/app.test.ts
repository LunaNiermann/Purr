import { afterEach, beforeEach, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { buildApp } from "./app.js";

let app: FastifyInstance;

beforeEach(async () => {
  app = await buildApp({ dbPath: ":memory:" });
});
afterEach(async () => {
  await app.close();
});

const EXT_PUB = Buffer.alloc(32, 1).toString("base64");
const PHONE_PUB = Buffer.alloc(32, 2).toString("base64");

async function pair() {
  const create = await app.inject({
    method: "POST",
    url: "/v1/pairings",
    payload: { extPub: EXT_PUB },
  });
  expect(create.statusCode).toBe(201);
  const { pairingId, extToken } = create.json();
  const complete = await app.inject({
    method: "POST",
    url: `/v1/pairings/${pairingId}/complete`,
    payload: { phonePub: PHONE_PUB, fcmToken: "fake-token" },
  });
  expect(complete.statusCode).toBe(200);
  const { phoneToken, extPub } = complete.json();
  expect(extPub).toBe(EXT_PUB);
  return { pairingId, extToken, phoneToken };
}

describe("pairing", () => {
  it("completes and reports state to both sides", async () => {
    const { pairingId, extToken, phoneToken } = await pair();
    for (const token of [extToken, phoneToken]) {
      const res = await app.inject({
        method: "GET",
        url: `/v1/pairings/${pairingId}`,
        headers: { authorization: `Bearer ${token}` },
      });
      expect(res.statusCode).toBe(200);
      expect(res.json().completed).toBe(true);
    }
  });

  it("rejects a second completion and bad tokens", async () => {
    const { pairingId } = await pair();
    const again = await app.inject({
      method: "POST",
      url: `/v1/pairings/${pairingId}/complete`,
      payload: { phonePub: PHONE_PUB },
    });
    expect(again.statusCode).toBe(404);
    const bad = await app.inject({
      method: "GET",
      url: `/v1/pairings/${pairingId}`,
      headers: { authorization: "Bearer wrong-token-wrong-token" },
    });
    expect(bad.statusCode).toBe(404);
  });

  it("unpairs from either side, even with an empty JSON body", async () => {
    const { pairingId, phoneToken } = await pair();
    // Mirror the real client: content-type json, no body.
    const del = await app.inject({
      method: "DELETE",
      url: `/v1/pairings/${pairingId}`,
      headers: {
        authorization: `Bearer ${phoneToken}`,
        "content-type": "application/json",
      },
    });
    expect(del.statusCode).toBe(204);
    const gone = await app.inject({
      method: "GET",
      url: `/v1/pairings/${pairingId}`,
      headers: { authorization: `Bearer ${phoneToken}` },
    });
    expect(gone.statusCode).toBe(404);
  });
});

describe("approval requests", () => {
  it("relays a request to the phone and the answer back, single-use", async () => {
    const { pairingId, extToken, phoneToken } = await pair();
    const reqBlob = Buffer.from("sealed-request").toString("base64");
    const created = await app.inject({
      method: "POST",
      url: "/v1/requests",
      headers: { authorization: `Bearer ${extToken}` },
      payload: { pairingId, requestBlob: reqBlob },
    });
    expect(created.statusCode).toBe(201);
    const { requestId } = created.json();

    const pending = await app.inject({
      method: "GET",
      url: `/v1/requests?pairingId=${pairingId}`,
      headers: { authorization: `Bearer ${phoneToken}` },
    });
    expect(pending.json().requests).toHaveLength(1);
    expect(pending.json().requests[0].requestBlob).toBe(reqBlob);

    const ansBlob = Buffer.from("sealed-answer").toString("base64");
    const answered = await app.inject({
      method: "POST",
      url: `/v1/requests/${requestId}/answer`,
      headers: { authorization: `Bearer ${phoneToken}` },
      payload: { answerBlob: ansBlob },
    });
    expect(answered.statusCode).toBe(204);

    const wait = await app.inject({
      method: "GET",
      url: `/v1/requests/${requestId}/wait`,
      headers: { authorization: `Bearer ${extToken}` },
    });
    expect(wait.json()).toMatchObject({ status: "answered", answerBlob: ansBlob });

    // single-use: second fetch finds nothing
    const again = await app.inject({
      method: "GET",
      url: `/v1/requests/${requestId}/wait`,
      headers: { authorization: `Bearer ${extToken}` },
    });
    expect(again.statusCode).toBe(404);
  });

  it("phone cannot create requests; ext cannot answer", async () => {
    const { pairingId, extToken, phoneToken } = await pair();
    const blob = Buffer.from("x").toString("base64");
    const byPhone = await app.inject({
      method: "POST",
      url: "/v1/requests",
      headers: { authorization: `Bearer ${phoneToken}` },
      payload: { pairingId, requestBlob: blob },
    });
    expect(byPhone.statusCode).toBe(404);

    const created = await app.inject({
      method: "POST",
      url: "/v1/requests",
      headers: { authorization: `Bearer ${extToken}` },
      payload: { pairingId, requestBlob: blob },
    });
    const byExt = await app.inject({
      method: "POST",
      url: `/v1/requests/${created.json().requestId}/answer`,
      headers: { authorization: `Bearer ${extToken}` },
      payload: { answerBlob: blob },
    });
    expect(byExt.statusCode).toBe(404);
  });

  it("a new request supersedes the previous pending one", async () => {
    const { pairingId, extToken, phoneToken } = await pair();
    const blob = Buffer.from("x").toString("base64");
    const first = await app.inject({
      method: "POST",
      url: "/v1/requests",
      headers: { authorization: `Bearer ${extToken}` },
      payload: { pairingId, requestBlob: blob },
    });
    await app.inject({
      method: "POST",
      url: "/v1/requests",
      headers: { authorization: `Bearer ${extToken}` },
      payload: { pairingId, requestBlob: blob },
    });
    const pending = await app.inject({
      method: "GET",
      url: `/v1/requests?pairingId=${pairingId}`,
      headers: { authorization: `Bearer ${phoneToken}` },
    });
    expect(pending.json().requests).toHaveLength(1);
    const staleAnswer = await app.inject({
      method: "POST",
      url: `/v1/requests/${first.json().requestId}/answer`,
      headers: { authorization: `Bearer ${phoneToken}` },
      payload: { answerBlob: blob },
    });
    expect(staleAnswer.statusCode).toBe(404);
  });
});

describe("backups", () => {
  const id = "a".repeat(22);
  const auth = "backup-auth-secret-abcdef";
  const blob = Buffer.from("ciphertext").toString("base64");

  it("stores, fetches, and deletes with proof of knowledge", async () => {
    const put = await app.inject({
      method: "PUT",
      url: `/v1/backups/${id}`,
      payload: { blob, digest: "d1", backupAuth: auth },
    });
    expect(put.statusCode).toBe(200);
    expect(put.json().size).toBe(10);

    const fetchRes = await app.inject({
      method: "POST",
      url: `/v1/backups/${id}/fetch`,
      payload: { backupAuth: auth },
    });
    expect(fetchRes.statusCode).toBe(200);
    expect(fetchRes.json().blob).toBe(blob);

    const del = await app.inject({
      method: "DELETE",
      url: `/v1/backups/${id}`,
      headers: { authorization: `Bearer ${auth}` },
    });
    expect(del.statusCode).toBe(204);
  });

  it("wrong auth and missing id are indistinguishable 404s", async () => {
    await app.inject({
      method: "PUT",
      url: `/v1/backups/${id}`,
      payload: { blob, digest: "d1", backupAuth: auth },
    });
    const wrongAuth = await app.inject({
      method: "POST",
      url: `/v1/backups/${id}/fetch`,
      payload: { backupAuth: "totally-wrong-secret-xx" },
    });
    const missing = await app.inject({
      method: "POST",
      url: `/v1/backups/${"b".repeat(22)}/fetch`,
      payload: { backupAuth: auth },
    });
    expect(wrongAuth.statusCode).toBe(404);
    expect(missing.statusCode).toBe(404);
    expect(wrongAuth.body).toBe(missing.body);
  });

  it("overwrite requires the original auth", async () => {
    await app.inject({
      method: "PUT",
      url: `/v1/backups/${id}`,
      payload: { blob, digest: "d1", backupAuth: auth },
    });
    const hijack = await app.inject({
      method: "PUT",
      url: `/v1/backups/${id}`,
      payload: { blob, digest: "d2", backupAuth: "attacker-supplied-secret" },
    });
    expect(hijack.statusCode).toBe(404);
  });
});

describe("vault replica (touch-your-key)", () => {
  const keyBlob = Buffer.from("sealed-master-key").toString("base64");
  const replicaBlob = Buffer.from("encrypted-vault-replica").toString("base64");

  it("syncs the key ext→phone and the replica phone→ext", async () => {
    const { pairingId, extToken, phoneToken } = await pair();

    // Ext publishes the sealed master key.
    const putKey = await app.inject({
      method: "PUT",
      url: `/v1/pairings/${pairingId}/replica-key`,
      headers: { authorization: `Bearer ${extToken}` },
      payload: { keyBlob },
    });
    expect(putKey.statusCode).toBe(204);

    // Phone reads it back.
    const getKey = await app.inject({
      method: "GET",
      url: `/v1/pairings/${pairingId}/replica-key`,
      headers: { authorization: `Bearer ${phoneToken}` },
    });
    expect(getKey.statusCode).toBe(200);
    expect(getKey.json().keyBlob).toBe(keyBlob);

    // Phone pushes the encrypted replica.
    const putReplica = await app.inject({
      method: "PUT",
      url: `/v1/pairings/${pairingId}/replica`,
      headers: { authorization: `Bearer ${phoneToken}` },
      payload: { replicaBlob },
    });
    expect(putReplica.statusCode).toBe(204);

    // Ext reads it.
    const getReplica = await app.inject({
      method: "GET",
      url: `/v1/pairings/${pairingId}/replica`,
      headers: { authorization: `Bearer ${extToken}` },
    });
    expect(getReplica.statusCode).toBe(200);
    expect(getReplica.json().replicaBlob).toBe(replicaBlob);
  });

  it("rejects a replica before a key is enrolled", async () => {
    const { pairingId, phoneToken } = await pair();
    const res = await app.inject({
      method: "PUT",
      url: `/v1/pairings/${pairingId}/replica`,
      headers: { authorization: `Bearer ${phoneToken}` },
      payload: { replicaBlob },
    });
    expect(res.statusCode).toBe(409);
  });

  it("a new key invalidates the stored replica", async () => {
    const { pairingId, extToken, phoneToken } = await pair();
    for (const p of [
      { url: `/v1/pairings/${pairingId}/replica-key`, token: extToken, body: { keyBlob } },
      { url: `/v1/pairings/${pairingId}/replica`, token: phoneToken, body: { replicaBlob } },
    ]) {
      await app.inject({
        method: "PUT",
        url: p.url,
        headers: { authorization: `Bearer ${p.token}` },
        payload: p.body,
      });
    }
    // Re-publish a new key.
    await app.inject({
      method: "PUT",
      url: `/v1/pairings/${pairingId}/replica-key`,
      headers: { authorization: `Bearer ${extToken}` },
      payload: { keyBlob: Buffer.from("new-key").toString("base64") },
    });
    // The stale replica is gone.
    const getReplica = await app.inject({
      method: "GET",
      url: `/v1/pairings/${pairingId}/replica`,
      headers: { authorization: `Bearer ${extToken}` },
    });
    expect(getReplica.statusCode).toBe(404);
  });

  it("enforces sides: phone can't publish a key, ext can't publish a replica", async () => {
    const { pairingId, extToken, phoneToken } = await pair();
    const phoneKey = await app.inject({
      method: "PUT",
      url: `/v1/pairings/${pairingId}/replica-key`,
      headers: { authorization: `Bearer ${phoneToken}` },
      payload: { keyBlob },
    });
    expect(phoneKey.statusCode).toBe(404);

    await app.inject({
      method: "PUT",
      url: `/v1/pairings/${pairingId}/replica-key`,
      headers: { authorization: `Bearer ${extToken}` },
      payload: { keyBlob },
    });
    const extReplica = await app.inject({
      method: "PUT",
      url: `/v1/pairings/${pairingId}/replica`,
      headers: { authorization: `Bearer ${extToken}` },
      payload: { replicaBlob },
    });
    expect(extReplica.statusCode).toBe(404);
  });
});
