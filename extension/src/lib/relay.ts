/** Relay client (extension side). Sends and receives ciphertext only. */

export const RELAY_URL = "https://2fa.apps.not-final.com";

async function req(
  path: string,
  init: RequestInit & { bearer?: string } = {},
): Promise<Response> {
  const headers: Record<string, string> = {
    "content-type": "application/json",
  };
  if (init.bearer) headers.authorization = `Bearer ${init.bearer}`;
  return fetch(`${RELAY_URL}${path}`, { ...init, headers });
}

export async function createPairing(
  extPubB64: string,
): Promise<{ pairingId: string; extToken: string }> {
  const res = await req("/v1/pairings", {
    method: "POST",
    body: JSON.stringify({ extPub: extPubB64 }),
  });
  if (!res.ok) throw new Error(`pairing create failed (${res.status})`);
  return res.json();
}

export async function waitForPhone(
  pairingId: string,
  extToken: string,
): Promise<{ completed: boolean; phonePub?: string; phoneNameBlob?: string }> {
  const res = await req(`/v1/pairings/${pairingId}/wait`, { bearer: extToken });
  if (!res.ok) throw new Error(`pairing wait failed (${res.status})`);
  return res.json();
}

export async function unpair(pairingId: string, extToken: string): Promise<void> {
  await req(`/v1/pairings/${pairingId}`, { method: "DELETE", bearer: extToken });
}

export async function createRequest(
  pairingId: string,
  extToken: string,
  requestBlob: string,
): Promise<{ requestId: string; expiresAt: number; pushed: boolean }> {
  const res = await req("/v1/requests", {
    method: "POST",
    bearer: extToken,
    body: JSON.stringify({ pairingId, requestBlob }),
  });
  if (!res.ok) throw new Error(`request create failed (${res.status})`);
  return res.json();
}

export type WaitResult =
  | { status: "answered"; answerBlob: string }
  | { status: "expired" }
  | { status: "pending"; expiresAt: number }
  | { status: "gone" };

export async function waitForAnswer(
  requestId: string,
  extToken: string,
): Promise<WaitResult> {
  const res = await req(`/v1/requests/${requestId}/wait`, { bearer: extToken });
  if (res.status === 404) return { status: "gone" };
  if (!res.ok) throw new Error(`answer wait failed (${res.status})`);
  return res.json();
}
