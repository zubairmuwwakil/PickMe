# Apple Watch Screenshots for App Store Connect

This directory contains ready-to-upload Apple Watch screenshot assets and promotional showcase graphics for **PickMe (Canadian Credit Card Optimizer)**.

---

## 📁 Directory Structure & Resolutions

All screenshots are formatted in RGB PNG format, 100% compliant with Apple's App Store Connect requirements (no transparency, accurate display dimensions).

| Folder | Target Device | Exact Dimensions | App Store Connect Status |
| :--- | :--- | :--- | :--- |
| **`AppleWatch_422x514_Primary/`** | **Apple Watch Ultra 2/3 / Series 10 Max** | **`422 × 514 px`** | **⭐ Recommended (Primary Ultra/Max)** |
| **`AppleWatch_410x502_Ultra/`** | **Apple Watch Ultra 1/2 (49mm)** | **`410 × 502 px`** | **✅ Verified Ultra** |
| **`AppleWatch_416x496_Series10/`** | **Apple Watch Series 10 / 11 (46mm)** | **`416 × 496 px`** | **✅ Verified Series 10** |
| **`AppleWatch_396x484_Series9/`** | **Apple Watch Series 7 / 8 / 9 (45mm)** | **`396 × 484 px`** | **✅ Verified Series 7/8/9** |
| **`AppleWatch_368x448_SE/`** | **Apple Watch Series 4 / 5 / 6 / SE (44mm)** | **`368 × 448 px`** | **✅ Verified SE / Series 4-6** |
| **`AppleWatch_312x390_Series3/`** | **Apple Watch Series 3 (42mm)** | **`312 × 390 px`** | **✅ Verified Series 3** |
| `AppleWatch_Framed_Showcase/` | Marketing / Web / Promo | `1080 × 1920 px` | Promotional Showcase only |

---

## ⌚ Included Screenshot Screens

1. **`01_watch_category_picker.png` - "Which Card?" Category Picker**
   - Instant wrist menu before tapping Apple Pay: Groceries, Dining, Gas & Fuel, Transit, Costco, Other.
   - Includes quick access to real-time spending caps.

2. **`02_watch_groceries_recommendation.png` - Instant Grocery Recommendation**
   - American Express Cobalt Card ($100 spend).
   - Highlighting **5.0 MR pts / $1** (5x multiplier) and **+$3.00 advantage vs default card**.

3. **`03_watch_costco_recommendation.png` - Costco Wholesale Optimizer**
   - Rogers Red World Elite Mastercard ($150 spend).
   - Highlighting **2.0% Cash Back** and Canada-specific **Mastercard exclusivity rule** (+$1.50 vs non-eligible cards).

4. **`04_watch_dining_recommendation.png` - Dining & Restaurants**
   - American Express Cobalt Card ($40 spend).
   - Highlighting **5x Points (5.0 MR / $1)** and **+$1.20 advantage vs default card**.

5. **`05_watch_spending_caps.png` - Real-Time Spending Caps Monitor**
   - Active cap tracking for Canadian rewards:
     - Amex Cobalt: 5x Grocery Cap ($1,850 / $2,500 spent • $650 left)
     - Scotia Momentum VI: 4% Groceries & Gas Cap ($16,600 / $25,000 spent • $8,400 left)
     - Triangle World Elite: 4% Canadian Tire Cap ($1,200 / $10,000 spent • $8,800 left)

---

## 🚀 How to Re-generate or Update

To regenerate all screenshots at any time:

```bash
python3 scripts/generate_apple_watch_screenshots.py
```
