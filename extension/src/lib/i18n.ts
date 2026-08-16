/**
 * Extension UI localization.
 *
 * The language is chosen from the *browser* (default) or set manually in
 * Options. It is never tied to the paired phone — the two are fully separate,
 * and pairing exchanges only keys, never a locale.
 *
 * chrome.i18n.getMessage always follows the browser UI language and cannot be
 * overridden, so for a manual picker we resolve strings ourselves from the
 * locale message maps bundled at build time. chrome.i18n still drives the
 * manifest name/description (which the store shows per browser language).
 *
 * Positional tokens are written as {0}, {1}, … in the message and filled here.
 */
import ar from "../../public/_locales/ar/messages.json";
import de from "../../public/_locales/de/messages.json";
import en from "../../public/_locales/en/messages.json";
import es from "../../public/_locales/es/messages.json";
import fr from "../../public/_locales/fr/messages.json";
import hi from "../../public/_locales/hi/messages.json";
import id from "../../public/_locales/id/messages.json";
import it from "../../public/_locales/it/messages.json";
import ja from "../../public/_locales/ja/messages.json";
import ko from "../../public/_locales/ko/messages.json";
import pt from "../../public/_locales/pt/messages.json";

type Messages = Record<string, { message: string }>;

const EN = en as Messages;
const LOCALES: Record<string, Messages> = {
  en, es, de, fr, it, pt, id, hi, ar, ja, ko,
} as Record<string, Messages>;

/** Languages offered in the manual picker, in their own script. */
export const UI_LANGUAGES: ReadonlyArray<{ code: string; name: string }> = [
  { code: "en", name: "English" },
  { code: "es", name: "Español" },
  { code: "de", name: "Deutsch" },
  { code: "fr", name: "Français" },
  { code: "it", name: "Italiano" },
  { code: "pt", name: "Português" },
  { code: "id", name: "Bahasa Indonesia" },
  { code: "hi", name: "हिन्दी" },
  { code: "ar", name: "العربية" },
  { code: "ja", name: "日本語" },
  { code: "ko", name: "한국어" },
];

const RTL = new Set(["ar"]);
const AUTO = "auto";
let active = "en";

/** The best supported locale for the browser's UI language ("de-DE" -> "de"). */
function browserLang(): string {
  const ui = (chrome.i18n?.getUILanguage?.() ?? "en").toLowerCase();
  const base = ui.split("-")[0]!;
  return LOCALES[base] ? base : "en";
}

function resolve(pref: string): string {
  if (pref === AUTO) return browserLang();
  return LOCALES[pref] ? pref : browserLang();
}

function applyDir(): void {
  if (typeof document === "undefined") return;
  document.documentElement.setAttribute("dir", RTL.has(active) ? "rtl" : "ltr");
  document.documentElement.setAttribute("lang", active);
}

/** Read the stored preference and set the active language. Call once, before
 * the first render, on every extension page. */
export async function initI18n(): Promise<void> {
  active = resolve(await getUiLang());
  applyDir();
}

export function t(key: string, subs?: Array<string | number>): string {
  const dict = LOCALES[active] ?? EN;
  let msg = dict[key]?.message ?? EN[key]?.message ?? key;
  if (subs && subs.length) {
    msg = msg.replace(/\{(\d+)\}/g, (_m: string, i: string) =>
      String(subs[Number(i)] ?? ""),
    );
  }
  return msg;
}

/** Apply translations to any element carrying data-i18n in a static HTML page. */
export function localizeDom(root: ParentNode = document): void {
  for (const node of root.querySelectorAll<HTMLElement>("[data-i18n]")) {
    node.textContent = t(node.dataset.i18n!);
  }
}

/** The stored preference: "auto" (follow browser) or a locale code. */
export async function getUiLang(): Promise<string> {
  const { uiLang } = await chrome.storage.local.get("uiLang");
  return (uiLang as string | undefined) ?? AUTO;
}

/** Persist a new preference and update the active language immediately. */
export async function setUiLang(pref: string): Promise<void> {
  await chrome.storage.local.set({ uiLang: pref });
  active = resolve(pref);
  applyDir();
}
