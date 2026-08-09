import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

export function newId(): string {
  return randomBytes(16).toString("base64url");
}

export function newToken(): string {
  return randomBytes(32).toString("base64url");
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("base64url");
}

/** Constant-time comparison of a presented token against a stored hash. */
export function tokenMatches(presented: string, storedHash: string): boolean {
  const a = createHash("sha256").update(presented, "utf8").digest();
  const b = Buffer.from(storedHash, "base64url");
  return a.length === b.length && timingSafeEqual(a, b);
}

export function bearer(header: string | undefined): string | null {
  if (!header?.startsWith("Bearer ")) return null;
  const token = header.slice(7).trim();
  return token.length >= 16 && token.length <= 128 ? token : null;
}

/** Base64 payload size guard: true if `s` is plausible base64 within maxBytes decoded. */
export function isB64Within(s: unknown, maxBytes: number): s is string {
  return (
    typeof s === "string" &&
    s.length <= Math.ceil(maxBytes / 3) * 4 + 4 &&
    /^[A-Za-z0-9+/_-]*={0,2}$/.test(s)
  );
}
