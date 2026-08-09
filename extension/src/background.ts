/**
 * MV3 service worker. Deliberately thin: the popup drives the approval flow
 * while it's open (MV3 workers die after ~30 s idle, so nothing here relies
 * on staying resident). The worker's only jobs are first-run onboarding and
 * badge hygiene.
 */

chrome.runtime.onInstalled.addListener((details) => {
  if (details.reason === "install") {
    void chrome.runtime.openOptionsPage();
  }
});
