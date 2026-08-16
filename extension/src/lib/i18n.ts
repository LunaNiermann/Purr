/**
 * Thin wrapper over chrome.i18n. Messages live in public/_locales/<lang>/
 * messages.json and are picked automatically from the browser UI language,
 * falling back to the manifest's default_locale ("en").
 *
 * Positional tokens are written as {0}, {1}, … in the message and filled here,
 * so we don't depend on chrome's named-placeholder declarations.
 */
export function t(key: string, subs?: Array<string | number>): string {
  let msg = chrome.i18n.getMessage(key) || key;
  if (subs && subs.length) {
    msg = msg.replace(/\{(\d+)\}/g, (_, i) => String(subs[Number(i)] ?? ""));
  }
  return msg;
}

/** Apply translations to any element carrying data-i18n / data-i18n-* in a
 * static HTML page (used for the popup header buttons). */
export function localizeDom(root: ParentNode = document): void {
  for (const node of root.querySelectorAll<HTMLElement>("[data-i18n]")) {
    node.textContent = t(node.dataset.i18n!);
  }
}
