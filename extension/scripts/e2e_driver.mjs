// End-to-end driver: plays the extension's role against a relay, printing
// the pairing payload for the phone and then requesting a code.
//
//   node scripts/e2e_driver.mjs pair    --relay http://127.0.0.1:3000 --phone-relay http://10.0.2.2:3000
//   node scripts/e2e_driver.mjs request --relay http://127.0.0.1:3000 --domain github.com
//
// State persists in .e2e-state.json (throwaway, gitignored).
import { xchacha20poly1305 } from "@noble/ciphers/chacha";
import { x25519 } from "@noble/curves/ed25519";
import { hkdf } from "@noble/hashes/hkdf";
import { sha256 } from "@noble/hashes/sha2";
import { randomBytes } from "@noble/hashes/utils";
import { readFileSync, writeFileSync } from "node:fs";

const args = process.argv.slice(2);
const mode = args[0];
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : fallback;
};
const relay = opt("relay", "http://127.0.0.1:3000");
const phoneRelay = opt("phone-relay", relay);
const STATE = new URL("../.e2e-state.json", import.meta.url);

const b64 = (u8) => Buffer.from(u8).toString("base64");
const unb64 = (s) => new Uint8Array(Buffer.from(s, "base64"));
const te = new TextEncoder();

const seal = (key, obj) => {
  const nonce = randomBytes(24);
  const ct = xchacha20poly1305(key, nonce).encrypt(te.encode(JSON.stringify(obj)));
  const out = new Uint8Array(nonce.length + ct.length);
  out.set(nonce);
  out.set(ct, nonce.length);
  return b64(out);
};
const open = (key, blob) => {
  const raw = unb64(blob);
  const clear = xchacha20poly1305(key, raw.slice(0, 24)).decrypt(raw.slice(24));
  return JSON.parse(Buffer.from(clear).toString("utf8"));
};

async function api(path, { method = "GET", body, bearer } = {}) {
  const res = await fetch(`${relay}${path}`, {
    method,
    headers: {
      "content-type": "application/json",
      ...(bearer ? { authorization: `Bearer ${bearer}` } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok && res.status !== 404 && res.status !== 410) {
    throw new Error(`${method} ${path} -> ${res.status}: ${await res.text()}`);
  }
  return res;
}

if (mode === "pair") {
  const priv = x25519.utils.randomPrivateKey();
  const pub = x25519.getPublicKey(priv);
  const secret = randomBytes(16);
  const created = await (
    await api("/v1/pairings", { method: "POST", body: { extPub: b64(pub) } })
  ).json();
  const qr = `purr-pair:${Buffer.from(
    JSON.stringify({
      v: 1,
      relay: phoneRelay,
      pairingId: created.pairingId,
      extPub: b64(pub),
      secret: b64(secret),
    }),
  ).toString("base64")}`;
  console.log("PAIRING PAYLOAD (give this to the phone):\n");
  console.log(qr + "\n");
  console.log("Waiting for the phone to join...");
  for (;;) {
    const wait = await (
      await api(`/v1/pairings/${created.pairingId}/wait`, {
        bearer: created.extToken,
      })
    ).json();
    if (!wait.completed) continue;
    const shared = x25519.getSharedSecret(priv, unb64(wait.phonePub));
    const session = hkdf(sha256, shared, secret, te.encode("twokeys/pairing-v1"), 32);
    let phoneName = "phone";
    if (wait.phoneNameBlob) phoneName = open(session, wait.phoneNameBlob).name;
    writeFileSync(
      STATE,
      JSON.stringify({
        pairingId: created.pairingId,
        extToken: created.extToken,
        sessionKey: b64(session),
      }),
    );
    console.log(`PAIRED with "${phoneName}". State saved.`);
    process.exit(0);
  }
}

if (mode === "request") {
  const state = JSON.parse(readFileSync(STATE, "utf8"));
  const session = unb64(state.sessionKey);
  const domain = opt("domain", "github.com");
  const blob = seal(session, {
    kind: "code",
    domain,
    browser: "Chrome · Windows",
    ts: Date.now(),
  });
  const created = await (
    await api("/v1/requests", {
      method: "POST",
      bearer: state.extToken,
      body: { pairingId: state.pairingId, requestBlob: blob },
    })
  ).json();
  console.log(`Request ${created.requestId} created (pushed=${created.pushed}). Waiting for the phone...`);
  for (;;) {
    const res = await api(`/v1/requests/${created.requestId}/wait`, {
      bearer: state.extToken,
    });
    if (res.status === 404) {
      console.log("GONE (already consumed or superseded)");
      process.exit(1);
    }
    const wait = await res.json();
    if (wait.status === "pending") continue;
    if (wait.status === "expired") {
      console.log("EXPIRED (60s passed — B6-expired popup would show)");
      process.exit(1);
    }
    const answer = open(session, wait.answerBlob);
    console.log("ANSWER:", JSON.stringify(answer));
    process.exit(0);
  }
}

console.log("usage: node scripts/e2e_driver.mjs pair|request [--relay URL] [--phone-relay URL] [--domain D]");
process.exit(1);
