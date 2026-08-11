import { hmac } from "@noble/hashes/hmac";
import { sha1 } from "@noble/hashes/sha1";
import { sha256, sha512 } from "@noble/hashes/sha2";

/**
 * RFC 4226 HOTP + RFC 6238 TOTP, mirroring the phone's Dart engine
 * (app/lib/src/core/totp.dart). Used by the "touch your key" route to compute
 * a code locally from the decrypted replica entry.
 */

export type TotpAlgorithm = "sha1" | "sha256" | "sha512";

const B32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

/** Tolerant base32 decode: uppercases, ignores padding, spaces, and stray
 * characters (matches the phone's forgiving parser). */
export function base32Decode(input: string): Uint8Array {
  let bits = 0;
  let value = 0;
  const out: number[] = [];
  for (const ch of input.toUpperCase()) {
    const idx = B32.indexOf(ch);
    if (idx === -1) continue;
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return new Uint8Array(out);
}

function hashFor(algo: TotpAlgorithm) {
  return algo === "sha256" ? sha256 : algo === "sha512" ? sha512 : sha1;
}

export function hotp(
  secret: Uint8Array,
  counter: number,
  digits = 6,
  algo: TotpAlgorithm = "sha1",
): string {
  const msg = new Uint8Array(8);
  const view = new DataView(msg.buffer);
  // 64-bit big-endian counter, split into two 32-bit halves (safe < 2^53).
  view.setUint32(0, Math.floor(counter / 0x1_0000_0000));
  view.setUint32(4, counter >>> 0);
  const digest = hmac(hashFor(algo), secret, msg);
  const offset = digest[digest.length - 1]! & 0x0f;
  const bin =
    ((digest[offset]! & 0x7f) << 24) |
    (digest[offset + 1]! << 16) |
    (digest[offset + 2]! << 8) |
    digest[offset + 3]!;
  return (bin % 10 ** digits).toString().padStart(digits, "0");
}

export interface TotpParams {
  secret: Uint8Array;
  timeMs?: number;
  period?: number;
  digits?: number;
  algorithm?: TotpAlgorithm;
}

export function totp({
  secret,
  timeMs = Date.now(),
  period = 30,
  digits = 6,
  algorithm = "sha1",
}: TotpParams): string {
  const counter = Math.floor(timeMs / 1000 / period);
  return hotp(secret, counter, digits, algorithm);
}
