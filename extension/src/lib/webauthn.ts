import { hkdf } from "@noble/hashes/hkdf";
import { sha256 } from "@noble/hashes/sha2";

import { fromB64, toB64 } from "./crypto";

/**
 * "Touch your key" — the WebAuthn PRF (hmac-secret) layer.
 *
 * A registered FIDO2 key, touched, returns a stable per-credential secret for a
 * fixed salt. That secret feeds HKDF to reconstruct the *replica key* that
 * decrypts the on-device encrypted vault replica. The replica key is never
 * stored on the desktop — it only exists for the instant between a touch and a
 * single-entry decrypt.
 *
 * Mirrors nothing on the phone directly: the phone only ever receives the
 * derived replica key (over the E2EE pairing channel) so it can encrypt the
 * replica. The PRF salt and HKDF info below are the shared, non-secret contract.
 */

// Fixed PRF input. Not a secret; it just has to be identical every time so the
// same key yields the same output. 32 bytes of a domain-separated constant.
const PRF_SALT: Uint8Array = sha256(
  new TextEncoder().encode("purr/replica/prf/v1"),
);
const REPLICA_KEY_INFO = new TextEncoder().encode("purr/replica-key/v1");

// UV pinned to "discouraged": the experience is a *touch*, not a PIN, and
// hmac-secret returns a different secret with vs. without user verification, so
// the setting must be identical at register and at unlock. If a key mandates
// UV this surfaces as a registration error rather than a silent key mismatch.
const USER_VERIFICATION: UserVerificationRequirement = "discouraged";
const RP_NAME = "Purr";
const TIMEOUT_MS = 60_000;

// On an extension page, location.hostname is the extension id — a valid RP id
// for WebAuthn ceremonies scoped to the extension origin.
function rpId(): string {
  return location.hostname;
}

function randomBytes(n: number): Uint8Array {
  return crypto.getRandomValues(new Uint8Array(n));
}

// WebAuthn's BufferSource fields want an ArrayBuffer-backed view; noble and our
// base64 helpers hand back Uint8Array<ArrayBufferLike>, which TS 5.7 rejects.
// Copy into a fresh, definitely-ArrayBuffer-backed buffer.
function ab(u8: Uint8Array): ArrayBuffer {
  const out = new Uint8Array(u8.length);
  out.set(u8);
  return out.buffer;
}

function replicaKeyFromPrf(prfOutput: Uint8Array): Uint8Array {
  return hkdf(sha256, prfOutput, undefined, REPLICA_KEY_INFO, 32);
}

// Chrome exposes PRF results under getClientExtensionResults().prf; type defs
// lag the spec, so we read it through a narrow shape.
interface PrfExtensionResults {
  prf?: { enabled?: boolean; results?: { first?: ArrayBuffer } };
}

export interface RegisterResult {
  credentialIdB64: string;
  /** The authenticator advertised hmac-secret/PRF support. */
  prfSupported: boolean;
}

/** True when the browser exposes the WebAuthn API at all. */
export function webauthnAvailable(): boolean {
  return (
    typeof PublicKeyCredential !== "undefined" &&
    typeof navigator.credentials?.create === "function"
  );
}

/**
 * Register a security key with PRF enabled. One touch. Reports whether the key
 * actually supports PRF — the make-or-break capability for this route.
 */
export async function registerKey(label: string): Promise<RegisterResult> {
  const cred = (await navigator.credentials.create({
    publicKey: {
      rp: { id: rpId(), name: RP_NAME },
      user: {
        id: ab(randomBytes(16)),
        name: label || "Purr key",
        displayName: label || "Purr key",
      },
      challenge: ab(randomBytes(32)),
      pubKeyCredParams: [
        { type: "public-key", alg: -7 }, // ES256
        { type: "public-key", alg: -257 }, // RS256
      ],
      authenticatorSelection: {
        authenticatorAttachment: "cross-platform",
        residentKey: "discouraged",
        userVerification: USER_VERIFICATION,
      },
      timeout: TIMEOUT_MS,
      attestation: "none",
      extensions: {
        prf: { eval: { first: ab(PRF_SALT) } },
      } as AuthenticationExtensionsClientInputs,
    },
  })) as PublicKeyCredential | null;
  if (!cred) throw new Error("Registration was cancelled.");

  const ext = cred.getClientExtensionResults() as PrfExtensionResults;
  const prfSupported = ext.prf?.enabled === true || !!ext.prf?.results?.first;
  return {
    credentialIdB64: toB64(new Uint8Array(cred.rawId)),
    prfSupported,
  };
}

/**
 * Touch a registered key and reconstruct the replica key from its PRF output.
 * Accepts every registered credential id so any of the user's keys can unlock.
 * Throws if PRF output is absent (key/browser can't do it).
 */
export async function deriveReplicaKey(
  credentialIdsB64: string[],
): Promise<{ replicaKey: Uint8Array; credentialIdB64: string }> {
  const assertion = (await navigator.credentials.get({
    publicKey: {
      rpId: rpId(),
      challenge: ab(randomBytes(32)),
      allowCredentials: credentialIdsB64.map((id) => ({
        type: "public-key" as const,
        id: ab(fromB64(id)),
        transports: ["usb", "nfc", "ble", "internal"] as AuthenticatorTransport[],
      })),
      userVerification: USER_VERIFICATION,
      timeout: TIMEOUT_MS,
      extensions: {
        prf: { eval: { first: ab(PRF_SALT) } },
      } as AuthenticationExtensionsClientInputs,
    },
  })) as PublicKeyCredential | null;
  if (!assertion) throw new Error("No key responded.");

  const ext = assertion.getClientExtensionResults() as PrfExtensionResults;
  const first = ext.prf?.results?.first;
  if (!first) {
    throw new Error(
      "This key returned no PRF output — it doesn't support PRF/hmac-secret.",
    );
  }
  return {
    replicaKey: replicaKeyFromPrf(new Uint8Array(first)),
    credentialIdB64: toB64(new Uint8Array(assertion.rawId)),
  };
}
