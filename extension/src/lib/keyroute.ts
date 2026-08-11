import { fromB64, open, seal, toB64 } from "./crypto";
import { getReplica, putReplicaKey } from "./relay";
import {
  getPairing,
  getReplicaCache,
  getSecurityKeys,
  setReplicaCache,
  setSecurityKeyWrap,
} from "./state";
import { base32Decode, totp, type TotpAlgorithm } from "./totp";
import { deriveKek } from "./webauthn";

/**
 * The "touch your key" route, extension side.
 *
 * A random 32-byte master key **K** encrypts the vault replica (the phone does
 * that, under K). K is wrapped per security key as `seal(KEK, {k})`, where
 * `KEK = HKDF(that key's PRF output)`. K is never stored on the desktop — only
 * the wraps are; a touch reconstructs the KEK, which unwraps K just long enough
 * to decrypt one entry. Any enrolled key can unlock (multi-key safeguard).
 */

function wrapK(kek: Uint8Array, k: Uint8Array): string {
  return seal(kek, { k: toB64(k) });
}
function unwrapK(kek: Uint8Array, wrapped: string): Uint8Array {
  return fromB64(open<{ k: string }>(kek, wrapped).k);
}

export async function isEnrolled(): Promise<boolean> {
  return (await getSecurityKeys()).some((k) => k.prfConfirmed && k.wrappedKB64);
}

/** First-time enable: mint a fresh K, wrap it for the key touched now, and
 * publish K (sealed to the phone) so it starts encrypting the replica. */
export async function enrollFirstKey(): Promise<{ label: string }> {
  const pairing = await getPairing();
  if (!pairing) throw new Error("Pair a computer first.");
  const confirmed = (await getSecurityKeys()).filter((k) => k.prfConfirmed);
  if (confirmed.length === 0)
    throw new Error("Add and confirm a security key first.");
  if (confirmed.some((k) => k.wrappedKB64))
    throw new Error('Key sign-in is already on — use "Add to sign-in".');

  const { kek, credentialIdB64 } = await deriveKek(
    confirmed.map((c) => c.credentialIdB64),
  );
  const target = confirmed.find((c) => c.credentialIdB64 === credentialIdB64);
  if (!target) throw new Error("Touched a key that isn't registered here.");

  const k = crypto.getRandomValues(new Uint8Array(32));
  await setSecurityKeyWrap(target.credentialIdB64, wrapK(kek, k));
  const keyBlob = seal(fromB64(pairing.sessionKeyB64), { k: toB64(k) });
  await putReplicaKey(pairing.pairingId, pairing.extToken, keyBlob);
  return { label: target.label };
}

/** Add another key to sign-in: touch an enrolled key to recover K, then touch
 * the new key to wrap K for it (two touches). Your lose-a-key safeguard. */
export async function addTouchedKey(
  newCredentialIdB64: string,
): Promise<{ label: string }> {
  const keys = await getSecurityKeys();
  const enrolled = keys.filter((k) => k.prfConfirmed && k.wrappedKB64);
  if (enrolled.length === 0) throw new Error("Turn on key sign-in first.");

  const first = await deriveKek(enrolled.map((k) => k.credentialIdB64));
  const src = enrolled.find((k) => k.credentialIdB64 === first.credentialIdB64);
  if (!src?.wrappedKB64)
    throw new Error("Touch a key that's already in sign-in first.");
  const k = unwrapK(first.kek, src.wrappedKB64);

  const target = keys.find((k) => k.credentialIdB64 === newCredentialIdB64);
  if (!target?.prfConfirmed) throw new Error("Confirm the new key first.");
  const second = await deriveKek([newCredentialIdB64]);
  if (second.credentialIdB64 !== newCredentialIdB64)
    throw new Error("Touched the wrong key — touch the new one.");
  await setSecurityKeyWrap(newCredentialIdB64, wrapK(second.kek, k));
  return { label: target.label };
}

/** Turn the route off on this computer: drop every wrap and the cached
 * replica. The key material never leaves; nothing here can read it again. */
export async function disableKeyRoute(): Promise<void> {
  for (const k of await getSecurityKeys()) {
    if (k.wrappedKB64) await setSecurityKeyWrap(k.credentialIdB64, undefined);
  }
  await setReplicaCache(null);
}

/** One account as the extension needs it to compute a code. */
export interface ReplicaAccount {
  site: string;
  user: string;
  secret: string;
  digits: number;
  period: number;
  algorithm: TotpAlgorithm;
  type: string;
  counter?: number;
}

/** Pull the latest replica ciphertext from the relay into the local cache. */
export async function refreshReplica(): Promise<boolean> {
  const pairing = await getPairing();
  if (!pairing) return false;
  const r = await getReplica(pairing.pairingId, pairing.extToken);
  if (!r) return false;
  await setReplicaCache({ replicaBlob: r.replicaBlob, updatedAt: r.replicaUpdatedAt });
  return true;
}

/** Touch a key and decrypt the cached replica → accounts. The unlock. */
export async function unlockReplica(): Promise<ReplicaAccount[]> {
  const enrolled = (await getSecurityKeys()).filter(
    (k) => k.prfConfirmed && k.wrappedKB64,
  );
  if (enrolled.length === 0) throw new Error("Key sign-in isn't set up.");

  let cache = await getReplicaCache();
  if (!cache) {
    await refreshReplica();
    cache = await getReplicaCache();
  }
  if (!cache)
    throw new Error("No vault yet — open the phone app once so it can sync.");

  const { kek, credentialIdB64 } = await deriveKek(
    enrolled.map((k) => k.credentialIdB64),
  );
  const src = enrolled.find((k) => k.credentialIdB64 === credentialIdB64);
  if (!src?.wrappedKB64)
    throw new Error("That key isn't in sign-in — touch an enrolled one.");
  const k = unwrapK(kek, src.wrappedKB64);
  const payload = open<{ v: number; accounts: ReplicaAccount[] }>(
    k,
    cache.replicaBlob,
  );
  return payload.accounts ?? [];
}

/** Match an account to a domain, mirroring the phone's forgiving matcher. */
export function matchAccount(
  accounts: ReplicaAccount[],
  domain: string,
): ReplicaAccount | null {
  const norm = (s: string) => s.toLowerCase().replace(/[^a-z0-9]/g, "");
  const parts = domain.split(".");
  const base = norm(parts.length > 1 ? parts[parts.length - 2]! : domain);
  for (const a of accounts) {
    const site = norm(a.site);
    if (site && (site === base || base.includes(site) || site.includes(base)))
      return a;
  }
  return null;
}

/** Current code for a matched account. */
export function codeFor(a: ReplicaAccount, nowMs = Date.now()): string {
  return totp({
    secret: base32Decode(a.secret),
    timeMs: nowMs,
    period: a.period,
    digits: a.digits,
    algorithm: a.algorithm,
  });
}
