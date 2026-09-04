# Mastercard Places MCC proof of concept

**Date:** 2026-09-04  
**Status:** ready when Mastercard real-data access/terms are available  
**Research:** `docs/research/2026-09-04-merchant-mcc-provider-evaluation.md`  
**Architecture:** `docs/superpowers/specs/2026-09-04-merchant-mcc-production-architecture-design.md`

## Goal

Determine whether Mastercard Places can economically and correctly supply location-level Mastercard MCC evidence for Canadian merchants **without bank linking**, and whether its contract permits PickMe’s intended runtime use.

This POC is intentionally evidence-first. Do not build a production client before the access, coverage, accuracy, and data-use gates pass.

## Hypothesis

PickMe already has:

```text
Wallet/GPS
  -> MapKit nearby POI
  -> conservative canonical merchant resolution
  -> MerchantMCCGraph
```

Mastercard Places can potentially add:

```text
canonical merchant + resolved physical location
  -> server-side Places lookup
  -> Mastercard location mccCode
  -> externalLocationReport(network: mastercard)
  -> existing MerchantMCCGraph
```

No bank account, purchase amount, card identity, user identity, or Wallet descriptor needs to be sent to Places for this use case.

## Phase 0 — access and legal gate

Before writing production integration code:

1. Create/use a Mastercard Developers project with Places enabled.
2. Confirm access to **real Canadian data**; sandbox dummy data is insufficient for the coverage test.
3. Obtain current production pricing/quota information.
4. Read the current Places-specific agreement/terms, not just generic Mastercard Developers terms.
5. Get explicit answers on:
   - whether PickMe may retain/cache returned `mccCode` and location identifiers;
   - allowed cache duration;
   - whether Places data may be combined with PickMe’s own merchant/MCC evidence graph;
   - whether aggregate/community-derived outputs may incorporate provider evidence;
   - display/redistribution restrictions;
   - attribution requirements;
   - deletion requirements after termination.

### Stop condition

If the contract does not permit the required reusable runtime evidence semantics, **do not work around it technically**. Mark Places as runtime-only if permitted, or reject it and move to the next provider.

## Phase 1 — offline Canadian coverage experiment

Use a test harness/server script, not the iOS production path.

### Sample

Build a stratified sample from the existing 500 Canadian seed:

- 100–150 physical merchant locations if practical;
- include grocery, dining/QSR, gas, pharmacy, big box, electronics, apparel, travel/hotel, auto, and specialty;
- include national chains and a few merchants where PickMe already has owner/public exact-MCC evidence;
- include multiple locations for several large chains to test location variation;
- use known MapKit coordinates/place context rather than sending transaction history.

Do not cherry-pick only famous merchants.

### Record for the POC

The POC report may retain only what the provider agreement permits. At minimum derive aggregate measurements for:

- query attempted;
- zero/one/multiple candidate result;
- accepted identity match vs rejected/ambiguous;
- MCC present vs absent;
- exact agreement/disagreement with available comparison evidence;
- latency bucket;
- error/rate-limit outcome.

Do not commit production credentials or raw licensed provider datasets to Git.

## Phase 2 — identity acceptance rule

Do not accept the nearest Places result blindly.

A result should initially require all of:

1. PickMe already has a high-confidence canonical merchant ID from its own identity path.
2. Places merchant name/hierarchy agrees with that canonical merchant under a conservative matcher.
3. Physical distance/location is within a tested threshold appropriate for the source precision.
4. Result is not an ecommerce-only location for an in-store query.
5. `mccCode` parses as a valid four-digit MCC.

Ambiguity fails closed.

The POC should log aggregate rejection reasons because a low acceptance rate can mean identity matching—not MCC coverage—is the bottleneck.

## Phase 3 — initial go/no-go gates

These are **engineering starting thresholds**, not claims about Mastercard’s service. Future agents should tune them if the sample proves they are poorly chosen.

Proceed to a production design only if approximately:

- **identity precision:** >= 98% on manually validated accepted matches;
- **accepted-location coverage:** >= 80% of the target sample;
- **MCC fill among accepted locations:** >= 90%;
- **catastrophic mismatch rate:** effectively zero for obvious wrong-brand/wrong-location matches;
- **p95 latency:** acceptable for asynchronous/prefetch use, or provider supports caching permitted by contract;
- **economics:** projected decision-sensitive lookup cost is comfortably below the value of improved recommendations;
- **terms:** permit the actual storage/runtime use PickMe requires.

A lower raw coverage rate may still pass if coverage is excellent in the merchant categories where MCC uncertainty changes card winners most often.

## Phase 4 — compare against PickMe evidence

For locations with trustworthy comparison data, measure separately:

```text
Places vs direct owner literal MCC
Places vs community aggregate
Places vs researched seed prior
```

Do not collapse these into one “accuracy” denominator: their provenance differs.

Important interpretation:

- disagreement with a seed prior may indicate the seed is wrong;
- disagreement with owner MCC may reflect Mastercard-vs-other-network variation or location/acquirer change;
- disagreement across networks should remain evidence, not be force-resolved.

The POC must therefore retain network provenance when evaluating correctness.

## Phase 5 — production architecture if the POC passes

### Credential boundary

Mastercard credentials/private keys must live server-side. **Never ship them in the iOS app.**

Preferred topology:

```text
PickMe
  -> In Unity/MoneyTalks provider endpoint
      -> Mastercard Places
      -> normalized, contract-compliant response
  -> MerchantMCCEvidence
  -> MerchantMCCGraph
```

In Unity owns transport/secret management/cache/rate limiting. PickMe continues to own merchant identity, evidence weighting, confidence, and card decisions.

If a dedicated provider service becomes operationally cleaner at scale, it may replace the In Unity route. Do not move recommendation semantics with it.

### Minimal request

Prefer only the data needed for a place lookup:

- canonical merchant ID/name token as needed for match verification;
- resolved/coarsened physical location appropriate to the API;
- channel/in-store context.

Do **not** send:

- amount;
- card ID/PAN;
- owner identity;
- Wallet event ID;
- raw Wallet descriptor;
- reward result;
- transaction history.

### Evidence mapping

A successful Places result should initially map to:

```text
kind = externalLocationReport
network = mastercard
mcc = provider mccCode
location = matched store scope
sourceConfidence = calibrated provider confidence, below direct owner evidence
```

Do not mark it `directOwnerMcc` merely because Mastercard is the network vendor. It is still external location evidence about the merchant, not proof of the owner’s specific transaction.

## Phase 6 — decision-sensitive lookup gate

This is the key cost/scalability optimization.

Before making a paid/external provider call, PickMe should resolve locally and ask:

> Would the plausible MCC branches choose different winning cards?

The newly added decision-quality instrumentation already measures this population.

Recommended runtime policy:

```text
local graph resolves confidently
    -> no provider call

local graph uncertain, but all plausible MCCs choose same card
    -> no provider call

local graph uncertain AND plausible MCCs choose different cards
    -> provider lookup eligible
```

Additional lookup triggers may be justified for explicit user verification or stale/recode detection, but they should be deliberate.

This gate reduces:

- API spend;
- latency;
- provider dependency;
- external location disclosure;
- useless precision work that cannot change the recommendation.

## Phase 7 — caching and freshness

Only implement caching after contract review.

If allowed:

- cache provider evidence by canonical merchant + physical location + network + channel;
- attach provider provenance and retrieval time;
- expire/revalidate rather than treating provider answers as timeless;
- do not overwrite contradictory local evidence;
- do not copy licensed provider data into the static shipped seed unless explicitly permitted.

The existing graph’s recency/conflict model should continue to own how stale evidence influences decisions.

## Phase 8 — fallback and outage behavior

Provider outage must never block checkout.

Rules:

- strict network timeout;
- use permitted fresh cache if available;
- otherwise use the local graph;
- no retry loop on the checkout critical path;
- failures may increment privacy-safe aggregate diagnostics;
- do not display “verified MCC” unless evidence semantics truly warrant it.

## POC outputs

A future agent completing the experiment should update the research doc with:

1. date and Places API/version tested;
2. Canadian sample size and category distribution;
3. accepted-location coverage;
4. MCC fill rate;
5. validated identity precision;
6. disagreement breakdown by evidence source/network;
7. latency and rate-limit behavior;
8. pricing estimate at decision-sensitive lookup volume;
9. exact contract/caching conclusion;
10. GO / NO-GO / CONDITIONAL decision.

Do not commit provider credentials or licensed raw result dumps.

## If Places fails

Next evaluation order:

1. **Plaid Transactions** — optional owner-linked transaction MCC POC across the highest-priority Canadian issuers.
2. **MX Transactions** — compare MCC fill/provenance if Plaid is weak.
3. issuer-specific statement/API imports where a literal MCC is documented.
4. revisit network/processor sources as terms/products evolve.

Do not jump to a more sophisticated MCC model merely because an evidence provider fails. Provider coverage and inference quality are separate problems.

## What future agents may change

Everything in this POC plan is replaceable except the trust/privacy invariants in the production architecture.

Change the vendor, thresholds, sample design, backend host, spatial matching algorithm, caching strategy, or call trigger when measurements show a higher-ROI approach.

The success criterion is not “integrate Mastercard Places.” It is:

> **Acquire materially better MCC evidence at a privacy, latency, cost, and reliability level that improves PickMe’s actual card decisions.**
