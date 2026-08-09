// Generates cross-language test vectors for the pairing crypto.
// Output consumed by app/test/pairing_interop_test.dart — if either side
// drifts from the shared construction, that test fails.
import { xchacha20poly1305 } from "@noble/ciphers/chacha";
import { x25519 } from "@noble/curves/ed25519";
import { hkdf } from "@noble/hashes/hkdf";
import { sha256 } from "@noble/hashes/sha2";
import { writeFileSync } from "node:fs";

const te = new TextEncoder();
const b64 = (u8) => Buffer.from(u8).toString("base64");

// Fixed keys: deterministic vectors.
const extPriv = Uint8Array.from({ length: 32 }, (_, i) => i + 1);
const phonePriv = Uint8Array.from({ length: 32 }, (_, i) => 101 + i);
const secret = Uint8Array.from({ length: 16 }, (_, i) => 201 + i);

const extPub = x25519.getPublicKey(extPriv);
const phonePub = x25519.getPublicKey(phonePriv);
const shared = x25519.getSharedSecret(extPriv, phonePub);
const session = hkdf(sha256, shared, secret, te.encode("twokeys/pairing-v1"), 32);

const nonce = Uint8Array.from({ length: 24 }, (_, i) => 51 + i);
const payload = { kind: "code", domain: "github.com", browser: "Chrome · Windows", ts: 1754745600000 };
const ct = xchacha20poly1305(session, nonce).encrypt(te.encode(JSON.stringify(payload)));
const blob = new Uint8Array(nonce.length + ct.length);
blob.set(nonce);
blob.set(ct, nonce.length);

writeFileSync(
  "../app/test/fixtures/pairing_vectors.json",
  JSON.stringify(
    {
      extPriv: b64(extPriv),
      extPub: b64(extPub),
      phonePriv: b64(phonePriv),
      phonePub: b64(phonePub),
      pairingSecret: b64(secret),
      sessionKey: b64(session),
      sealedBlob: b64(blob),
      payload,
    },
    null,
    2,
  ),
);
console.log("vectors written");
