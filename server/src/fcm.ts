import { readFileSync } from "node:fs";
import { GoogleAuth } from "google-auth-library";

/**
 * FCM HTTP v1 sender. Data-only, high-priority messages whose payload is
 * routing information only ({requestId, pairingId}) — never domains,
 * account names, or codes. FCM is TLS to Google, not end-to-end encrypted,
 * so the payload must stay meaningless to Google.
 *
 * Configured via FCM_SERVICE_ACCOUNT (path to a service-account JSON).
 * When unconfigured the server still works: phones poll pending requests
 * on app open, so a missing push degrades to "open the app" (design 5f).
 */
export interface Pusher {
  send(fcmToken: string, data: Record<string, string>): Promise<boolean>;
}

export function createPusher(serviceAccountPath: string | undefined, log: {
  info: (msg: string) => void;
  warn: (msg: string) => void;
}): Pusher {
  if (!serviceAccountPath) {
    log.warn("FCM_SERVICE_ACCOUNT not set — push disabled, phones must poll");
    return { send: async () => false };
  }
  const creds = JSON.parse(readFileSync(serviceAccountPath, "utf8")) as {
    project_id: string;
  };
  const auth = new GoogleAuth({
    keyFile: serviceAccountPath,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const url = `https://fcm.googleapis.com/v1/projects/${creds.project_id}/messages:send`;

  return {
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
