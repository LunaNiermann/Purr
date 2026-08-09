/**
 * Shared approval-flow state, persisted in chrome.storage.session so it
 * survives the popup closing (which happens the instant the user switches to
 * their phone to approve). The background service worker owns the flow; the
 * popup only reads this and reflects it.
 */
export type FlowStatus =
  | "awaitingPhone"
  | "filled"
  | "filledClipboard"
  | "denied"
  | "expired"
  | "unreachable"
  | "unmatched";

export interface Flow {
  status: FlowStatus;
  domain: string;
  requestId?: string;
  code?: string; // only for filledClipboard (page field not found)
  at: number;
}

const KEY = "flow";

export async function getFlow(): Promise<Flow | null> {
  const { flow } = await chrome.storage.session.get(KEY);
  return (flow as Flow | undefined) ?? null;
}

export async function setFlow(flow: Flow | null): Promise<void> {
  if (flow === null) await chrome.storage.session.remove(KEY);
  else await chrome.storage.session.set({ [KEY]: flow });
}
