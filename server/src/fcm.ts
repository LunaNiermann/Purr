import { readFileSync } from "node:fs";
import { GoogleAuth } from "google-auth-library";

/**
 * FCM HTTP v1 sender. Data-only, high-priority messages whose payload is
 * routing information only ({requestId, pairingId}) — never domains,
 * account names, or codes. FCM is TLS to Google, not end-to-end encrypted,
 * so the payload must stay meaningless to Google.
 *
 * The Firebase service account can be supplied three ways (checked in order),
 * so it fits whatever a host makes easy:
 *   FCM_SERVICE_ACCOUNT_JSON  — the JSON itself, raw or base64 (PaaS env var)
 *   FCM_SERVICE_ACCOUNT       — a path to the JSON file (mounted volume)
 * When none is set the server still works: phones poll pending requests on
 * app open, so a missing push degrades to "open the app" (design 5f).
 */
export interface Pusher {
  /** True when a valid service account was loaded and push can be sent. */
  configured: boolean;
  send(fcmToken: string, data: Record<string, string>): Promise<boolean>;
}

export interface FcmConfig {
  /** Raw JSON or base64-encoded JSON of the service account. */
  json?: string | undefined;
  /** Path to a service-account JSON file. */
  path?: string | undefined;
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

function loadServiceAccount(
  config: FcmConfig,
  log: { warn: (msg: string) => void },
): ServiceAccount | null {
  let raw: string | undefined;
  if (config.json && config.json.trim()) {
    const value = config.json.trim();
    // Accept either the JSON itself or a base64 blob of it — base64 avoids
    // newline/quote mangling in env-var UIs.
    raw = value.startsWith("{")
      ? value
      : Buffer.from(value, "base64").toString("utf8");
  } else if (config.path && config.path.trim()) {
    try {
      raw = readFileSync(config.path, "utf8");
    } catch (err) {
      log.warn(`FCM_SERVICE_ACCOUNT file unreadable: ${(err as Error).message}`);
      return null;
    }
  }
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as Partial<ServiceAccount>;
    if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
      log.warn("FCM service account is missing required fields — push disabled");
      return null;
    }
    return parsed as ServiceAccount;
  } catch {
    log.warn("FCM service account is not valid JSON — push disabled");
    return null;
  }
}

export function createPusher(config: FcmConfig, log: {
  info: (msg: string) => void;
  warn: (msg: string) => void;
}): Pusher {
  const creds = loadServiceAccount(config, log);
  if (!creds) {
    log.warn("FCM not configured — push disabled, phones must poll");
    return { configured: false, send: async () => false };
  }
  log.info(`FCM configured — push enabled for project ${creds.project_id}`);
  const auth = new GoogleAuth({
    credentials: {
      client_email: creds.client_email,
      private_key: creds.private_key,
    },
    projectId: creds.project_id,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const url = `https://fcm.googleapis.com/v1/projects/${creds.project_id}/messages:send`;

  return {
    configured: true,
    async send(fcmToken, data) {
      try {
        const client = await auth.getClient();
        const token = (await client.getAccessToken()).token;
        const res = await fetch(url, {
          method: "POST",
          headers: {
            authorization: `Bearer ${token}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: fcmToken,
              data,
              android: { priority: "HIGH", ttl: "60s" },
              // iOS can't render a data-only message: APNs would treat it as a
              // silent background push — throttled, best-effort, and never
              // delivered after the user swipes the app away. So for Apple we
              // attach a visible alert with generic, static text: the same
              // words for every request, so APNs/Google still learn nothing
              // (the domain, account, and code stay in the sealed blob the
              // phone fetches after the tap). No content-available flag: the
              // system shows the banner itself; waking the app too would
              // just double-post via the local-notification path.
              apns: {
                headers: {
                  "apns-priority": "10",
                  // Mirror the 60 s request TTL — a code prompt after expiry
                  // would only open the app onto nothing.
                  "apns-expiration": String(Math.ceil(Date.now() / 1000) + 60),
                },
                payload: {
                  aps: {
                    alert: {
                      title: "Your browser needs a code",
                      body: "Tap to approve on your phone",
                    },
                    sound: "default",
                  },
                },
              },
            },
          }),
        });
        if (!res.ok) {
          log.warn(`FCM send failed: ${res.status} ${await res.text()}`);
          return false;
        }
        return true;
      } catch (err) {
        log.warn(`FCM send error: ${(err as Error).message}`);
        return false;
      }
    },
  };
}
