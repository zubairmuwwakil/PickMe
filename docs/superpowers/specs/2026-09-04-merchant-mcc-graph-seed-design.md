# Merchant MCC graph — seed, learning, community evidence, and future architecture

**Date:** 2026-09-04  
**Status:** implemented and intentionally evolvable  
**Owner:** `Store/` for merchant identity, evidence composition, persistence, and runtime MCC inference  
**Canonical seed:** `contracts/merchant-mcc-graph/`  
**Scope:** merchant/location/channel MCC inference for PickMe recommendations and Purchase Routes

> This document is the architecture handoff for future agents. It records what exists, why the current choices were made, what must remain true, and which parts are explicitly replaceable when a better or more scalable solution becomes available.

## Executive summary

PickMe does **not** model a merchant as `merchant -> one MCC`.

It models:

```text
merchant identity
    + location
    + channel
    + network when known
    + editorial prior
    + local owner evidence
    + explicit transaction MCC evidence
    + opt-in community evidence
        -> MCC probability distribution
        -> card reward/category rules
        -> confidence-aware purchase decision
```

The initial 500 Canadian merchants, followed by an additive cited 50-merchant US tranche, are
bootstrap priors so PickMe works on day one in both supported markets. They are never treated as
payment-network truth merely because they are bundled with the app.

The runtime now has one Store-side `MerchantMCCGraph`. Both normal checkout category resolution and Purchase Routes consume that graph. Earlier experimental Engine-side MCC posterior/runtime code was removed rather than allowing two independent truth systems to diverge.

The system is deliberately provider-agnostic at the evidence boundary. A future agent may add Plaid, MX, Canadian open-banking, issuer APIs, processor/network APIs, receipt/statement import, or a better community backend **without replacing the recommendation engine or changing the meaning of observed vs inferred evidence**.

## Non-negotiable semantic invariants

Future implementations may change algorithms, storage, providers, thresholds, or backend topology. These invariants should change only with an explicit product/architecture decision:

1. **Seed MCCs are priors, not observations.**
2. **A reward-category outcome is not a literal 4-digit MCC.** It may narrow the possible MCC set, but must not fabricate one exact code.
3. **Only a source that actually supplies a literal transaction/processor MCC may create direct observed-MCC evidence.**
4. **Brand-wide evidence must not silently become terminal/location truth.** Location identity matters because acquirer/terminal coding can vary.
5. **Channel matters.** In-store, online, and app merchant accounts may have different MCCs.
6. **Conflicting evidence is retained.** Do not overwrite history with “latest answer wins.” Disagreement should reduce confidence.
7. **Issuer reward rules remain separate from merchant MCC inference.** MCC inference answers “how is this merchant likely coded?”; card contracts answer “what does this card do with that code?”
8. **Community evidence is weaker than direct owner evidence and cannot promote itself to direct observed truth.**
9. **Local recommendations must continue working when community/network services are unavailable.**
10. **Do not create a second MCC resolver.** Replace the existing resolver if a superior model is adopted; do not run two competing systems indefinitely.

## Why this architecture exists

### The core problem

MCC is assigned to a merchant account/terminal by the acquiring side of the payment system. A national chain can therefore appear under different MCCs by location, merchant-of-record, network, channel, or business line.

Apple Wallet/Shortcuts currently gives PickMe useful transaction context, but it does **not** expose a public API that reliably supplies the payment-network MCC. MapKit POI categories are useful classification evidence, but are not MCC ground truth.

Therefore PickMe needs two things at once:

- enough seed data to recommend immediately;
- a learning system that can supersede the seed as real evidence arrives.

### Why not just keep a dictionary?

A flat `merchant -> MCC` dictionary is cheap but creates false certainty. It cannot represent:

- two Walmart locations with different coding;
- storefront vs online checkout differences;
- conflicting community observations;
- a weak editorial guess being replaced by a direct transaction MCC;
- several possible MCCs that all produce the same best-card answer.

The graph/distribution approach costs slightly more complexity but prevents the recommendation engine from baking uncertainty into permanent “truth.”

## Canonical ownership and data flow

The authoring path is:

```text
contracts/merchant-mcc-graph/
    manifest.json
    profiles.json
    observations.json
    merchants-001-050.json ... merchants-451-500.json
            |
            | scripts/sync-merchant-mcc-graph-into-store.sh
            v
Store/Sources/CardCopilotStore/Resources/merchant-mcc-*
            |
            v
MerchantMCCSeedCatalogue
            |
            v
MerchantMCCGraph
```

`contracts/merchant-mcc-graph/` is the only canonical home for seed data. Store resource files are packaging copies and must not be independently authored.

The CI gate runs `scripts/validate-merchant-mcc-graph.py`, which protects the 50-row shard shape,
IDs, country-scoped display identity, US citations, profile references, candidate/weight validity,
confidence bounds, and location-scoped public evidence rules.

## Seed design

### Merchant scope

The graph began with the 500 Canadian merchants supplied in
`pickme_canada_500_merchant_seed(1).xlsx`. It now adds a cited 50-merchant US shard without
renumbering, replacing, or reusing any Canadian ID.

This list is the bootstrap coverage set, **not** a permanent product limit. A future agent may
expand beyond 550 merchants, but should preserve stable merchant IDs and migrate the seed contract
deliberately rather than quietly replacing identities. Country is part of canonical identity: when
a same-named cross-border brand is separately seeded, country-aware resolution selects it from the
physical merchant location and unknown-country matches fail closed.

### MCC taxonomy

The taxonomy seed references the Adyen DABstep MCC data (CC-BY-4.0). Public MCC-directory examples are kept only as low-confidence external/location evidence; they are not copied wholesale into PickMe as authoritative truth.

### Weighted priors

Each seed profile may contain multiple candidate MCCs plus weights. Runtime uses the full distribution rather than discarding all but the primary MCC.

The profile confidence is the **total strength of the editorial prior**. Candidate weights distribute that strength. Adding six possible MCCs must not make a prior six times stronger than a one-MCC profile.

This matters because uncertainty in the source data should remain uncertainty in the runtime model.

## Merchant identity and descriptor matching

Identity resolution uses two complementary systems:

- `contracts/merchant-pack.json` / `MerchantRecognizer` for curated statement/brand aliases;
- the country-scoped seed catalogue for canonical merchant IDs and MCC profiles.

The seed fallback supports safe normalized matching, including common descriptor suffixes for multi-word merchant names, while avoiding raw substring behavior such as matching `Metro` inside `Metropolitan Hotel`.

Do not merge merchant recognition and MCC evidence into one structure. They answer different questions:

- recognition: **which merchant is this?**
- MCC graph: **how is this merchant/location/channel likely coded?**

If merchant identity improves later (for example stronger MapKit place IDs, issuer merchant IDs, network merchant IDs, or a canonical merchant entity service), plug that improved identity into the graph query rather than replacing the graph semantics.

## Runtime evidence model

The canonical runtime evidence object is `MerchantMCCEvidence` in `Store/Sources/CardCopilotStore/MerchantMCCGraph.swift`.

Important dimensions:

```text
merchantKey
placeID?
latitude/longitude?
channel
network?
mcc?
category?
kind
sourceConfidence
observedAt
sourceReference?
```

Current evidence kinds are:

| Kind | Default graph weight | Meaning |
|---|---:|---|
| `directOwnerMcc` | 1.00 | Owner/transaction evidence supplied a literal MCC |
| `externalLocationReport` | 0.65 | External/community location-scoped MCC evidence |
| `researchedSeed` | 0.40 default | Editorial bootstrap prior; profile confidence may define actual total prior strength |
| `rewardOutcomeInference` | 0.55 total per answer | Reward result narrows MCC to a bounded set but does not reveal an exact MCC |
| `categoryOutcome` | 0.00 for exact-MCC scoring | Category truth may be useful elsewhere but cannot fabricate an MCC |

These are starting policy constants, not sacred numbers. Future agents may tune them from field data. If changed, add tests showing why the new calibration is better.

## Graph scoring

`MerchantMCCGraph.predict` is a pure resolver. Persistence lives outside it.

At a high level:

```text
score(mcc)
  = weighted editorial prior
  + matching evidence adjusted by:
      evidence kind
      source confidence
      location proximity/identity
      network match
      channel match
      evidence age

share(mcc) = score(mcc) / total score
```

Confidence uses both agreement and evidence strength. A single weak seed cannot become 100% confident merely because no competing candidate is present.

Current location behavior intentionally gives strongest weight to an exact place match, then nearby coordinate evidence, and weaker weight to brand-only evidence. Evidence also ages rather than remaining equally strong forever.

### Safe future replacement

The weighted-count model is intentionally replaceable. A future agent may adopt:

- Dirichlet/Bayesian updates;
- hierarchical Bayesian brand -> location priors;
- calibrated logistic/GBM models;
- learned embeddings plus merchant identity features;
- server-computed posteriors with an offline local fallback.

A replacement is acceptable if it preserves provenance, uncertainty, the observed/inferred distinction, and offline behavior.

## Local owner learning

### Statement reconciliation is the preferred feedback moment

The system asks for MCC-learning feedback during reconciliation rather than immediately after checkout because the issuer's posted reward result is most likely to be knowable then.

The UI defaults to **Not sure / Skip**. Quick Match does not manufacture reward evidence.

The low-friction prompt allows high-signal categories such as grocery, dining, gas, EV charging, transit, drugstore, lodging, and car rental. These categories map to bounded MCC sets.

A grocery answer, for example, is intentionally represented as several fractional MCC candidates instead of pretending that “grocery” proves MCC 5411.

### One purchase = one bounded vote

Reward feedback uses a purchase/source fingerprint. Correcting the answer replaces the prior reward-inference rows rather than counting the same purchase twice.

The total reward-outcome strength is fixed and divided across candidate MCCs. A category with six possible MCCs therefore does not receive six times the influence of a category with one possible MCC.

### Exact MCC path

When a reconciliation genuinely supplies a literal MCC, Store persists `observedMerchantCategoryCode`. This can become `directOwnerMcc` evidence and may eventually make a location prediction `isObserved`/`isTrusted` under the graph rules.

Do not route ordinary category confirmation through this path.

## Community MCC sharing

Community sharing is an **optional network enhancement**, not a requirement for PickMe to work.

### Consent

`CommunityMerchantMCCSettingsStore` owns an explicit opt-in setting. Local learning remains available regardless of this switch.

When sharing is disabled:

- cached shared MCC evidence is deleted;
- pending community MCC uploads are cleared;
- normal local recommendations continue.

### What may be uploaded

The community wire only accepts reports created from an explicit owner-observed literal MCC with a physical location and a recognized seed merchant.

The report intentionally excludes:

- card ID;
- purchase amount;
- Wallet descriptor;
- account information;
- user ID;
- device ID.

Category-only and reward-inference feedback are **not** uploaded as exact MCC observations.

### Location privacy

Community upload/query uses rounded coordinates (~0.001 degrees, roughly 100 m scale) plus canonical merchant ID rather than a precise visit trace. This also makes matching tolerant to small Wallet/MapKit GPS drift.

Do not casually increase shared coordinate precision. If a future backend gains a better privacy-preserving spatial key (for example H3/geohash cells with documented resolution), migrate the wire version explicitly.

### Retry behavior

Explicit MCC reports enter a local pending queue. Upload is opportunistic during community refresh. Observation UUIDs provide idempotency so a retry after a crash does not create duplicate server truth.

### Downloaded community evidence

Community signals are cached separately from owner history and expire after a short TTL. They remain `externalLocationReport` evidence.

The client currently requires corroboration across at least three support days before accepting a shared signal and caps community source confidence below owner evidence. Even unanimous community evidence cannot make `MerchantMCCPrediction.isTrusted` true by itself because `isTrusted` requires direct-owner observations.

### External backend boundary

The iOS client defines:

```text
POST /api/community/merchant-mcc
POST /api/community/merchant-mcc/query
```

through `MoneyTalksConfiguration.apiBaseURL`.

This PickMe repository contains the client/wire contract; do **not** assume from that alone that a production backend deployment, retention policy, abuse controls, aggregation job, or operational SLO has been independently verified. A future production-readiness pass should confirm the server implementation and deployment against this contract.

## Recommendation integration

The graph does not directly decide the card.

The flow is:

```text
merchant/location/channel
    -> MerchantMCCGraph distribution
    -> scoreable PickMe purchase category branches
    -> issuer/card reward contract rules
    -> reward value per card
    -> final purchase decision policy
```

This separation is important. A merchant can have uncertain MCC but still produce a confident recommendation if every plausible MCC branch chooses the same card.

Conversely, if different plausible MCCs produce different winning cards, PickMe should expose/resolve the ambiguity rather than hide it behind a single guessed MCC.

`merchantMCCGraphPrediction` is the Store-side projection used by normal category resolution. It consumes the same graph and local/community reward evidence used elsewhere.

## Purchase Routes integration

`PurchaseRouteAcquisitionResolver` consumes the same MCC graph to decide whether a nearby acquisition merchant satisfies a route's required MCC.

This was an explicit design choice: Purchase Routes must not have a second merchant classification system.

Gift-card inventory is a separate evidence axis. “This Metro likely codes as grocery” does **not** imply “this Metro has the desired gift card in stock.” MCC and inventory confidence must remain independent.

## Choices made and why

### 1. One Store-side runtime graph

**Chosen:** one `MerchantMCCGraph` in Store.

**Why:** merchant identity, location, local observations, community cache, and purchase reconciliation all live at the Store/composition boundary. Running a second Engine posterior created duplicate truth and synchronization risk.

**Future freedom:** if MCC inference later becomes a pure cross-platform semantic that must run identically on iOS/Android/server, it may be promoted to a shared engine contract. Do that as a migration, not by adding a second resolver.

### 2. Keep seed and observations separate

**Chosen:** immutable-ish authored seed + runtime evidence.

**Why:** allows corrections and learning without rewriting provenance. It also makes it clear which claim came from research versus a real transaction.

### 3. Learn from reward outcomes without fabricating MCC

**Chosen:** fractional bounded candidate evidence.

**Why:** high user convenience. Users often know “this earned grocery” before they know a four-digit MCC. That information is valuable but weaker than exact network data.

### 4. Prefer reconciliation over constant prompts

**Chosen:** optional statement-time prompt.

**Why:** better evidence timing and lower UX friction. Asking after every purchase would create fatigue and low-quality labels.

### 5. Community is opt-in and weaker than local owner truth

**Chosen:** explicit consent, privacy-minimal payload, short-lived cache, corroboration threshold.

**Why:** community data can dramatically improve cold-start coverage, but should not require sharing financial history or allow a noisy crowd to override direct evidence.

### 6. No mandatory bank linking today

**Chosen:** PickMe works with the current Wallet/reconciliation path without requiring a linked financial account.

**Why:** lower onboarding friction, lower dependency cost, and no single Canadian aggregation provider guarantees MCC coverage for every issuer.

**Not a permanent rejection:** automatic financial-data providers remain one of the strongest future upgrades if coverage/cost/privacy justify them.

## Alternatives considered but not adopted as the foundation

### Plaid / MX / issuer aggregation as the only MCC source

Potentially excellent for automatic exact MCC observations, but institution coverage varies and creates account-linking friction plus an external dependency. Best treated as a future evidence provider, not the only architecture.

### Public/community MCC website as the database

Useful for research and low-confidence verification, but licensing, completeness, staleness, and location variance make it unsuitable as PickMe's canonical runtime truth.

### MapKit category = MCC

Rejected. POI category is semantic place information, not payment-network merchant coding.

### User manually enters MCC for every purchase

Rejected as a primary workflow because the friction would destroy learning participation. Keep exact MCC entry advanced/optional while collecting lower-friction evidence where safe.

### Latest observation overwrites merchant MCC

Rejected because it destroys contradictory evidence and cannot distinguish temporary/local differences from a brand-wide change.

## Future provider seam

The next scalable architecture should treat exact-MCC acquisition as providers feeding the existing evidence model:

```text
MerchantMCCObservationProvider
    local reconciliation
    statement/file import
    Plaid
    MX
    Canadian consumer-driven banking API
    direct issuer API
    Mastercard/Visa/processor source
    community aggregate
            |
            v
      MerchantMCCEvidence
            |
            v
      MerchantMCCGraph
```

The interface does not have to use this exact Swift name today. The architectural requirement is that providers emit normalized evidence rather than each implementing recommendation logic.

A provider should ideally report:

```text
merchant identity / descriptor
literal MCC if actually supplied
location/place identity when available
network
channel
observed timestamp
source/provenance
confidence / source class
stable dedupe fingerprint
```

## Highest-ROI next improvements

These are recommendations, not locked requirements. Re-evaluate them against product usage and provider availability before implementing.

### P0 — verify/productionize the community backend contract

The client is now useful enough that the highest operational risk is assuming the server side is production-grade when only the client contract is visible here.

Verify:

- the two MCC endpoints are deployed;
- observation UUID dedupe is enforced server-side;
- coordinate rounding/bucketing matches the client;
- no hidden user/device/account identifier is retained;
- aggregation requires independent support rather than repeated spam from one source;
- abuse/rate limiting exists;
- deletion/retention policy is documented;
- query responses satisfy the `supportDays/supportUnits/totalUnits/confidence` contract;
- monitoring exists for rejection/error rates.

### P1 — add an automatic exact-MCC provider when economics justify it

A linked-transaction provider could remove nearly all user friction for supported institutions. Recommended approach:

1. run a small Canadian coverage proof-of-concept;
2. measure which target issuers actually return ISO MCC;
3. compare Plaid, MX, issuer/open-banking alternatives on coverage, refresh latency, cost, and consent UX;
4. ingest only literal MCC as direct evidence;
5. keep the existing local/community path as fallback.

Do not commit PickMe's domain model to one vendor.

### P1 — instrument learning quality

Before making the model more sophisticated, measure whether it is actually improving recommendations.

Useful privacy-safe metrics:

- seed-only vs learned prediction rate;
- MCC/category disagreement rate;
- percentage of uncertain branches that change the recommended card;
- reward-feedback completion/skip rate;
- direct-MCC observations per active user;
- community signal coverage by merchant/location;
- calibration: predictions at ~80% confidence should be correct about ~80% of the time;
- stale/recode detection rate.

Prefer aggregated counters; do not create unnecessary transaction telemetry.

### P1 — explicit recoding/change detection

MCCs can change. Add logic that recognizes recent strong evidence disagreeing with an older strong posterior and lowers confidence quickly rather than waiting for long-term historical weight to decay.

A future model may use change-point detection or a shorter half-life after a conflict.

### P2 — move local evidence persistence when scale warrants it

Small evidence caches/queues currently fit lightweight local persistence. If evidence volume, migrations, querying, or debugging become painful, move runtime evidence to a versioned SwiftData/SQLite model.

Do not migrate just for architectural aesthetics; do it when the operational benefit is real.

### P2 — hierarchical/generalized learning

Once enough real observations exist, consider hierarchical priors:

```text
brand
  -> region
    -> location
      -> network
        -> channel
```

This would let a new location borrow useful information from the brand while still allowing the location to diverge with direct evidence.

### P2 — broaden merchant coverage beyond the initial 500

Expand only after identity quality and evidence provenance are stable. Prefer stable canonical merchant IDs and additive shards/contracts so existing observations survive catalogue growth.

## What a future agent is free to change

A future agent **should** change the following when a demonstrably better solution exists:

- graph math and confidence calibration;
- evidence weights;
- decay/half-life rules;
- storage technology;
- backend provider;
- spatial bucketing technology;
- exact-MCC acquisition vendors;
- promotion thresholds;
- prompt timing/copy;
- community aggregation algorithm;
- merchant catalogue size;
- whether inference eventually runs on-device, server-side, or both.

Do not preserve a mediocre choice merely because this document records it.

## What a future agent must prove before replacing the architecture

A replacement should answer:

1. Does it preserve the difference between seed, inferred category, community evidence, and literal observed MCC?
2. Can it represent location/channel/network variation?
3. Can it retain or audit contradictory observations?
4. What happens offline or when the provider/backend is down?
5. Can existing evidence be migrated without silently becoming stronger?
6. Does it improve measurable recommendation accuracy, latency, cost, coverage, or user friction?
7. Does it maintain or improve privacy?
8. Is there still one authoritative runtime resolver?

If the answer is yes and the new approach has materially higher ROI, replace the current implementation and update this document.

## Future-agent implementation checklist

Before touching MCC code:

1. Read this document.
2. Read `REPO_MAP.md` and the nearest `AGENTS.md`.
3. Inspect current `main`; this subsystem is evolving quickly and another agent may have landed work after this document.
4. Find all callers of `MerchantMCCGraph.predict` and `merchantMCCGraphPrediction`.
5. Check Purchase Routes before changing MCC semantics.
6. Check community wire/privacy tests before changing shared evidence.
7. Never infer a literal MCC from category feedback.
8. Add/update tests for provenance, conflict, location scope, and dedupe.
9. Run:

```bash
python3 scripts/validate-merchant-mcc-graph.py
(cd Store && swift test)
(cd Engine && swift test)
```

10. Let CI verify the synchronized Store resources and app integration.
11. Update this document when the architecture, evidence contract, or highest-ROI recommendation materially changes.

## Key implementation map

### Canonical seed/data

- `contracts/merchant-mcc-graph/manifest.json`
- `contracts/merchant-mcc-graph/profiles.json`
- `contracts/merchant-mcc-graph/observations.json`
- `contracts/merchant-mcc-graph/merchants-*.json`
- `scripts/validate-merchant-mcc-graph.py`
- `scripts/sync-merchant-mcc-graph-into-store.sh`

### Store graph/runtime

- `Store/Sources/CardCopilotStore/MerchantMCCGraph.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCSeedCatalogue.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCGraphEvidenceBuilder.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCGraphResolution.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCRewardFeedback.swift`
- `Store/Sources/CardCopilotStore/MerchantMCCLearningStore.swift`
- `Store/Sources/CardCopilotStore/CommunityMerchantMCC.swift`
- `Store/Sources/CardCopilotStore/CommunityMerchantMCCPendingStore.swift`
- `Store/Sources/CardCopilotStore/CommunityMerchantMCCReports.swift`
- `Store/Sources/CardCopilotStore/PurchaseRouteAcquisitionResolver.swift`

### App integration

- `App/CardCopilot/Views/ReconcileView.swift`
- `App/CardCopilot/Services/MerchantProvider.swift`
- `App/CardCopilot/Settings.bundle/Root.plist`

### Important tests

- `Store/Tests/CardCopilotStoreTests/MerchantMCCGraphTests.swift`
- `Store/Tests/CardCopilotStoreTests/MerchantMCCLearningStoreTests.swift`
- `Store/Tests/CardCopilotStoreTests/MerchantMCCSeedCatalogueTests.swift`
- `Store/Tests/CardCopilotStoreTests/MerchantMCCSeedResourceSyncTests.swift`
- `Store/Tests/CardCopilotStoreTests/MerchantMCCWeightedPriorTests.swift`
- `Store/Tests/CardCopilotStoreTests/CommunityMerchantMCCTests.swift`

## Known historical data issue

The merchant-pack Air Canada MCC issue recorded in the original seed design should remain a focused data-cleanup task unless already fixed: `merchant-pack.json` historically used MCC `3000`, while the MCC taxonomy identifies `3009` as Air Canada. Verify current `main` before changing it; do not blindly apply an old note.

## Final architecture principle

The goal is not to build the most sophisticated MCC model. The goal is to make the **best card decision with honest uncertainty and continuously improving evidence**.

If a simpler system produces better measured decisions with less cost and friction, use it. If a more scalable provider or model becomes materially better, migrate to it. Keep the evidence provenance and trust boundaries intact so PickMe can evolve without losing the ability to explain why it believed a merchant coded a certain way.
