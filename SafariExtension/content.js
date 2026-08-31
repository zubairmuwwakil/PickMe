// PickMe Safari Extension - In-Page Content Script
// Deterministically identifies checkout domains and presents the winning card recommendation pill.

(function () {
  "use strict";

  const MERCHANT_RULES = {
    "amazon": { name: "Amazon", category: "Shopping", topCard: "Amazon Rewards Mastercard / Amex Cobalt (via gift cards)", multiplier: "2.5% - 5x" },
    "walmart": { name: "Walmart", category: "Groceries & General", topCard: "MBNA Rewards World Elite", multiplier: "5x / 4%" },
    "costco": { name: "Costco", category: "Wholesale", topCard: "CIBC Costco Mastercard (Online: 2% / In-Store: 3% Restaurants/Gas)", multiplier: "Mastercard Only" },
    "bestbuy": { name: "Best Buy", category: "Electronics", topCard: "Amex Platinum (1-Yr Extended Warranty + Purchase Protection)", multiplier: "Warranty Priority" },
    "doordash": { name: "DoorDash", category: "Dining / Delivery", topCard: "Amex Cobalt", multiplier: "5x points (~8.5%)" },
    "ubereats": { name: "Uber Eats", category: "Dining / Delivery", topCard: "Amex Cobalt", multiplier: "5x points (~8.5%)" },
    "uber": { name: "Uber Rides", category: "Transit / Travel", topCard: "Amex Cobalt", multiplier: "2x points" },
    "instacart": { name: "Instacart", category: "Groceries", topCard: "Amex Cobalt / Scotiabank Gold Amex", multiplier: "5x points (~8.5%)" },
    "aircanada": { name: "Air Canada", category: "Travel / Airline", topCard: "Amex Aeroplan Reserve", multiplier: "3x Aeroplan Points + Free Checked Bag" },
    "westjet": { name: "WestJet", category: "Travel / Airline", topCard: "WestJet RBC World Elite", multiplier: "2% WestJet Dollars + Companion Voucher" },
    "apple": { name: "Apple", category: "Electronics", topCard: "Amex SimplyCash Preferred (2% Cashback + Purchase Security)", multiplier: "2% + 1-Yr Extended Warranty" }
  };

  function detectMerchant() {
    const hostname = window.location.hostname.toLowerCase();
    for (const [key, info] of Object.entries(MERCHANT_RULES)) {
      if (hostname.includes(key)) {
        return info;
      }
    }
    return null;
  }

  function injectCardRecommendationPill(merchant) {
    if (document.getElementById("pickme-recommendation-pill")) return;

    const container = document.createElement("div");
    container.id = "pickme-recommendation-pill";
    container.style.cssText = `
      position: fixed;
      bottom: 24px;
      right: 24px;
      z-index: 999999;
      background: rgba(20, 20, 24, 0.94);
      color: #ffffff;
      backdrop-filter: blur(16px);
      -webkit-backdrop-filter: blur(16px);
      border: 1px solid rgba(255, 255, 255, 0.15);
      border-radius: 16px;
      padding: 14px 18px;
      box-shadow: 0 10px 30px rgba(0, 0, 0, 0.35);
      font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, sans-serif;
      font-size: 13px;
      display: flex;
      flex-direction: column;
      gap: 6px;
      max-width: 320px;
      transition: transform 0.25s ease, opacity 0.25s ease;
      cursor: pointer;
    `;

    container.innerHTML = `
      <div style="display: flex; align-items: center; justify-content: space-between;">
        <span style="font-weight: 700; font-size: 11px; text-transform: uppercase; letter-spacing: 0.6px; color: #60a5fa;">PickMe Recommendation</span>
        <button id="pickme-pill-close" style="background: none; border: none; color: #9ca3af; font-size: 14px; cursor: pointer; padding: 0 4px;">&times;</button>
      </div>
      <div style="font-weight: 600; font-size: 14px; color: #ffffff;">
        Use <span style="color: #38bdf8;">${merchant.topCard}</span>
      </div>
      <div style="font-size: 12px; color: #9ca3af;">
        ${merchant.name} (${merchant.category}) &bull; <strong style="color: #4ade80;">${merchant.multiplier}</strong>
      </div>
    `;

    document.body.appendChild(container);

    document.getElementById("pickme-pill-close").addEventListener("click", (e) => {
      e.stopPropagation();
      container.style.opacity = "0";
      container.style.transform = "translateY(12px)";
      setTimeout(() => container.remove(), 250);
    });
  }

  // Run on page load
  const currentMerchant = detectMerchant();
  if (currentMerchant) {
    // Only inject on checkout, cart, or merchant landing
    setTimeout(() => injectCardRecommendationPill(currentMerchant), 800);
  }
})();
