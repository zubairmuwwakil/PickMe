# Issuer MCC local purchase join

**Date:** 2026-09-04  
**Status:** implemented  
**Scope:** PickMe on-device MCC learning  
**Economic constraint:** recurring production data-provider cost remains **$0** unless the owner explicitly changes that decision.

## Purpose

PickMe can import a literal four-digit Merchant Category Code from an issuer-owned CSV for free. An issuer export normally proves the merchant and MCC, but it does not by itself prove which physical store the owner visited.

This design safely upgrades some imported rows from strong brand-level evidence (`ownerImportedMcc`) to location-anchored owner evidence (`directOwnerMcc`) by matching the import to a purchase that already exists on the same iPhone.

The goal is **better card decisions**, not maximizing the number of rows called exact. Ambiguous rows stay unlocated.

## Architectural invariant

An imported row may become `directOwnerMcc` only when PickMe can prove one and only one compatible local purchase with a known location.

```text
issuer CSV row
    |
    | literal MCC present
    v
canonical merchant
    |
    | transient local matching
    | merchant + date + CAD amount + network when known
    v
exactly one compatible located StoredPurchase?
    |                         |
   yes                       no / >1
    |                         |
    v                         v
directOwnerMcc          ownerImportedMcc
location anchored       brand-level only
```

There is no majority vote, nearest-match fallback, fuzzy amount match, or automatic promotion of an ambiguous result.

## Current matching contract

### Merchant

Both the imported merchant and the local purchase must resolve through the deterministic curated merchant resolver to the same canonical merchant ID.

Learned aliases are deliberately not sufficient for this promotion. A learned alias may be useful for normal recognition, but a high-trust issuer-file join should not recursively trust a prior inference to create stronger evidence.

### Location

The compatible `StoredPurchase` must already have finite latitude and longitude.

The importer does not invent a location and does not use the issuer file to create one.

Today `StoredPurchase` does not carry a verified Apple place ID, so a successful issuer join persists the purchase coordinates. If the purchase model later gains a trustworthy place ID, prefer that identifier over coordinate-only anchoring.

### Amount and currency

A direct join requires an explicit imported amount and an existing local `amountCad` within one cent.

Amount exists only as a **transient join key**. It is not copied into the MCC evidence ledger, source reference, community payload, or MCC graph.

`StoredPurchase.amountCad` is explicitly CAD, so the current implementation also requires an **explicit CAD currency field** in the issuer row before amount can participate in a location join.

Unknown currency and non-CAD currency both fail closed to `ownerImportedMcc`. A numeric `USD 42.17` must never match a local `CAD 42.17` merely because the numbers are equal.

Future non-CAD support needs a separately verified currency-normalization design; do not silently FX-convert to manufacture a match.

### Card network

If the import knows the card network, the matched local purchase must have a `cardUsedId` whose catalogue network exactly agrees.

The card ID itself is not copied into MCC evidence. The graph may retain only the normalized network (`visa`, `mastercard`, `amex`, or `discover`).

If the import does not know the network, network does not become a guessed matching requirement.

### Date

The importer distinguishes transaction-date and posting-date columns:

- transaction/date: local purchase may differ by at most **1 UTC calendar day**;
- posting/posted date: local purchase may differ by at most **4 UTC calendar days**.

These are bounded heuristics, not issuer truths. Amount + merchant + optional network + exact-one-result are what keep the wider posting window conservative.

Source-specific adapters should tighten these windows if an issuer's documented format gives better semantics.

### Uniqueness

After every applicable predicate above is evaluated:

- exactly one compatible purchase -> eligible for direct promotion;
- zero compatible purchases -> keep `ownerImportedMcc`;
- two or more compatible purchases -> keep `ownerImportedMcc`.

Never choose one ambiguous purchase by distance, order, recency, or majority vote.

## Persisted data

For a successful local join, the MCC ledger stores only the facts required by the graph:

- canonical merchant identity;
- literal MCC;
- local purchase latitude/longitude;
- in-store channel;
- optional normalized payment network;
- observation timestamp;
- evidence kind `directOwnerMcc`;
- a local idempotency/correlation reference based on non-sensitive local identifiers.

It does **not** persist from the imported file:

- amount;
- card/account number;
- raw card ID;
- raw issuer row;
- filename;
- statement text;
- balance;
- reward amount.

The raw file is read for the import operation and is not retained by the MCC learner.

## Idempotency and evidence independence

Brand-level imported evidence dedupes by non-sensitive facts:

```text
source + canonical merchant + UTC day + MCC + network
```

That prevents multiple same-day transactions from inflating a brand prior merely because the owner shopped more often.

Successfully joined evidence normally dedupes around the opaque **local purchase UUID**, allowing two genuinely distinct local purchases to become two independent direct observations without persisting amount/card details in the fingerprint.

### Cross-source dedupe with manual reconciliation

The same transaction can sometimes appear through two acquisition paths:

1. the owner already reconciled a `StoredObservation` with a literal MCC; and
2. a later issuer CSV import safely joins to that same local purchase.

If both paths report the **same literal MCC**, the imported evidence deliberately reuses the evidence-builder ID:

```text
observation:<StoredObservation UUID>
```

The graph dedupes by evidence ID, so one transaction cannot become two independent direct observations and accidentally accelerate `isTrusted`.

If the stored observation and issuer row report **different literal MCCs**, they remain distinct evidence. A disagreement is information and must remain visible rather than being hidden by dedupe.

Re-importing the same issuer file therefore does not increase confidence, and re-observing the same transaction through another local acquisition path does not manufacture corroboration.

## Location-local trust

A separate graph bug was fixed as part of this work.

`directOwnerMcc` is now allowed to count toward `directObservationCount`, `isObserved`, and `isTrusted` only when it matches the queried location by either:

1. exact Apple place ID, when both sides have one; or
2. coordinates within **75 metres**.

Direct evidence from another branch of the same chain may still weakly influence the brand-level MCC posterior, but it cannot make the current branch look observed or trusted.

This distinction is an invariant. The graph's scoring radius and its trust radius do not need to be identical.

## Checkout/category projection

Before this local-join feature existed, every issuer import projected through the category layer as `.brandPrior`, because imports were necessarily unlocated.

That is no longer correct for a safely joined row.

Current rule:

```text
graph winner has location-matched direct evidence
+ category posterior is not conflicted
    -> ConfidenceSource.observedMcc
    -> raw state merchantMccGraph:ownerLocatedExact

unlocated issuer evidence
    -> ConfidenceSource.brandPrior
    -> raw state merchantMccGraph:ownerImportedExact
```

Community evidence alone can never create `.observedMcc`.

A safely joined literal MCC uses the normal observed-MCC confidence floor while still allowing stronger repeated graph corroboration to raise confidence.

## Confidence semantics

A single successful issuer-file join becomes location-anchored direct evidence, but the graph still applies its normal confidence rules.

`isTrusted` remains reserved for repeated independent direct evidence plus sufficient aggregate confidence. One joined statement row is not automatically permanent truth.

Unlocated issuer imports remain `ownerImportedMcc`, weighted strongly but below direct location evidence and unable by themselves to set `isObserved` or `isTrusted`.

## Community boundary

A local issuer-file join does **not** automatically upload anything to the community MCC service in this slice.

If community sharing is extended later, it must still obey the existing independent opt-in and privacy contract. Do not turn importing a private issuer file into implicit community contribution.

## Failure behavior

The importer fails closed in all of these cases:

- missing amount for a proposed location join;
- missing/unknown currency;
- non-CAD currency;
- known network mismatch;
- no local purchase location;
- merchant does not deterministically resolve;
- date outside the source window;
- amount differs by more than one cent;
- zero matches;
- multiple matches.

Failing closed means **retain the literal MCC as `ownerImportedMcc` when otherwise valid**, not discard useful evidence and not guess a store.

## Files

Primary implementation:

- `Store/Sources/CardCopilotStore/MerchantMCCExactImport.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCGraph.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCGraphResolution.swift`
- `App/CardCopilot/Views/SettingsView.swift`

Consumers:

- `Store/Sources/CardCopilotStore/PurchaseRouteAcquisitionResolver.swift`

Tests:

- `Store/Tests/CardCopilotStoreTests/MerchantMCCExactImportTests.swift`
- `Store/Tests/CardCopilotStoreTests/MerchantMCCImportedJoinProjectionTests.swift`
- `Store/Tests/CardCopilotStoreTests/MerchantMCCGraphTests.swift`
- `Store/Tests/CardCopilotStoreTests/MerchantMCCLearningEraseTests.swift`

Related decisions:

- `docs/research/2026-09-04-free-production-mcc-sources.md`
- `docs/superpowers/specs/2026-09-04-merchant-mcc-production-architecture-design.md`

## Replacement and extension criteria

This implementation is not sacred. Future agents should replace or tighten it when a demonstrably better free path exists.

Preferred upgrades, in order:

1. **Verified issuer transaction identifier** — if an export exposes a stable transaction ID that can be safely joined to locally captured data, prefer it over heuristics.
2. **Verified Apple place ID on StoredPurchase** — persist/use it when the purchase was actually resolved to that MapKit place; prefer exact place identity over coordinate radius.
3. **Source-specific adapters** — use documented issuer currency/date/network semantics instead of generic column inference.
4. **Explicit non-CAD design** — support non-CAD issuer amounts only after a design can prove semantic equivalence with the local purchase; never silently convert to manufacture a match.
5. **Aggregate join diagnostics** — measure eligible rows, joined rows, ambiguous rows, missing-location rows, network mismatches, and currency mismatches locally without recording merchant/amount/card details in analytics.
6. **Stronger matching model only if measurements justify it** — a probabilistic matcher is acceptable only if it has a calibrated false-positive bound and still refuses unsafe promotions.

## Rollback triggers

Disable direct promotion and retain imports as `ownerImportedMcc` only if any of the following are observed:

- a confirmed false location join;
- repeated owner-vs-import conflicts at matched locations;
- issuer export semantics change without a verified adapter update;
- the matching implementation begins requiring persistent sensitive transaction fields;
- instrumentation shows that direct promotion rarely changes card decisions enough to justify its complexity.

The safe fallback is always available: literal issuer MCC remains useful as unlocated owner evidence.

## Guiding rule for future agents

**Optimize the correctness of the card recommendation, not the percentage of imports that become direct evidence.**

A row left unlocated is cheap uncertainty. A falsely location-anchored row can become trusted and poison future recommendations. When in doubt, keep the weaker evidence class.
