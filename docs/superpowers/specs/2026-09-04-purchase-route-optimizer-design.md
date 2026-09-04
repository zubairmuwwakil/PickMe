# Purchase Route Optimizer — design

**Status:** V1 semantic core + nearby MCC-graph checkout UI implemented 2026-09-04.

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
actual merchant network acceptance -> RecommendationEngine
```

Canonical graph data remains under `contracts/merchant-mcc-graph/`. Store packages byte-identical
runtime copies through `scripts/sync-merchant-mcc-graph-into-store.sh`; a test fails if those copies
drift.

## Inventory boundary

MCC qualification is **not** gift-card inventory evidence. V1 can say that a nearby Metro/Sobeys/etc.
is a plausible MCC-5411 acquisition merchant, but it does not claim that a particular location
currently has a Shoppers gift card in stock. The route disclosure explicitly requires availability
to be confirmed.

Gift-card inventory should become its own evidence edge later, with source, location, confidence,
and freshness. It must not be inferred from MCC or chain identity.

## Expansion path

The same model should later support:

1. **Gift-card inventory evidence** — location-specific observations with freshness/confidence.
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
- `Store/Sources/CardCopilotStore/PurchaseRouteAcquisitionResolver.swift`
- `Store/Tests/CardCopilotStoreTests/MerchantMCCSeedCatalogueTests.swift`
- `Store/Tests/CardCopilotStoreTests/MerchantMCCSeedResourceSyncTests.swift`

Kotlin route-semantic twin:

- `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/PurchaseRouteAdvisor.kt`
- `android/core/engine/src/test/kotlin/com/cardcopilot/engine/PurchaseRouteAdvisorTest.kt`

Checkout UI:

- `App/CardCopilot/Views/RecommendationView.swift`

## Next product slice

Add a location-specific **gift-card inventory evidence edge** so a route can distinguish
"nearby merchant likely codes 5411" from "this exact location recently had the target gift card in
stock." Keep inventory confidence/freshness separate from MCC confidence.
