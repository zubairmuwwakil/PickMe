# Benefits Disclosure & Protection Lens — Design

**Date:** 2026-08-15 · **Status:** Approved by Zubair (this doc is the validated design; implementation plan follows)
**Scope decision:** Zubair overrode the engine-first parking-lot recommendation: benefits disclosure is designed and **built now**, in parallel with the 30-checkout experiment reaching deployment. The recurring-payment assignment audit is a **separate session**. Card-acquisition suggestions ("which card to GET") were considered and **rejected** for now — they conflict with the locked "which card to USE" positioning and require a market-wide catalogue plus a real spend distribution, neither of which exists yet.

## 1. Why

The target user (knowledge-gap casual multi-card holder) does not know their cards' earn rates — and knows their insurance benefits even less. At big-ticket checkouts the earn delta between the best and second-best card is dollars, while purchase protection, extended warranty, or travel coverage is plausibly worth hundreds. Nothing in Canada surfaces this at the moment of payment. The feature answers two moments:

1. **Ambient**: "you're buying something protected — here's what the recommended card gives you."
2. **Deliberate** (the protection lens): "I'm booking a flight / renting a car / buying a laptop — which card earns best, and *separately*, which protects me best?"

## 2. Decisions

| # | Decision | Consequence |
|---|----------|-------------|
| B1 | **Disclose, don't score.** No benefit is ever converted to CAD or fed to the `Scorer`. The earn ranking and the protection comparison meet only in the UI. | Structural: `BenefitsAdvisor` has no import path into the scoring pipeline. Mirrors `PortfolioAnalyzer.requiredBenefitValueCad` and the valuation policy. |
| B2 | **Certificate language, never coverage promises.** Fixed wording: "per the certificate of insurance"; never "you're covered". Conditions and exclusions are stored and displayed **verbatim**, not paraphrased. Standing footer on every benefits surface: *"Coverage depends on certificate conditions — verify before relying on it."* | A wrong "covered" is a four-figure harm caught only in a crisis; wording is a correctness feature, not copy. |
| B3 | **All four families in v1 schema and data**: shopping, travel disruption, rental CDW, emergency travel medical (Zubair, this session). | Ten benefit kinds (§4). One certificate-reading pass covers everything. |
| B4 | **Zubair compiles the real data; Claude ships structure + stub.** Same trust model as the earn-rules dossier. The shipped `benefits-catalogue.json` is drafted from public issuer pages with every entry `verificationStatus: "stub"` — dev scaffolding, visually unmistakable, never trusted display. Zubair's dossier replaces the file wholesale. | Extraction template (§9) makes his certificate session mechanical. No in-app editing of benefits data. |
| B5 | **Parallel subsystem** (architecture A): separate `benefits-catalogue.json` + pure `BenefitsAdvisor`; `SeedLoader→RuleMatcher→CapMath→Scorer` pipeline untouched. | Zero risk to the validated engine tests and the 30-checkout experiment. Benefits freshness decoupled from earn-rule freshness — two truth procedures, two files. |
| B6 | **No new merchant categories.** The earn category vocabulary is the experiment's ground-truth axis and stays frozen. Benefit triggering uses (a) existing `PurchaseContext` signals and (b) a user-declared `BenefitContext` for planned purchases. | Earn categories describe the merchant (statement-verifiable); benefit contexts describe the purchase (known only to the buyer). Declared context has no prediction-accuracy problem. |
| B7 | **"Best protection" = Pareto dominance, never weights.** Badge only when exactly one card is equal-or-better on every displayed coverage row. Ties or trade-offs render as "trade-off — your call" over the comparison table. | The badge is a checkable factual claim, cell-by-cell. The benefits analogue of `valuationSensitive`. |
| B8 | **Absence is data, gated by verification.** Missing kind at `certificateVerified` = "no coverage"; missing kind at `stub`/`issuerPage` = "unknown — unverified". Rendered differently. | Crypto.com honestly shows "no coverage found (unverified)" until the certificate pass proves the negative. |
| B9 | **Prediction log untouched.** Benefits render; they don't record. No schema change to the immutable log. | Experiment data path stays byte-identical. |

## 3. Architecture

```
Engine package (pure, no UI):
  Resources/benefits-catalogue.json      ← new, sibling of card-catalogue.json
  Models/BenefitsModels.swift            ← catalogue, kinds, coverage, verification
  Engine/BenefitsAdvisor.swift           ← disclosures(…) + comparison(…)
  Loading: BenefitsLoader (mirrors SeedLoader pattern)

App:
  Checkout disclosure lines + detail sheet   (RecommendationView area)
  Protection lens (declared context → table) (new view, Home + checkout entry)
  Per-card benefits reference screen         (new view; doubles as verification checklist)
```

## 4. Data model

Top level mirrors the earn catalogue's provenance discipline: `benefitsCatalogueVersion`, `_provenance`, `cards[]`.

Per card:

```json
{
  "cardId": "amex-cobalt",
  "certificate": {
    "underwriter": "…",
    "sourceUrl": "…/certificate.pdf",
    "certificateDate": null,
    "lastVerifiedAt": null,
    "verificationStatus": "stub"
  },
  "benefits": [
    {
      "benefitId": "cobalt-purchase-protection",
      "family": "shopping",
      "kind": "purchaseProtection",
      "coverage": { "windowDays": 90, "maxPerOccurrenceCad": 1000, "maxAnnualCad": null },
      "conditions": ["Full purchase charged to the card"],
      "exclusions": ["…"],
      "certificateQuote": null,
      "notes": null
    }
  ]
}
```

**Families → kinds (10):**

| Family | Kinds | Typed coverage fields (comparison rows) |
|---|---|---|
| `shopping` | `purchaseProtection`, `extendedWarranty`, `mobileDeviceInsurance` | windowDays, maxPerOccurrenceCad, maxAnnualCad; extraYears, maxOriginalWarrantyYears; maxCad, deductibleCad |
| `travelDisruption` | `flightDelay`, `baggageDelay`, `baggageLoss`, `tripCancellation`, `tripInterruption` | delayHours, maxCad, perDayCad; maxTripLengthDays where applicable |
| `rentalCdw` | `rentalCdw` | maxRentalDays, maxVehicleValueCad |
| `travelMedical` | `travelMedical` | maxCad, maxTripLengthDays, ageLimit |

Typed fields exist **only** for what the comparison table sorts/displays. Everything conditional lives verbatim in `conditions`/`exclusions`. Unknown `kind` values must decode tolerantly (forward compatibility).

**Verification ladder:** `stub` → `issuerPage` → `certificateVerified`. Status renders on every surface; `stub` shows an explicit "unverified draft" chip.

## 5. Engine API

```swift
public enum BenefitsAdvisor {
    /// Path 1 — ambient. Conservative triggers from the checkout's existing facts.
    static func disclosures(context: PurchaseContext, wallet: [CardID],
                            catalogue: BenefitsCatalogue) -> [BenefitDisclosure]

    /// Path 2 — deliberate. User-declared purchase kind; no detection involved.
    static func comparison(context: BenefitContext, wallet: [CardID],
                           catalogue: BenefitsCatalogue) -> ProtectionComparison
}

public struct BenefitContext { kind: flight | trip | carRental | electronics | mobileDevice | applianceFurniture; abroad: Bool }
public struct BenefitDisclosure { cardId, kind, coverageFacts, conditions, exclusions, verification }
public struct ProtectionComparison { relevantKinds, rows(per card), dominantCardId: CardID? /* nil = trade-off */ }
```

**Ambient trigger rules (v1, thresholds live in the catalogue file, not code):**

- Shopping disclosures: `amountCad ≥ bigTicketThresholdCad` (start 150) **and** category ∉ consumables set (dining, grocery, foodDelivery, gasStation, transit, drugStore, cafe/bakery) → shopping-family lines for the recommended card.
- Travel hints: category == `hotel` **or** `country != "CA"` **or** `currency != "CAD"` → travel-medical + disruption hint line.
- Cross-card nudge: if a non-recommended card has coverage in a triggered family that the recommended card lacks entirely → one "compare" line into the lens. Never re-ranks.

**Declared context → relevant kinds:**

| Context | Relevant kinds |
|---|---|
| `flight`, `trip` | `flightDelay`, `baggageDelay`, `baggageLoss`, `tripCancellation`, `tripInterruption`; + `travelMedical` when `abroad` |
| `carRental` | `rentalCdw`; + `travelMedical` when `abroad` |
| `electronics`, `applianceFurniture` | `purchaseProtection`, `extendedWarranty` |
| `mobileDevice` | `purchaseProtection`, `extendedWarranty`, `mobileDeviceInsurance` |

**Dominance rule (B7):** over the displayed coverage rows for the declared context, card A dominates B iff A ≥ B on every row and A > B on at least one (missing coverage = worst). Badge iff exactly one maximal card. Otherwise `dominantCardId = nil` → "trade-off" UI.

**Lens earn line:** shown only when the user enters an (optional) amount. Computed by the normal engine with category `"other"` — none of these purchase kinds has a bonus category in the wallet's earn rules, so base rates + FX + cap handling apply correctly. (Hotel bookings for Bonvoy earn go through the regular checkout flow; the lens is a protection tool, not a second earn path.)

## 6. UI surfaces

1. **Checkout disclosure** — ≤2 quiet lines under the recommendation ("Purchase protection 90 days · Warranty +1 yr — per certificate"); tap → sheet with coverage facts, verbatim conditions/exclusions, verification chip, B2 footer. Plus the cross-card nudge line when triggered.
2. **Protection lens** — entries: "Big purchase or trip" on Home; the nudge/compare link at checkout. Declare context → comparison table (columns = cards with any relevant coverage; rows = typed facts; tap-through to conditions). Dominance badge or "trade-off — your call". The earn winner for the same purchase shows as one line alongside — two runs, one screen, never merged.
3. **Reference screen** — first per-card browse surface: card list → all benefits with verification chips. Doubles as Zubair's verification checklist; done when every chip reads `certificateVerified`.

## 7. Testing

Engine-level (fixture benefits catalogue with synthetic cards covering all 10 kinds):

- Trigger boundaries: threshold edges, consumables exclusion, hotel/foreign/currency triggers, recommended-vs-nudge selection.
- Comparison assembly: relevant-kind filtering per context, row construction, missing-coverage handling.
- Dominance: unique dominant; tie → no badge; strict trade-off → no badge; missing-family cases.
- Verification semantics: stub-absence ("unknown") vs certificateVerified-absence ("no coverage") produce distinct outputs (B8).
- Schema: round-trip decode, unknown-kind tolerance, required provenance fields.

App surfaces verified on simulator (no prediction-log or category-flow changes to regression-test — B6/B9 keep those paths untouched).

## 8. Non-goals (v1)

No CAD valuation of benefits; no Scorer/RecommendationEngine/prediction-log changes; no claims-filing guidance or insurance advice; no benefits for non-wallet cards; no push alerts (cap-visibility session owns alerting); no in-app benefits editing; no new personal-data collection (benefits data is card metadata — Law 25 posture unchanged).

## 9. Deliverables & build order

1. Engine: `BenefitsModels` + `BenefitsLoader` + fixtures + decode/verification tests.
2. Engine: `BenefitsAdvisor` (triggers, comparison, dominance) + tests.
3. Stub `benefits-catalogue.json` — all 10 wallet cards, public-page draft, everything `stub`.
4. App: checkout disclosure + detail sheet.
5. App: protection lens (context picker → table → dominance/trade-off).
6. App: reference/verification screen.
7. `docs/research/benefits-extraction-template.md` + fill-in JSON skeleton: per-kind field guide (units, where each number lives in a typical certificate) so Zubair's certificate session is mechanical.

## 10. Open items (owner data)

- Zubair's certificate dossier (replaces stub file; per-card `certificateDate` matters — terms vary by issue date).
- Unchanged from before, still pending for the experiment: Tangerine selected categories, Rogers link + anniversary, Crypto Level Up Pro state, Scotia account-year anchor, **current cap progress** (stale Scotia cap progress can fail the experiment's arithmetic check independent of this feature).
