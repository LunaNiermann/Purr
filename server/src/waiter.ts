/**
 * Long-poll coordination: waiters park on a key until notify() or timeout.
 * Chosen over WebSockets because MV3 service workers are killed after ~30 s
 * idle; short long-polls survive worker restarts with no keepalive protocol.
 */
export class Waiters {
  private waiting = new Map<string, Set<() => void>>();

  /** Resolves true if notified before timeoutMs elapsed. */
  wait(key: string, timeoutMs: number): Promise<boolean> {
    return new Promise((resolve) => {
      const set = this.waiting.get(key) ?? new Set();
      this.waiting.set(key, set);
      const timer = setTimeout(() => {
        set.delete(entry);
        resolve(false);
      }, timeoutMs);
      const entry = () => {
        clearTimeout(timer);
        resolve(true);
      };
      set.add(entry);
    });
  }

  notify(key: string): void {
    const set = this.waiting.get(key);
    if (!set) return;
    this.waiting.delete(key);
    for (const fn of set) fn();
  }
}
