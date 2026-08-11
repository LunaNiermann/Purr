import { describe, expect, it } from "vitest";

import { base32Decode, hotp, totp, type TotpAlgorithm } from "./totp";

const te = new TextEncoder();

describe("base32Decode", () => {
  it("decodes RFC 4648 vectors and tolerates lowercase/padding/spaces", () => {
    expect(new TextDecoder().decode(base32Decode("MZXW6==="))).toBe("foo");
    expect(new TextDecoder().decode(base32Decode("mz xw 6"))).toBe("foo");
    // The RFC 6238 SHA-1 seed "12345678901234567890".
    expect(new TextDecoder().decode(base32Decode("GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"))).toBe(
      "12345678901234567890",
    );
  });
});

describe("hotp", () => {
  // RFC 4226 Appendix D — secret "12345678901234567890", 6 digits.
  const secret = te.encode("12345678901234567890");
  const expected = [
    "755224", "287082", "359152", "969429", "338314",
    "254676", "287922", "162583", "399871", "520489",
  ];
  it("matches the RFC 4226 vectors", () => {
    expected.forEach((code, counter) => {
      expect(hotp(secret, counter, 6, "sha1")).toBe(code);
    });
  });
});

describe("totp", () => {
  // RFC 6238 Appendix B — 8 digits. SHA-1 seed is 20 bytes, SHA-256 32, SHA-512 64.
  const seed = (algo: TotpAlgorithm) => {
    const base = "1234567890";
    const lens = { sha1: 20, sha256: 32, sha512: 64 } as const;
    let s = "";
    while (s.length < lens[algo]) s += base;
    return te.encode(s.slice(0, lens[algo]));
  };
  const cases: Array<[number, TotpAlgorithm, string]> = [
    [59, "sha1", "94287082"],
    [59, "sha256", "46119246"],
    [59, "sha512", "90693936"],
    [1111111109, "sha1", "07081804"],
    [1234567890, "sha1", "89005924"],
    [2000000000, "sha1", "69279037"],
  ];
  it("matches the RFC 6238 vectors across algorithms", () => {
    for (const [t, algo, code] of cases) {
      expect(
        totp({ secret: seed(algo), timeMs: t * 1000, period: 30, digits: 8, algorithm: algo }),
      ).toBe(code);
    }
  });
});
