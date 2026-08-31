document.addEventListener("DOMContentLoaded", () => {
  const merchantEl = document.getElementById("merchant-name");
  const adviceEl = document.getElementById("card-advice");

  if (chrome && chrome.tabs) {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (tabs.length > 0 && tabs[0].url) {
        const url = new URL(tabs[0].url);
        merchantEl.textContent = url.hostname;
        adviceEl.textContent = "Check recommended card on this merchant page.";
      }
    });
  }

  document.getElementById("open-app")?.addEventListener("click", () => {
    window.open("https://inunity.ca", "_blank");
  });
});
