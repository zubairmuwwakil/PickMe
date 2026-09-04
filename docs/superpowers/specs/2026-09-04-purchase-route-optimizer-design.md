# Purchase Route Optimizer — design

**Status:** V1 semantic core + nearby MCC graph + local gift-card inventory learning implemented 2026-09-04.

## Problem

Checkout currently answers one question well: given the merchant/category in front of the owner,
which owned card has the highest defensible decision value?

That is not always the globally best way to fund the purchase. A user may be able to buy a
merchant gift card at a higher-earning merchant, enter through a cashback portal, use a payment
intermediary, or activate a promotion before paying. These are alternate *purchase routes*, not
alternate card rules.

## Boundary

`RecommendationEngine` remains the sole authority for choosing an owned card for a card-funded
leg. It must not learn gift-card hacks or portal-specific routing.

`PurchaseRouteAdvisor` sits one level above it:

```
purchase goal
  ├─ direct route ───────────────> RecommendationEngine
  └─ alternate purchase route
       └─ acquisition/funding leg -> RecommendationEngine
```

The route layer compares net CAD decision value after route fees/friction. This preserves the
existing valuation, caps, acceptance, owner-state, and reward-rule semantics instead of creating a
second rewards calculator.

## V1

V1 supports one generic route template:

- destination aliases: Shoppers Drug Mart / Shoppers / Pharmaprix
- instrument: Shoppers Drug Mart gift card
- acquisition requirement: an eligible grocery merchant coding as MCC 5411
- evidence: `communityObserved`
- disclosure: inventory and reward treatment can vary; availability must be confirmed

The card is not hard-coded. If MBNA, Cobalt, or another owned card is worth more on the acquisition
leg, the normal recommendation engine chooses it.

## Noise / friction gate

A route is surfaced only if it clears **both**:

- at least CAD $1 incremental value; and
- at least 1 percentage point incremental return.

This is intentionally stricter than switching cards at the same till. An alternate route can cost
another stop, another checkout, or another stored-value instrument.

## Evidence model

Routes carry a distinct evidence level:

- `retailerConfirmed`
- `communityObserved`
- `experimental`

This is separate from D3 card-contract provenance. A community-observed route may be ranked as a
potential opportunity, but the UI must not present variable inventory or issuer reward treatment as
guaranteed.

MCC evidence is independently ranked by `MerchantMCCGraph`. The canonical 500-merchant seed is an
editorial prior, public directory observations are low-confidence external evidence, and reconciled
owner MCC observations can override those priors. A route never upgrades seed data into observed
terminal truth merely because it used the graph.

Gift-card inventory is a third evidence axis, independent from both route provenance and MCC. It is
resolved by `GiftCardInventoryGraph` from location-specific observations only.

## Checkout UI

For a single checkout recommendation, PickMe first evaluates the generic route, then asynchronously
resolves its acquisition requirement against nearby MapKit places through
`PurchaseRouteAcquisitionResolver`.

A physical candidate must:

- resolve safely to a canonical seed merchant;
- have the route-required MCC as the graph's current best prediction;
- retain the physical merchant's known network acceptance; and
- still clear the route's CAD + percentage-point friction threshold after normal card scoring.

The recommendation screen then replaces the generic instruction with the best nearby candidate,
including its distance and MCC-confidence disclosure. Reconciled owner MCC history participates in
that lookup. If a successful nearby scan finds no qualifying route, the generic placeholder is
suppressed instead of implying that the user should hunt for an unspecified store.

A physical route card also shows inventory state and two feedback controls:

- **Found it** records an owner-confirmed `available` observation for that exact location and gift
  card;
- **Not here** records an owner-confirmed `unavailable` observation for that exact location and gift
  card.

The observation is persisted locally and the route list is re-ranked immediately. Rapid duplicate
taps of the same answer are deduplicated so UI noise cannot inflate confidence.

The direct-card recommendation remains unchanged. Ambiguous/forked merchant outcomes do not surface
an alternate route in V1 because the destination coding has not settled.

## Merchant graph integration

Implemented flow:

```
route requirement: grocery + MCC 5411
                          |
                          v
MapKit nearby places -> canonical 500-merchant seed
                          |
                          v
seed prior + public evidence + reconciled owner MCC evidence
                          |
                          v
MerchantMCCGraph prediction + confidence
                          |
                          v
location-specific gift-card inventory evidence
                          |
                          v
actual merchant network acceptance -> RecommendationEngine
```

Canonical MCC graph data remains under `contracts/merchant-mcc-graph/`. Store packages
byte-identical runtime copies through `scripts/sync-merchant-mcc-graph-into-store.sh`; a test fails
if those copies drift.

## Inventory graph

MCC qualification is **not** gift-card inventory evidence. `GiftCardInventoryGraph` therefore
requires physical identity: an exact Apple place id when both sides have one, or a close coordinate
match as fallback. Brand-only observations are ignored.

Evidence fields include:

- merchant/location identity;
- target gift-card/instrument key;
- `available` / `unavailable`;
- source (`ownerConfirmed`, `retailerConfirmed`, `communityObserved`);
- source confidence;
- observation timestamp and optional source reference.

Inventory is volatile, so freshness is asymmetric:

- a positive sighting decays over weeks (30-day half-life);
- a negative sighting decays quickly (3-day half-life), because "not here" may be a temporary
  stockout rather than a permanent merchandising decision.

A recent actionable positive sighting outranks a closer store with unknown inventory. A sufficiently
strong recent negative observation temporarily suppresses that exact location. Neither changes the
merchant's MCC prediction.

Owner feedback is kept in a small versioned local append-only envelope rather than changing the
SwiftData purchase schema. This avoids a migration of durable financial history for volatile rack
inventory, while keeping the observation shape ready for a future opt-in, de-identified community
aggregator. Community upload is **not implemented yet**.

## Expansion path

The same model should later support:

1. **Opt-in community inventory aggregation** — de-identified location/instrument observations.
2. **Cashback portals** — portal -> merchant -> card.
3. **Payment intermediaries** — intermediary fee vs incremental card value.
4. **Promotions / issuer offers** — activate or route through an offer before checkout.
5. **Stacked routes** — only when each edge has evidence and the combined stack is valid.

Do not add these as special cases to `RecommendationEngine`. Add route types/legs above it.

## Files

Canonical Swift route semantics:

- `Engine/Sources/CardCopilotEngine/Engine/PurchaseRouteAdvisor.swift`
- `Engine/Tests/CardCopilotEngineTests/PurchaseRouteAdvisorTests.swift`

Store graph/runtime composition:

- `Store/Sources/CardCopilotStore/MerchantMCCGraph.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCGraphEvidenceBuilder.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCSeedCatalogue.swift`
- `Store/Sources/CardCopilotStore/GiftCardInventoryGraph.swift`
- `Store/Sources/CardCopilotStore/PurchaseRouteAcquisitionResolver.swift`
- `Store/Tests/CardCopilotStoreTests/GiftCardInventoryGraphTests.swift`
- `Store/Tests/CardCopilotStoreTests/MerchantMCCSeedCatalogueTests.swift`
- `Store/Tests/CardCopilotStoreTests/MerchantMCCSeedResourceSyncTests.swift`

Kotlin route-semantic twin:

- `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/PurchaseRouteAdvisor.kt`
- `android/core/engine/src/test/kotlin/com/cardcopilot/engine/PurchaseRouteAdvisorTest.kt`

Checkout UI:

- `App/CardCopilot/Views/RecommendationView.swift`

## Next product slice

Add a de-identified, opt-in community aggregation service for inventory observations so confirmed
availability can improve routes across devices/users while preserving location-level freshness and
keeping account/card/purchase data out of the payload.
