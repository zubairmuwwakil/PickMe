# Purchase Route Optimizer — design

**Status:** V1 semantic core + checkout UI implemented 2026-09-04.

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

The route deliberately does **not** claim that a specific Metro/Sobeys/FreshCo/etc. location stocks
the card. That belongs to merchant-location evidence and eventually the merchant/MCC graph.

The card is also not hard-coded. If MBNA, Cobalt, or another owned card is worth more on the
acquisition leg, the normal recommendation engine chooses it.

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

## Checkout UI

For a single checkout recommendation, PickMe evaluates matching alternate routes using a separate
`RecommendationEngine` instance with merchant-specific checkout credits disabled for the generic
acquisition leg. When a route clears the friction gate, the recommendation screen shows a compact
**Potentially better route** card containing:

- acquisition instruction;
- the owned card chosen for that acquisition leg;
- incremental CAD value over the direct route;
- evidence label and disclosure.

The direct-card recommendation remains unchanged. Ambiguous/forked merchant outcomes do not surface
an alternate route in V1 because the destination coding has not settled.

## Expansion path

The same model should later support:

1. **Gift-card routes** — acquire destination stored value at a better reward category.
2. **Cashback portals** — portal -> merchant -> card.
3. **Payment intermediaries** — intermediary fee vs incremental card value.
4. **Promotions / issuer offers** — activate or route through an offer before checkout.
5. **Stacked routes** — only when each edge has evidence and the combined stack is valid.

Do not add these as special cases to `RecommendationEngine`. Add route types/legs above it.

## Merchant graph integration

The merchant/MCC graph should eventually answer the acquisition feasibility question:

```
route requirement: grocery + MCC 5411 + Amex accepted + target gift card observed
                          |
                          v
merchant graph: nearby terminals ranked by confidence/freshness
```

That turns the V1 generic instruction ("an eligible grocery store") into nearby actionable options
without hard-coding chain-wide assumptions.

## Files

Canonical Swift semantics:

- `Engine/Sources/CardCopilotEngine/Engine/PurchaseRouteAdvisor.swift`
- `Engine/Tests/CardCopilotEngineTests/PurchaseRouteAdvisorTests.swift`

Kotlin twin:

- `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/PurchaseRouteAdvisor.kt`
- `android/core/engine/src/test/kotlin/com/cardcopilot/engine/PurchaseRouteAdvisorTest.kt`

Checkout UI:

- `App/CardCopilot/Views/RecommendationView.swift`

## Next product slice

Connect route acquisition requirements to the merchant/MCC graph so PickMe can replace the generic
"eligible grocery store" instruction with nearby, freshness-ranked stores where the required gift
card has actually been observed. Keep inventory confidence separate from MCC confidence.
