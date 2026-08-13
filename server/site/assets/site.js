// Purr landing page behavior: UA-based store detection + Ko-fi widget mount.
// Fallback content is already in the HTML, so nothing here is load-bearing.
(function () {
  "use strict";

  // --- Browser detection (order matters: Brave/Opera/Edge UAs contain "Chrome") ---
  var stores = {
    chrome: ["Chrome", "https://chromewebstore.google.com/detail/purr-2fa-authenticator/bfancenpneedgcnfjlajckcffpibjfkf", "Chrome Web Store"],
    edge: ["Edge", "https://microsoftedge.microsoft.com/addons/", "Edge Add-ons"],
    firefox: ["Firefox", "https://addons.mozilla.org/", "Firefox Add-ons"],
    brave: ["Brave", "https://chromewebstore.google.com/detail/purr-2fa-authenticator/bfancenpneedgcnfjlajckcffpibjfkf", "Chrome Web Store"],
    opera: ["Opera", "https://chromewebstore.google.com/detail/purr-2fa-authenticator/bfancenpneedgcnfjlajckcffpibjfkf", "Chrome Web Store"],
    safari: ["Safari", "#get", "Not supported yet, see other options"]
  };
  var ua = navigator.userAgent;
  var key = "chrome";
  if (navigator.brave) key = "brave";
  else if (/OPR\//.test(ua)) key = "opera";
  else if (/Edg\//.test(ua)) key = "edge";
  else if (/Firefox\//.test(ua)) key = "firefox";
  else if (/Chrome\//.test(ua)) key = "chrome";
  else if (/Safari\//.test(ua)) key = "safari";

  var name = stores[key][0];
  var href = stores[key][1];
  var store = stores[key][2];

  document.querySelectorAll(".js-browser-name").forEach(function (el) {
    el.textContent = name;
  });
  document.querySelectorAll(".js-ext-href").forEach(function (el) {
    el.setAttribute("href", href);
  });
  document.querySelectorAll(".js-ext-store").forEach(function (el) {
    el.textContent = store;
  });

  // --- Ko-fi widget (never call kofiwidget2.draw(): it uses document.write) ---
  var slot = document.getElementById("kofi-slot");
  function mountKofi(tries) {
    var w = window.kofiwidget2;
    if (!slot) return;
    if (w && typeof w.getHTML === "function") {
      w.init("Support me on Ko-fi", "#0f4e3c", "K3K01T7UXI");
      slot.innerHTML = w.getHTML();
      return;
    }
    if (tries < 20) setTimeout(function () { mountKofi(tries + 1); }, 250);
  }
  mountKofi(0);
})();
