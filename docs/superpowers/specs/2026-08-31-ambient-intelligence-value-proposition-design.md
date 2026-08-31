# PickMe Evolved Value Proposition & iOS 26 Platform Architecture

**Date:** 2026-08-31  
**Status:** Living Design Document (Open to iterative refinement by future agents)  
**Applies to:** `App/` (SwiftUI / iOS Integration), `Engine/` (Card Semantics), `Store/` (Local-First Persistence)  
**Authoritative Policies:** [`product-boundaries.md`](../../policies/product-boundaries.md) (A5, E1), [`REPO_MAP.md`](../../REPO_MAP.md)

---

## 1. Executive Summary & Why This Exists

PickMe was founded to be the ecosystem's authoritative **card-decision control center** at checkout. Its deterministic engine accurately computes point valuations, network eligibility, foreign exchange fees, and rewards arithmetic on-device.

Historically, card optimization tools have suffered from high friction: users must remember to open an app, search for a merchant, and decode complex points currencies at the physical register or online payment sheet.

This specification documents the strategic evolution of PickMe’s value proposition in light of modern iOS platform capabilities (iOS 18 through iOS 26) and a disciplined, phased execution model. 

### The Core Shift

```
┌──────────────────────────────────────┐         ┌────────────────────────────────────────────────────────┐
│          Traditional Model           │         │                     Evolved Model                      │
│ "Open an app and calculate which     │ ──────► │ "The right card is always in your hand, verified       │
│  card gets the most abstract points" │         │  on-device, with zero effort and zero cognitive load." │
└──────────────────────────────────────┘         └────────────────────────────────────────────────────────┘
```

---

## 2. Core Pillars of the Evolved Value Proposition

### Pillar 1: Dual-Delivery Model (Ambient + Intentional)
Real-world checkout occurs in two distinct behavioral modes. PickMe adopts a complementary dual-delivery architecture:

1. **Ambient Proactive Path (In-Store / Geofenced):**
   * **Mechanism:** When a user arrives at a physical merchant, [`AmbientLocationService`](file:///Users/zub/Documents/Github_Projects/PickMe/App/CardCopilot/Services/AmbientLocationService.swift) triggers a low-power geofence.
   * **Surface:** Actionable Local Notification, Dynamic Island, and Smart Stack promotion via WidgetKit `WidgetRelevances`.
   * **Experience:** The user glances at their Lock Screen / Apple Watch while walking to the aisle; the decision is made before reaching the register.
2. **Intentional Fast Path (Online / Register Fallback):**
   * **Mechanism:** When shopping online (Safari, DoorDash, Uber) or if ambient triggers are silent.
   * **Surface:** Action Button, Control Center widget, or Siri On-Screen Awareness (`@AssistantIntent(schema:)`).
   * **Experience:** Instant card recommendation overlay in **< 2 seconds flat**.

---

### Pillar 2: The "Dopamine Loop" (Felt Cash > Abstract Points)
Abstract point multipliers (e.g., "4x MR" or "3% category tier") do not reinforce daily habit loops. Felt financial gain against an established baseline does.

1. **The Anchor Card:** During onboarding, the user identifies their baseline default card (e.g., Apple Card 1.5%, debit card, or 1% flat card).
2. **Instant Micro-Win (Point of Decision):**
   * *Before:* "Earn 3x points on this \$40 purchase."
   * *After:* **"Swipe Sapphire Reserve: +$1.60 earned over your default card."**
3. **Cumulative Monthly Value Recovered:**
   * Prominently featured in widgets and app headers:
   * **"🏆 \$34.20 recovered this month across 18 purchases."**
   * Translates rewards arithmetic into undeniable, quantified dollars.

---

### Pillar 3: Frictionless Onboarding (30 Seconds to Value)
Adoption fails when onboarding requires JSON schemas, manual bank logins, or deep reward program knowledge.

* **Step 1: Visual Gallery (Top 50–100 Cards):** Tap-to-select interface for popular US and Canadian cards covering ~80–90% of active wallets.
* **Step 2: Anchor Selection:** Single prompt: *"Which card do you normally tap if you don't think about it?"*
* **Step 3: Ambient Permission:** Standard iOS location/notification permission prompt.
* **Step 4: Immediate Ready State:** Pre-populated with verified contract metadata from `contracts/`.

---

### Pillar 4: "Best Rewards Card" $\rightarrow$ "Best Way to Pay"
Expanding beyond pure reward multipliers to protect users on major purchases:

* **Everyday Small Spend (< \$100 at Dining/Grocery):** Maximize net reward yield.
* **High-Ticket Electronics & Goods (> \$300 at Apple/Best Buy/Costco):**
  * Evaluate warranty extension and purchase theft/damage protection from [`BenefitsDocumentVault`](file:///Users/zub/Documents/Github_Projects/PickMe/App/CardCopilot/State/BenefitsDocumentVault.swift).
  * Example recommendation: *"Swipe Amex Platinum: Earns 1x (\$12), but activates 1-Year Extended Warranty + \$10,000 Theft/Damage Protection. (Better than earning \$18 on 1.5% with zero protection)."*
* **Travel & Transit:** Prioritize primary auto rental CDW and trip cancellation coverage when booking flights/rentals.

---

## 3. Key iOS 26 & Platform Capabilities Utilized

| Platform Capability | PickMe Integration Surface | Value Delivered |
|---|---|---|
| **Apple Intelligence Screen Awareness** | `AppIntents` / `AssistantSchema` | Instant card lookup during Safari & in-app digital checkouts |
| **FinanceKit Background Sync** | Local SwiftData reconciliation | Automatic category cap exhaustion tracking & verified value calculation |
| **On-Device Foundation Models (SLM)** | [`CategoryMapper`](file:///Users/zub/Documents/Github_Projects/PickMe/App/CardCopilot/Services/CategoryMapper.swift) / Merchant Resolution | Offline cleanup of messy POS strings (e.g. `SQ *MERCHANT`) with 100% privacy |
| **Visual Intelligence / Camera Control** | Camera Control Intent | Instant card check by pointing camera at physical register or storefront |
| **WidgetKit `WidgetRelevances`** | Smart Stack & Lock Screen | Proactive card elevation upon geofence arrival |
| **Liquid Glass Design System** | [`CardArtView`](file:///Users/zub/Documents/Github_Projects/PickMe/App/CardCopilot/Views/CardArtView.swift) & [`CheckoutFlowView`](file:///Users/zub/Documents/Github_Projects/PickMe/App/CardCopilot/Views/CheckoutFlowView.swift) | Fluid, refractive card visual themes native to modern iOS |

---

## 4. Staged Execution Plan

To ensure rigorous validation and maintain high engineering quality, implementation should follow this ordered sequence:

```
┌────────────────────────────────────────────────────────┐
│ Phase 1: Core Engine Precision & Onboarding Redesign   │
│ - Flawless deterministic arithmetic & category mapping │
│ - 30-second visual card picker onboarding              │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│ Phase 2: Live Validation & Feedback Loop Trial         │
│ - 10–20 real users × 30 transactions = 600 decisions   │
│ - Measure recommendation accuracy & friction points    │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│ Phase 3: The Dopamine Value Loop & Ambient Delivery    │
│ - Anchor card delta calculation ("+$X vs default")     │
│ - Ambient geofenced notifications & Smart Stack widget │
│ - Action Button / Siri Intent on-demand fallback       │
└──────────────────────────┬─────────────────────────────┘
                           │
┌──────────────────────────▼─────────────────────────────┐
│ Phase 4: Differentiated "Best Way to Pay" & iOS 26     │
│ - High-ticket purchase protection & warranty rules     │
│ - Dynamic spend cap exhaustion via FinanceKit          │
│ - On-screen awareness & Visual Intelligence intents    │
└────────────────────────────────────────────────────────┘
```

---

## 5. Architectural & Policy Governance

1. **A5 Compliance (Analytics on the Hub):**
   PickMe remains the fast, on-device point-of-decision engine. Deep portfolio visualization, multi-year trend analysis, and macro reports live on the web hub. PickMe maintains only the point-of-sale recommendation, transaction feedback, and the singular **Value Recovered** monthly figure.
2. **E1 Compliance (Ecosystem Role):**
   PickMe retains its standalone identity as the card copilot, interfacing smoothly with the broader ecosystem without diluting its brand.
3. **Local-First Privacy:**
   All transaction feeds, ambient visits, and merchant resolutions execute strictly on-device using SwiftData, CoreLocation, and local Apple Intelligence frameworks. No user financial telemetry is exported to cloud servers.

---

## 6. Guidance for Future Agents

* **Living Status:** Future agents are encouraged to iterate on this document as Apple SDK updates ship or as real-world user trial data reveals new friction points.
* **Semantic Authority:** Any changes to engine arithmetic, contract bytes, or fixtures must continue passing the cross-language gate:
  ```bash
  (cd Engine && swift test) && (cd android && ./gradlew :core:engine:test)
  ```
* **Simplicity First:** Maintain the < 2-second decision latency constraint. Never compromise point-of-sale speed for ancillary background tasks.
