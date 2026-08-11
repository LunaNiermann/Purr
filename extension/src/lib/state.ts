/**
 * Persistent extension state in chrome.storage.local. The extension holds a
 * pairing and per-domain display metadata — never a TOTP secret. Session keys
 * are key material, so they live here only because MV3 has no better local
 * store; they can release nothing without the phone answering a request.
 */

export interface Pairing {
  pairingId: string;
  extToken: string;
  extPrivB64: string;
  extPubB64: string;
  phonePubB64: string;
  sessionKeyB64: string;
  phoneName: string;
  pairedAt: number;
  lastUsedAt: number | null;
}

export interface DomainMatch {
  site: string;
  username: string;
}

export interface Settings {
  autofill: boolean;
  preferKey: boolean;
  autoSubmit: boolean;
  siteRules: Record<string, "always-phone" | "never-autofill">;
}

export const defaultSettings: Settings = {
  autofill: true,
  preferKey: false,
  autoSubmit: true,
  siteRules: {},
};

export async function getPairing(): Promise<Pairing | null> {
  const { pairing } = await chrome.storage.local.get("pairing");
  return (pairing as Pairing | undefined) ?? null;
}

export async function setPairing(pairing: Pairing | null): Promise<void> {
  if (pairing === null) await chrome.storage.local.remove("pairing");
  else await chrome.storage.local.set({ pairing });
}

export async function getSettings(): Promise<Settings> {
  const { settings } = await chrome.storage.local.get("settings");
  return { ...defaultSettings, ...(settings as Partial<Settings> | undefined) };
}

export async function setSettings(settings: Settings): Promise<void> {
  await chrome.storage.local.set({ settings });
}

/** A registered "touch your key" security key. No secret material — the
 * credential id is a public handle; the replica key is only ever reconstructed
 * live from a touch, never stored. */
export interface SecurityKey {
  credentialIdB64: string;
  label: string;
  addedAt: number;
  /** True once a touch has actually produced PRF output — the only proof the
   * key can drive the route. Keys that can't (e.g. FIDO-only Titan) stay false
   * and are never used for unlock. */
  prfConfirmed: boolean;
  /** The replica master key K, wrapped for this key: seal(KEK, {k}). Present
   * once the key is enrolled into sign-in. Never the key itself. */
  wrappedKB64?: string;
}

/** The cached, encrypted vault replica pulled from the relay. Ciphertext under
 * the replica master key K — useless without a key touch. */
export interface ReplicaCache {
  replicaBlob: string;
  updatedAt: number;
}

export async function getSecurityKeys(): Promise<SecurityKey[]> {
  const { securityKeys } = await chrome.storage.local.get("securityKeys");
  return (securityKeys as SecurityKey[] | undefined) ?? [];
}

export async function addSecurityKey(key: SecurityKey): Promise<void> {
  const keys = await getSecurityKeys();
  // Replace on duplicate credential id (re-register), else append.
  const next = [
    ...keys.filter((k) => k.credentialIdB64 !== key.credentialIdB64),
    key,
  ];
  await chrome.storage.local.set({ securityKeys: next });
}

export async function removeSecurityKey(credentialIdB64: string): Promise<void> {
  const keys = await getSecurityKeys();
  await chrome.storage.local.set({
    securityKeys: keys.filter((k) => k.credentialIdB64 !== credentialIdB64),
  });
}

/** Mark a key as PRF-confirmed after a successful touch-test. */
export async function confirmSecurityKey(credentialIdB64: string): Promise<void> {
  const keys = await getSecurityKeys();
  await chrome.storage.local.set({
    securityKeys: keys.map((k) =>
      k.credentialIdB64 === credentialIdB64 ? { ...k, prfConfirmed: true } : k,
    ),
  });
}

/** Store (or clear) the wrapped master key for a security key. */
export async function setSecurityKeyWrap(
  credentialIdB64: string,
  wrappedKB64: string | undefined,
): Promise<void> {
  const keys = await getSecurityKeys();
  await chrome.storage.local.set({
    securityKeys: keys.map((k) =>
      k.credentialIdB64 === credentialIdB64 ? { ...k, wrappedKB64 } : k,
    ),
  });
}

export async function getReplicaCache(): Promise<ReplicaCache | null> {
  const { replicaCache } = await chrome.storage.local.get("replicaCache");
  return (replicaCache as ReplicaCache | undefined) ?? null;
}

export async function setReplicaCache(cache: ReplicaCache | null): Promise<void> {
  if (cache === null) await chrome.storage.local.remove("replicaCache");
  else await chrome.storage.local.set({ replicaCache: cache });
}

export async function getMatch(domain: string): Promise<DomainMatch | null> {
  const { matches } = await chrome.storage.local.get("matches");
  return ((matches as Record<string, DomainMatch> | undefined) ?? {})[domain] ?? null;
}

export async function rememberMatch(
  domain: string,
  match: DomainMatch,
): Promise<void> {
  const { matches } = await chrome.storage.local.get("matches");
  await chrome.storage.local.set({
    matches: { ...((matches as object | undefined) ?? {}), [domain]: match },
  });
}
