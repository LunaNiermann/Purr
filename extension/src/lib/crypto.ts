import { xchacha20poly1305 } from "@noble/ciphers/chacha";
import { x25519 } from "@noble/curves/ed25519";
import { hkdf } from "@noble/hashes/hkdf";
import { sha256 } from "@noble/hashes/sha2";
import { randomBytes } from "@noble/hashes/utils";

/**
 * Pairing crypto, mirroring the phone's Dart side exactly
 * (app/lib/src/services/pairing_crypto.dart):
 *
 *   shared  = X25519(ourPriv, theirPub)
 *   session = HKDF-SHA256(ikm=shared, salt=pairingSecret, info="twokeys/pairing-v1")
 *   blob    = base64(nonce24 || XChaCha20-Poly1305(session, nonce24, plaintext))
 *
 * The pairing secret rides only inside the QR (out-of-band) — the relay
 * never sees it, so a malicious relay cannot MitM the pairing.
 */

export interface KeyPair {
  priv: Uint8Array;
  pub: Uint8Array;
}

export function generateKeyPair(): KeyPair {
  const priv = x25519.utils.randomPrivateKey();
  return { priv, pub: x25519.getPublicKey(priv) };
}

export function newPairingSecret(): Uint8Array {
  return randomBytes(16);
}

export function deriveSessionKey(
  ourPriv: Uint8Array,
  theirPub: Uint8Array,
  pairingSecret: Uint8Array,
): Uint8Array {
  const shared = x25519.getSharedSecret(ourPriv, theirPub);
  return hkdf(sha256, shared, pairingSecret, utf8("twokeys/pairing-v1"), 32);
}

export function seal(sessionKey: Uint8Array, plaintext: object): string {
  const nonce = randomBytes(24);
  const ct = xchacha20poly1305(sessionKey, nonce).encrypt(
    utf8(JSON.stringify(plaintext)),
  );
  const out = new Uint8Array(nonce.length + ct.length);
  out.set(nonce);
  out.set(ct, nonce.length);
  return toB64(out);
}

export function open<T>(sessionKey: Uint8Array, blobB64: string): T {
  const raw = fromB64(blobB64);
  const nonce = raw.slice(0, 24);
  const ct = raw.slice(24);
  const clear = xchacha20poly1305(sessionKey, nonce).decrypt(ct);
  return JSON.parse(new TextDecoder().decode(clear)) as T;
}

export function utf8(s: string): Uint8Array {
  return new TextEncoder().encode(s);
}

export function toB64(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

export function fromB64(s: string): Uint8Array {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function toB64Url(bytes: Uint8Array): string {
  return toB64(bytes).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}
