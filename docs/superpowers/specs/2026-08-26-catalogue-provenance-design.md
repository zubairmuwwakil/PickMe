# Catalogue provenance: stamping and freezing what scored a prediction

**Date:** 2026-08-26
**Status:** approved (design)
**Scope:** Phase 1 of future-proofing the card contract. Provenance only — remote
catalogue delivery is explicitly out of scope and depends on this landing first.

## Problem

`StoredPrediction` is the append-only log the accuracy claim is measured against, and
`Schema.swift` correctly names it "the one record here that cannot be recomputed from
anything else." It records the *outputs* of a decision (`winnerValueCad`,
`predictedRewardUnits`, `valuationCentsPerPoint`, `scoredAmountCad`) but nothing about
which contract produced them.

Today that is implicitly safe: the catalogue only changes when the app binary changes,
so "which rules scored this?" is answerable from the build. That invariant is accidental,
and remote catalogue delivery destroys it — the catalogue would begin moving independently
of the binary, and every unstamped historical prediction becomes unattributable. A miss
would be indistinguishable from a rule change, and the accuracy number would degrade
silently.

Three further gaps follow from the same root:

1. `RELEASE.json` is not in `Engine/Sources/CardCopilotEngine/Resources/`, so the release
   id and digest are unreachable at runtime. The app ships the catalogue bytes but not the
   stamp describing them.
2. `winnerCardId`, `winnerRuleId`, and `cardUsedId` are unenforced strings into the
   catalogue. Nothing catches a stored id that a newer catalogue no longer defines.
3. Card ids have no permanence guarantee. A withdrawn product could simply disappear.

## Decisions taken

- **Provenance before delivery.** Shipping a fetch path first would destroy the implicit
  provenance that exists today.
- **Stamp *and* freeze the inputs used.** History becomes self-describing rather than
  merely attributable.
- **Ids are permanent.** Withdrawn cards are tombstoned, never deleted, never reused.
- **Hybrid storage (approach C).** Queried fields flat, the rest in a versioned blob.

### Why hybrid rather than all-flat or all-blob

The two consumers have sharply different access patterns. The accuracy claim asks
"what was our hit rate under `card-contracts@1.6`?" — an aggregate across many rows,
needing a real indexed column or it degrades to a full-table decode. The explain path
asks "what did we know when we scored this one?" — always a single-row lookup by id,
where a blob costs nothing. One mechanism would be wrong for one of them.

## Design

### 1. Runtime access to the stamp

`contracts/` and `Resources/` are already byte-identical (verified for
`card-catalogue.json` and `programs.json`). Copy `RELEASE.json` into `Resources/`, where
`.process("Resources")` in `Engine/Package.swift` picks it up.

`SeedLoader` gains `loadContractRelease() -> ContractRelease` exposing `release`,
`catalogueVersion`, and `digest`.

**Not doing:** runtime verification that bundled bytes hash to the recorded digest.
`release-catalogue.sh --check` enforces this in CI, and at this phase the stamp and the
rules ship in the same signed bundle — if one is corrupt, both are. Runtime verification
earns its keep when the catalogue arrives over the network; add it in phase 2.

### 2. The frozen snapshot

`ScoredRuleSnapshot: Codable`, declared in **Engine** (it describes contract semantics, so
it belongs beside the contract). Store persists it only as opaque `Data`.

Fields, all already resident in the `Recommendation` at decision time:

- `snapshotVersion: Int` — evolves in Swift, independent of the SwiftData schema
- `asOf: String` — the date the rules were resolved against
- `appliedRuleId`, `cardId`
- the earn rate and kind actually applied
- **deferred to `snapshotVersion` 2:** cap headroom at scoring time. `CandidateScore` does
  not carry it, so surfacing it means changing the engine's core output type — a wider
  change than this work. The `capNearlyExhausted` warning preserves the qualitative signal,
  and the blob's independent versioning is exactly what lets this be added later without a
  store migration.
- valuation used: `programId`, `centsPerPoint`, and the basis (floor / declared / aspirational)
- `grossRewardCad`, `fxCostCad`, `netValueCad`
- `warnings`, `exclusionReason`

Captured at the single production write site, `CheckoutService.swift:150`. No new
computation.

### 3. Store schema V2

`CardCopilotSchemaV2`. `StoredPrediction` gains three properties:

- `contractRelease: String?`
- `contractDigest: String?`
- `frozenInputs: Data?`

Typealiases move to V2. `CardCopilotMigrationPlan` gains the V2 schema and a
`.lightweight` stage — all three properties are optional, which is exactly the case
`Schema.swift` says to prefer.

V1 rows migrate with nulls. `contractRelease == nil` is the queryable meaning of "scored
before provenance existed," so accuracy reporting can bucket or exclude those rows
honestly rather than averaging them in with attributable ones. Pre-provenance rows are
**not** backfilled: inputs that were never recorded cannot be invented.

This migration is only cheap because `d05ecaa` nested the models under
`CardCopilotSchemaV1`. A flat V1 would have required performing that namespacing move
underneath a live store, in the same change that reshapes it.

### 4. Tombstoning

Cards gain card-level `status` (`active` / `withdrawn`) and `effectiveTo`, mirroring what
rules already carry and what `RuleMatcher` already enforces. Withdrawn cards are excluded
from candidate scoring but remain **resolvable by id** for display and history.
`schema/card-catalogue.schema.json` is updated to match.

The load-bearing piece is a **CI gate**: a check that no `cardId` present in the previously
published release has disappeared from the working set. "Ids are permanent" is a promise,
and a promise nothing enforces is one that breaks the first busy week.

### 5. Retention — out of scope, with the math

The snapshot serializes to roughly 400–800 bytes. At 10 checkouts/day that is ~3 MB/year;
at an aggressive 50/day, under 15 MB/year. `StoredPrediction` is the accuracy spine and
should not be pruned, and at these volumes it does not need to be. Compaction machinery
would solve a problem two orders of magnitude away. Revisit only if measured blob size
lands far above this estimate.

### 6. Testing

- **Engine:** `ScoredRuleSnapshot` `Codable` round-trip; fixture-driven assertion that the
  snapshot faithfully reflects what `Recommendation` held at scoring time.
- **Store:** a real V1→V2 migration test that opens a store written under V1.
  `SchemaVersionTests` currently pins registration only, which would not catch a broken stage.
- **CI:** the id-permanence gate from §4.

## Cross-repo impact

**None.** `engine-fixtures.json` is untouched; the catalogue change is additive and adds no
fixture assertions. MoneyTalks and the Android consumer need no coordination.

## Out of scope

- Remote catalogue fetch, verification, and rollback (phase 2 — this is its prerequisite)
- Re-scoring historical predictions
- Prediction-log retention or compaction (see §5)
