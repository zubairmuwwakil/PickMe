# Purchase Route Optimizer — design

**Status:** V1 route core, nearby MCC resolution, local/community inventory learning, community MCC
learning, and protection-aware route verdicts implemented 2026-09-04.

**Companion decision spec:**
[`2026-09-04-purchase-decision-architecture-design.md`](2026-09-04-purchase-decision-architecture-design.md)

## Problem

Checkout answers a local question well: given the merchant/category in front of the owner, which
owned card has the highest defensible reward/credit decision value?

That is not always the globally best purchase path. The owner may be able to:

- buy a merchant gift card at a higher-earning merchant;
- enter through a cashback portal;
- use a payment intermediary;
- activate an issuer/merchant promotion;
- combine several valid route legs.

These are alternate **purchase routes**, not new card reward rules.

## Architectural boundary

`RecommendationEngine` remains the sole authority for which owned card wins each card-funded leg.
It must not absorb gift-card hacks, portal routing, inventory, or route-specific assumptions.

```text
purchase goal
  |
  +-- direct route --------------------> RecommendationEngine
  |
  +-- alternate route
       |
       +-- acquisition/funding leg ----> RecommendationEngine
       +-- merchant/MCC evidence ------> MerchantMCCGraph
       +-- inventory evidence ---------> GiftCardInventoryGraph
       +-- protection effect ----------> ProtectionDecisionAdvisor
```

`PurchaseRouteAdvisor` compares route reward economics after fees/friction and carries protection as
an independent decision attribute. It does not assign an invented cash value to insurance.

## V1 route

The first generic route template is:

- destination aliases: Shoppers Drug Mart / Shoppers / Pharmaprix;
- instrument: Shoppers Drug Mart gift card;
- acquisition requirement: eligible grocery merchant coding MCC 5411;
- route evidence: `communityObserved`;
- protection effect: `replacesDestinationCardCharge`.

The acquisition card is never hard-coded. The ordinary recommendation engine picks the best owned
card for the actual acquisition merchant/context.

## Reward/friction gate

A route must clear both:

- at least CAD $1 incremental reward/credit value; and
- at least 1 percentage point incremental return.

This gate is intentionally stricter than switching cards at the same till because alternate routes
can add travel, another checkout, inventory uncertainty, stored-value handling, or other friction.

The numeric route advantage remains **reward economics only**:

```text
acquisition decision value
- fixed route fee
- estimated route friction
- direct decision value
= reward advantage
```

Protection does not add/subtract a fabricated CAD amount. It changes the route verdict.

## Protection-aware route verdict

Routes declare whether they preserve or replace the destination credit-card charge:

- `preservesDestinationCardCharge`
- `replacesDestinationCardCharge`

For a replacing route, `ProtectionDecisionAdvisor` checks the direct reward winner's trusted
shopping benefits when the benefits catalogue is available.

The route result is then one of:

- `rewardAdvantage` — no material trusted protection trade-off identified;
- `rewardProtectionTradeoff` — reward advantage exists, but the alternate funding path may change
  relevant card-linked protection or PickMe needs purchase-item context.

The checkout UI must therefore say **extra rewards**, not generic **extra value**, when protection is
unresolved. For material gift-card routes it renders:

> MORE REWARDS — PROTECTION TRADE-OFF

and routes the owner into the existing protection lens for electronics, phone, or appliance/furniture
context rather than guessing what was purchased from the merchant MCC.

See the companion purchase-decision spec for the rationale and future replacement rules.

## Evidence axes

Route quality is intentionally not one confidence number. Different facts use different evidence
systems.

### 1. Route provenance

- `retailerConfirmed`
- `communityObserved`
- `experimental`

This answers: how well do we know the route itself exists/works?

### 2. Merchant MCC evidence

`MerchantMCCGraph` combines:

- canonical 500-merchant seed priors;
- external/public evidence;
- owner-reconciled MCC observations;
- opt-in anonymous community MCC aggregates.

Owner-observed/reconciled evidence remains stronger than seed/community priors. A category outcome
does not fabricate an MCC.

### 3. Gift-card inventory evidence

`GiftCardInventoryGraph` answers a different question: does this **exact physical location** appear
to stock the target gift card?

Physical identity requires Apple place id when available, otherwise a close coordinate fallback.
Brand-only inventory claims are ignored.

Sources include:

- owner-confirmed;
- retailer-confirmed;
- community-observed.

Freshness is asymmetric:

- positive sighting half-life: ~30 days;
- negative sighting half-life: ~3 days.

A recent `Not here` suppresses only that location temporarily. It never changes MCC.

### 4. Protection evidence

Protection comes from the existing certificate-backed benefits catalogue and its verification
status. Stub benefits do not become trusted decision facts.

## Nearby route resolution

The implemented physical flow is:

```text
route requires grocery + MCC 5411
              |
              v
MapKit nearby physical places
              |
              v
safe canonical merchant resolution
              |
              v
seed + public + owner + community MCC evidence
              |
              v
MerchantMCCGraph prediction
              |
              v
location-specific inventory graph
              |
              v
actual network acceptance
              |
              v
RecommendationEngine for acquisition leg
              |
              v
reward threshold + protection verdict
```

A candidate must resolve safely to a canonical merchant, satisfy the route-required MCC prediction,
retain real network acceptance, and still clear the route reward threshold.

After a successful nearby scan, if no physical candidate qualifies, the generic placeholder is
suppressed instead of encouraging the owner to hunt for an unspecified store.

## Inventory feedback and learning

At a physical route candidate the owner can tap:

- **Found it**
- **Not here**

The observation is written locally, de-duplicated against rapid repeat taps, and the route list is
re-ranked immediately.

Community inventory sharing is implemented as an explicit opt-in feature and is off by default.
The shared payload is deliberately narrow: store/location identity, target gift-card instrument,
availability, observed time, and random observation id. It does not include card, amount, purchase
history, account/email, or device identity.

MoneyTalks/In Unity stores the anonymous community observations and returns bounded daily aggregates.
PickMe continues to own confidence/freshness semantics.

## Community MCC learning

A parallel opt-in anonymous pipeline exists for explicit/reconciled merchant MCC observations.
PickMe queues retry-safe reports, the backend applies privacy/evidence caps, and aggregate evidence
feeds back into the runtime merchant graph as lower-trust external evidence.

This keeps the system continuously learning without allowing one anonymous report to become payment-
network truth.

## Current data/storage boundaries

- canonical merchant seed/graph: `contracts/merchant-mcc-graph/`;
- packaged Store copies: `Store/Sources/CardCopilotStore/Resources/merchant-mcc-*`;
- local owner inventory feedback: versioned local append-only envelope;
- community inventory + MCC rows: anonymous In Unity backend tables;
- card reward/benefit facts: existing PickMe contracts/catalogues.

Do not create a second rewards calculator or a second benefits truth source inside routing.

## Expansion path

The route abstraction should next grow through additional route types, not merchant-specific hacks:

1. cashback portals / Rakuten-style routes;
2. issuer/merchant offers;
3. payment intermediaries and their fees;
4. credits / prepaid balances;
5. stacked routes where every edge is independently valid;
6. learned route completion/reliability once there is enough consented outcome data.

Each route type should declare, at minimum:

- funding legs;
- fees/friction;
- evidence/provenance;
- merchant/payment constraints;
- whether the destination card charge is preserved/replaced;
- any inventory/activation prerequisite.

## Future-proofing rule

This V1 architecture is not sacred. A future agent should replace pieces when a better solution is
more correct, evidence-backed, scalable, private, and high-ROI.

Do **not** preserve the implementation merely because this document exists. Preserve the invariants:

- issuer facts stay issuer facts;
- observations carry provenance;
- reward economics remain deterministic underneath learned layers;
- unknown/conflict states are representable;
- a learned/community signal cannot silently become stronger than trusted owner/issuer evidence;
- final decisions remain explainable.

For changes to reward + protection decision semantics, follow the migration protocol in the companion
purchase-decision architecture spec and version the policy.

## Canonical files

Swift route semantics:

- `Engine/Sources/CardCopilotEngine/Engine/PurchaseRouteAdvisor.swift`
- `Engine/Sources/CardCopilotEngine/Engine/ProtectionDecisionAdvisor.swift`
- `Engine/Tests/CardCopilotEngineTests/PurchaseRouteAdvisorTests.swift`

Kotlin twin:

- `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/PurchaseRouteAdvisor.kt`
- `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/ProtectionDecisionAdvisor.kt`
- `android/core/engine/src/test/kotlin/com/cardcopilot/engine/PurchaseRouteAdvisorTest.kt`

Store/runtime evidence:

- `Store/Sources/CardCopilotStore/MerchantMCCGraph.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCGraphEvidenceBuilder.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCSeedCatalogue.swift`
- `Store/Sources/CardCopilotStore/GiftCardInventoryGraph.swift`
- `Store/Sources/CardCopilotStore/PurchaseRouteAcquisitionResolver.swift`
- community inventory/MCC client and cache files under `Store/Sources/CardCopilotStore/`.

Checkout UI:

- `App/CardCopilot/Views/RecommendationView.swift`
- `App/CardCopilot/Views/BenefitsDisclosureSection.swift`

## Next highest-ROI route work

After this protection-aware slice is stable in CI, the next route type should be chosen by expected
coverage and implementation leverage. Cashback portals / issuer offers are strong candidates because
they reuse the same reward, evidence, activation, and final-decision layers without requiring a new
merchant truth system.
