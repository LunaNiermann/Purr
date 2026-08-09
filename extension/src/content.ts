/**
 * Content script: finds 2FA code fields and fills them on request from the
 * popup. It renders NO UI of its own — every visible surface is the
 * extension-owned popup (the DEF CON 33 clickjacking lesson).
 */

interface CodeTarget {
  kind: "single" | "segmented";
  inputs: HTMLInputElement[];
}

const OTP_NAME_RE =
  /(^|[-_ ])(otp|totp|2fa|mfa|one[-_ ]?time|verification|auth(entication)?)([-_ ]?(code|token|pin))?([-_ ]|$)|^code$|^token$/i;

function visible(el: HTMLElement): boolean {
  const rect = el.getBoundingClientRect();
  if (rect.width === 0 || rect.height === 0) return false;
  const style = getComputedStyle(el);
  return style.visibility !== "hidden" && style.display !== "none";
}

export function findCodeTarget(root: Document): CodeTarget | null {
  const inputs = [...root.querySelectorAll<HTMLInputElement>("input")].filter(
    (i) =>
      !i.disabled &&
      !i.readOnly &&
      visible(i) &&
      ["text", "tel", "number", "password", ""].includes(i.type || "text"),
  );

  // Segmented: 4-8 single-char boxes near each other.
  const singles = inputs.filter(
    (i) => i.maxLength === 1 || i.getAttribute("maxlength") === "1",
  );
  if (singles.length >= 4 && singles.length <= 8) {
    return { kind: "segmented", inputs: singles };
  }

  // Single field: autocomplete=one-time-code wins, then name/id heuristics.
  const byAutocomplete = inputs.find(
    (i) => i.autocomplete === "one-time-code",
  );
  if (byAutocomplete) return { kind: "single", inputs: [byAutocomplete] };

  const byName = inputs.find(
    (i) =>
      OTP_NAME_RE.test(i.name) ||
      OTP_NAME_RE.test(i.id) ||
      OTP_NAME_RE.test(i.getAttribute("aria-label") ?? ""),
  );
  if (byName) return { kind: "single", inputs: [byName] };
  return null;
}

function setNativeValue(input: HTMLInputElement, value: string): void {
  // React/Vue ignore plain .value writes; go through the native setter and
  // dispatch the events frameworks listen for.
  const setter = Object.getOwnPropertyDescriptor(
    HTMLInputElement.prototype,
    "value",
  )?.set;
  setter?.call(input, value);
  input.dispatchEvent(new Event("input", { bubbles: true }));
  input.dispatchEvent(new Event("change", { bubbles: true }));
}

function fill(code: string, submit: boolean): boolean {
  const target = findCodeTarget(document);
  if (!target) return false;
  if (target.kind === "single") {
    const input = target.inputs[0]!;
    input.focus();
    setNativeValue(input, code);
  } else {
    const digits = code.split("");
    target.inputs.forEach((input, i) => {
      input.focus();
      setNativeValue(input, digits[i] ?? "");
    });
  }
  if (submit) {
    const form = target.inputs[0]!.form;
    const button = form?.querySelector<HTMLButtonElement>(
      'button[type="submit"], input[type="submit"], button:not([type])',
    );
    button?.click();
  }
  return true;
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === "twokeys:probe") {
    sendResponse({ found: findCodeTarget(document) !== null });
  } else if (message?.type === "twokeys:fill") {
    sendResponse({
      filled: fill(message.code as string, message.submit as boolean),
    });
  }
  return undefined;
});
