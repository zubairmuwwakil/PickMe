# Merchant MCC learning — production architecture and future handoff

**Date:** 2026-09-04  
**Status:** implemented, production-connected, intentionally replaceable  
**Primary semantic owner:** PickMe `Store/`  
**Canonical seed:** `contracts/merchant-mcc-graph/`  
**Community server:** [In Unity/MoneyTalks decision record](../../../../MoneyTalks/docs/decisions/2026-09-04-community-merchant-mcc.md)

This is the authoritative client-side handoff for merchant identity, MCC evidence
semantics, trust, and the resolver. It complements the original graph/seed
design in `2026-09-04-merchant-mcc-graph-seed-design.md`. The MoneyTalks
[decision record](../../../../MoneyTalks/docs/decisions/2026-09-04-community-merchant-mcc.md)
owns the anonymous community network, privacy contract, storage, retention, and
abuse model; its [runbook](../../../../MoneyTalks/docs/runbooks/community-merchant-mcc.md)
owns server operations. This document supersedes only stale client-facing
community-backend statements in the original design.

The purpose of this document is not to freeze today's implementation. It separates:

- **invariants that protect correctness/privacy**, from
- **implementation choices that future agents should replace when a higher-ROI solution is proven**.

## Executive summary

PickMe now has four evidence layers that converge on one Store-side `MerchantMCCGraph`:

```text
1. editorial seed priors
2. learned merchant identity / aliases
3. direct owner MCC + bounded reward/category evidence
4. opt-in community MCC evidence
        |
        v
MerchantMCCGraph
        |
        +--> normal checkout category/card decision
        |
        +--> Purchase Routes acquisition-MCC checks
```

There is still only **one MCC resolver**. The system is local-first: community/network failure cannot make PickMe unable to recommend a card.

The initial 500-merchant Canada graph is a cold-start prior, not a product ceiling and not payment-network truth.

## Current end-to-end flow

### A. Merchant identity

PickMe first tries deterministic curated/canonical identity:

```text
Wallet/MapKit merchant string
    -> MerchantRecognizer / curated match keys
    -> MerchantMCCSeedCatalogue canonical match
```

If deterministic matching does not resolve the Wallet descriptor, the local identity learner can add a conservative exact normalized alias after repeated evidence.

### B. Wallet checkout identity learning

A strict automatic Wallet-to-checkout join can teach a descriptor alias when:

- the automatic capture succeeded;
- the matched checkout already has a deterministic canonical seed merchant anchor;
- the Wallet event supplies a stable event ID;
- replayed events do not count twice.

An alias needs at least **two independent source fingerprints** before it becomes actionable.

If observations conflict across canonical merchants, the learner fails closed rather than majority-voting its way into a potentially wrong global identity.

Learned aliases cannot shadow deterministic curated/seed matches.

### C. GPS + MapKit identity learning

A Wallet descriptor can also learn from an already-successful high-confidence nearby MapKit resolution.

The learning hook happens **after** `resolveWalletMerchant` accepts the nearby merchant. The GPS/MapKit path therefore does not weaken the existing distance/name/category gate just to collect training data.

The MapKit merchant must deterministically resolve into the canonical seed catalogue before it can teach the Wallet alias.

The same minimum-observation rule remains in effect: one GPS event is evidence, not activation.

### D. MCC evidence

Once merchant identity is canonicalized, the graph combines:

- researched seed priors;
- direct owner literal MCC observations;
- reward/category inference that narrows but does not fabricate exact MCC;
- scoped community evidence.

Direct owner literal MCC is the strongest evidence class.

Trusted terminal truth still requires repeated direct owner MCC observations.

### E. Community sharing

If the user explicitly opts in, **only** a reconciled literal MCC can enter the
local retry queue and be uploaded opportunistically. When sharing is disabled,
PickMe clears that queue and its community cache; local learning remains enabled.
Network failure is opportunistic and a still-fresh local cache may remain usable.
Retries are idempotent through the observation UUID; a duplicate upload is a
successful outcome, not an error.

The [server decision](../../../../MoneyTalks/docs/decisions/2026-09-04-community-merchant-mcc.md#privacy-and-anonymous-network-contract)
defines the payload, anonymous boundary, location bucket, retention, and abuse
controls. The service returns aggregate evidence only; PickMe maps it only to
`externalLocationReport`.

### F. Recommendation consumption

Both ordinary checkout recommendations and Purchase Routes consume the same MCC graph. Purchase Routes does not maintain a second merchant-MCC truth system.

Gift-card inventory remains a separate axis: “merchant likely codes as grocery” and “gift card is in stock” are independent claims.

## Non-negotiable semantic invariants

A future agent may replace almost every implementation detail below, but should not break these without an explicit architecture/product decision.

1. **Seed MCCs are priors, never direct observations.**
2. **Category/reward feedback cannot fabricate a literal four-digit MCC.**
3. **Only a source that genuinely supplies a literal MCC may create direct observed-MCC evidence.**
4. **Community evidence stays weaker than direct owner evidence.**
5. **Community evidence cannot by itself produce `.observedMcc`, `isTrusted`, or terminal truth.**
6. **Merchant identity and MCC inference remain separate concepts.**
7. **Location and channel variation must remain representable.**
8. **Conflicting evidence is retained or auditable rather than overwritten.**
9. **Purchase Routes and normal checkout use the same MCC resolver.**
10. **Local recommendations continue working without community/network access.**
11. **There is one authoritative runtime MCC resolver. Replace it; do not add a permanent second one.**
12. **Existing evidence must not become stronger merely because storage/model technology changes.**

## Replacement standard

The following eight cross-boundary invariants are the replacement standard. They
are intentionally explicit because a seemingly better resolver or backend can
otherwise erode trust semantics:

1. PickMe still owns card/MCC trust semantics.
2. Literal observed MCC remains distinguishable from inferred/category/seed evidence.
3. Community evidence cannot silently become direct-owner truth.
4. Merchant/location/channel variation remains representable.
5. Local PickMe recommendations continue to work when the network is unavailable.
6. Existing evidence is migrated with provenance and without silently increasing its strength.
7. Privacy impact is no worse without an explicit product/privacy decision.
8. There is one authoritative MCC resolver, not parallel competing truth systems.

The server-specific controls that uphold item 7 are authoritative in the
[MoneyTalks decision record](../../../../MoneyTalks/docs/decisions/2026-09-04-community-merchant-mcc.md).

## Why the current choices were made

### One Store-side graph

**Why:** Store already owns local persistence, merchant identity, capture/reconciliation, nearby merchant composition, and community cache. Keeping MCC inference there avoids duplicated truth.

**Future freedom:** promote the resolver into a shared cross-platform Engine or service if iOS/Android/server parity becomes materially valuable. Do it as a migration, not by leaving two live resolvers.

### Conservative exact learned aliases

**Why:** descriptor learning is high leverage but a wrong merchant identity poisons every downstream MCC/card decision. Requiring repeated exact normalized aliases and failing closed on conflicts buys precision with little complexity.

**Future freedom:** replace with a stronger entity-resolution model, embeddings, processor IDs, or a canonical merchant service when measured precision/recall is better. Preserve deterministic curated precedence and explainable provenance.

### GPS learns only after MapKit already passed the existing gate

**Why:** learning should consume trustworthy product decisions; it should not loosen product decisions in order to manufacture training data.

**Future freedom:** improve the MapKit matching algorithm independently. If a superior place/entity matcher exists, feed its accepted identity into the same evidence boundary.

### Two independent local observations before alias activation

**Why:** one descriptor event is too easy to misjoin, while two independent successful events sharply reduce accidental activation.

**Not sacred:** tune the threshold from measured precision/recall. High-confidence processor IDs may justify one observation; noisier sources may require more.

### Community server choices

The anonymous-network boundary, coarse location bucket, contributor-privacy
tradeoffs, retention, aggregation, and the unresolved global `MerchantAlias`
question belong to the [MoneyTalks decision record](../../../../MoneyTalks/docs/decisions/2026-09-04-community-merchant-mcc.md).
PickMe consumes its returned evidence under the semantic invariants above rather
than duplicating a second server policy here.

### Community evidence — deliberate deferral

**Do not invest further in the community layer yet.** The authoritative
[MoneyTalks decision](../../../../MoneyTalks/docs/decisions/2026-09-04-community-merchant-mcc.md#explicit-decision--do-not-invest-further-in-community-evidence-yet)
records the full reasoning and server-side deferrals. Its three-distinct-UTC-day
publication threshold combines with PickMe's weaker-than-direct-owner
`externalLocationReport` consumption such that a single contributor gets no
user-visible value: after three separate visits, they already hold stronger
direct owner evidence.

Reopen community work only when privacy-safe client telemetry shows multiple
opted-in users contributing to or receiving published evidence that changes or
could change recommendations, or when abuse is observed. That does not make the
anonymous service a proof of independent contributors. Until then, defer
spatial-bucket changes, abuse hardening, threshold/cap tuning, network-specific
aggregation, rollups/materialized aggregates, and retention tuning. The
high-ROI work meanwhile is **not** community tuning; it is statement import
that acquires exact owner MCC.

### No mandatory bank linking

**Why:** PickMe remains useful with Wallet/reconciliation and avoids onboarding friction plus provider dependence.

**Not a permanent rejection:** an automatic provider returning real ISO MCC may be one of the highest-ROI upgrades once Canadian issuer coverage, cost, privacy, and consent UX are proven.

## Known limitations as of 2026-09-04

These are not bugs to hide; they are decision inputs for future work.

### The weighted graph is heuristic, not statistically calibrated yet

Evidence weights and confidence math are policy defaults. They should be tuned from field outcomes rather than defended because they shipped first.

### Initial merchant coverage is 500 Canadian merchants

The seed is useful but finite. Expansion should preserve stable canonical IDs so existing observations continue to join correctly.

### Local lightweight persistence has a scale ceiling

UserDefaults-style caches/queues are appropriate for the current evidence volume, but SwiftData/SQLite or another versioned store may become more operationally appropriate as history and migrations grow.

### Exact MCC observations remain the scarce signal

Identity learning can become excellent while the MCC itself remains a prior. More exact-MCC acquisition may eventually provide greater ROI than better identity math.

## Highest-ROI next work

This ranking is a recommendation, not a promise. Future agents should re-rank it using real usage data.

### P0 — measure decision quality before making the model smarter

Instrument privacy-safe aggregate quality signals:

- seed-only vs learned prediction coverage;
- learned alias activation/conflict rate;
- direct-owner vs community disagreement rate;
- community coverage by merchant/location;
- how often MCC uncertainty changes the winning card;
- confidence calibration;
- recoding/stale-evidence rate;
- reward-feedback completion/skip rate.

The key metric is not “how many MCCs did we predict?” It is **how often better evidence changed a card decision correctly**.

A more sophisticated ML model is low ROI until there is enough labeled outcome data to show the heuristic is the bottleneck.

### P0/P1 — evaluate automatic literal-MCC sources

Run a focused Canadian proof-of-concept across the issuers/cards PickMe users actually hold.

Compare:

- Plaid;
- MX;
- Canadian consumer-driven banking/open-banking providers;
- issuer APIs/data exports;
- statement/file import;
- processor/network sources where legally/licensably available.

For each, measure:

- percentage of target institutions returning literal ISO MCC;
- latency/freshness;
- account-linking friction;
- consent scope;
- cost per active user/observation;
- reliability;
- data-retention burden.

Treat the winner as another `MerchantMCCEvidence` provider. Do not make one vendor the domain model.

### P1 — explicit recoding/change detection

When recent strong direct evidence disagrees with an older strong posterior, confidence should fall quickly instead of waiting for slow decay.

Possible future approaches:

- shorter conflict half-life;
- change-point detection;
- recent-window posterior;
- brand/location “recode suspected” state.

Measure first; do not add complexity until real recodes appear.

### P1 — hand off server-side abuse hardening when warranted

If community evidence begins affecting many decisions or abuse appears, use the
[MoneyTalks decision](../../../../MoneyTalks/docs/decisions/2026-09-04-community-merchant-mcc.md#abuse-controls-and-honest-limits)
for the privacy-preserving hardening order. PickMe's job is to measure whether
the community signal changed a decision and preserve its weaker trust class.

### P1/P2 — hierarchical learning after enough data exists

A likely scalable model is:

```text
brand
  -> region
    -> location
      -> network
        -> channel
```

New locations could borrow brand priors while direct local evidence can diverge.

A hierarchical Bayesian model may be a better long-term fit than hand-tuned weights, but only after enough observations exist to calibrate it.

### P2 — expand beyond 500 merchants

Expand additively with stable IDs. Avoid rebuilding the catalogue in a way that strands learned evidence.

### P2 — graduate local persistence when operational pain appears

Move alias/evidence/cache state to SwiftData/SQLite when migrations, queryability, volume, or debugging make lightweight stores costly.

## What future agents are explicitly free to change

Change any of these when a demonstrably better solution exists:

- merchant entity-resolution algorithm;
- alias activation threshold;
- graph/scoring math;
- confidence calibration;
- evidence weights;
- decay/half-life logic;
- local persistence technology;
- exact-MCC data provider;
- merchant catalogue size;
- on-device vs server-side inference placement.

Do not preserve a mediocre choice because it appears in this document.

## Replacement test

Before replacing a major part, answer:

1. What measured problem does the replacement solve?
2. Does it improve accuracy, coverage, latency, reliability, privacy, cost, or user friction enough to justify migration?
3. Does it preserve literal-vs-inferred evidence provenance?
4. Can it represent location/channel/network variation?
5. Are contradictory observations retained or auditable?
6. Can current evidence migrate without silently gaining confidence?
7. Does PickMe still work offline/backend-down?
8. Does community remain weaker than owner-direct truth unless an explicit product decision changes that?
9. Is there still one authoritative MCC resolver?
10. Are new privacy/data-retention costs understood and documented?

If those answers are good and ROI is materially better, replace the current implementation and update this document.

## Implementation map

### Seed and validation

- `contracts/merchant-mcc-graph/`
- `contracts/merchant-pack.json`
- `scripts/validate-merchant-mcc-graph.py`
- `scripts/sync-merchant-mcc-graph-into-store.sh`

### Identity

- `Store/Sources/CardCopilotStore/MerchantRecognizer.swift`
- `Store/Sources/CardCopilotStore/MerchantIdentity.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCSeedCatalogue.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCIdentityLearningStore.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCGPSIdentityLearner.swift`
- `Store/Sources/CardCopilotStore/DiscoveredMerchantResolution.swift`
- `Store/Sources/CardCopilotStore/AutoCaptureLog.swift`
- `Store/Sources/CardCopilotStore/CheckoutService.swift`

### MCC evidence and graph

- `Store/Sources/CardCopilotStore/MerchantMCCGraph.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCGraphEvidenceBuilder.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCGraphResolution.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCRewardFeedback.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCLearningStore.swift`

### Community client

- `Store/Sources/CardCopilotStore/CommunityMerchantMCC.swift`
- `Store/Sources/CardCopilotStore/CommunityMerchantMCCPendingStore.swift`
- `Store/Sources/CardCopilotStore/CommunityMerchantMCCReports.swift`
- `App/CardCopilot/Services/MerchantProvider.swift`
- PickMe community settings in app Settings integration

### Purchase Routes

- `Store/Sources/CardCopilotStore/PurchaseRouteAcquisitionResolver.swift`
- `Store/Sources/CardCopilotStore/GiftCardInventoryGraph.swift`

### Tests worth reading before changing behavior

- identity learning store tests;
- identity pipeline tests;
- GPS identity learner tests;
- MCC graph/evidence builder tests;
- community MCC tests;
- Purchase Route acquisition resolver tests;
- merchant graph validator/seed sync tests.

Use code search on current `main` rather than trusting this filename list forever; files may be renamed as the design evolves.

## Future-agent workflow

Before modifying this subsystem:

1. Read `AGENTS.md`, `REPO_MAP.md`, this document, and the original seed/graph design.
2. Inspect current `main`; multiple agents may have changed the subsystem since this document.
3. Inspect both PickMe and MoneyTalks if changing community wire/semantics.
4. Preserve semantic provenance in tests.
5. Verify normal checkout **and** Purchase Routes before changing MCC behavior.
6. Run the merchant graph validator and relevant Swift tests.
7. Let CI exercise app integration.
8. For backend changes, require the In Unity DB-backed production smoke to pass.
9. Update this document when implementation, invariants, limitations, or ROI ranking materially changes.

## Final principle

The target is **not** “the most advanced MCC prediction system.”

The target is:

> the best card decision, with honest uncertainty, low user friction, strong privacy, and evidence that gets better over time.

If a simpler system wins on those outcomes, use it. If a more scalable future architecture wins, migrate to it. Preserve provenance and trust boundaries so PickMe can evolve without losing the ability to explain why it believed a merchant would code a certain way.
