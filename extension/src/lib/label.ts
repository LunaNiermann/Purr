/**
 * How this browser names itself to the phone. It rides in two places: the
 * per-request payload (so the approval sheet can say who is asking) and the
 * sealed name blob deposited at pairing time (so the phone's paired-browser
 * list can label this entry before any request has been made).
 */
export function browserLabel(): string {
  const ua = navigator.userAgent;
  const browser = ua.includes("Edg/") ? "Edge" : "Chrome";
  const os = ua.includes("Windows")
    ? "Windows"
    : ua.includes("Mac")
      ? "Mac"
      : "Linux";
  return `${browser} · ${os}`;
}
