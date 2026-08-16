# Card Contract — Phase 1 extraction spec

**Status:** Approved 2026-08-16 (design ratified in chat; fork "web picker" closed: none in v1).
**Parent decisions:** `../../MoneyTalks/docs/decisions/2026-08-16-one-money-app.md` (esp. 2, 3, 6, 9, 10).
**Goal:** one canonical home for card *data* and one language-neutral conformance suite for card *logic*, so MoneyTalks can delete its competing engine without creating a second source of truth.

## 1. Canonical location

`PickMe/contracts/` — PickMe owns card semantics, so it owns the contract. No new repo, no package registry (monorepo mechanics stay deferred).

```
contracts/
  card-catalogue.json        # moved from Engine/Sources/CardCopilotEngine/Resources/
  benefits-catalogue.json    # moved from same
  engine-fixtures.json       # moved from Engine/Tests/CardCopilotEngineTests/Fixtures/
  schema/
    card-catalogue.schema.json
    benefits-catalogue.schema.json
    engine-fixtures.schema.json
  CHANGELOG.md               # one line per catalogue/fixture change
```

The Swift package consumes them exactly as today via SPM resources — the move is a path change in `Package.swift` (`.copy`/`.process` resource paths) + `SeedLoader`. `swift test` green proves the move.

## 2. Consumers

| Consumer | Mechanism | What it may do |
|---|---|---|
| PickMe Engine (canonical) | SPM bundle resources from `contracts/` | Full semantics. Only place recommendation logic lives. |
| MoneyTalks web | **vendored copy** at `MoneyTalks/contracts/` + CI drift check (sha256 of each file vs a pinned manifest; fail = "re-sync from PickMe") | **Data display only** (v1): wallet facts, cap definitions/progress rendering, benefits reference. **No recommend(), no picker, no cheatsheet.** |
| Future TS twin | must pass `engine-fixtures.json` verbatim before it may ship | Deferred until a consumer needs recommendations outside iOS. |

Sync is manual-plus-guardrail on purpose: a copy script (`scripts/sync-contracts.sh` in MoneyTalks) and a CI step that fails on drift. Cheap, no infra, impossible to diverge silently.

## 3. Versioning (make `catalogueVersion` load-bearing)

- `catalogueVersion: "MAJOR.MINOR"` in `card-catalogue.json`, and `fixturesVersion` in `engine-fixtures.json`; they move together.
- MAJOR bumps on any breaking shape change; consumers (Swift now, TS later) **refuse to load a MAJOR they don't know** — today the field is decoded and never read; SeedLoader gains that check.
- Every catalogue edit updates `CHANGELOG.md` and `lastVerifiedAt` on touched rules.

## 4. Schema: document reality, don't redesign it

JSON Schema describes the format **as-is**, including fields the engine does not yet implement — marked `"x-status": "declared-not-computed"` so the gap PickMe's review found (cap `period`/`anchor`/`resetTimeZone`, `postAllowanceRate`, `RuleStatus`, `SourceType`) is visible in the contract instead of silent. Three behaviors are explicitly **engine-defined, not data**: `ownerConditions` ids, `program.programId` valuation dispatch, pseudo-categories (`recurring`, `ownerSelectedTangerineCategory`) + `categoryParents`. The schema enumerates their legal values; adding one remains a code change in the canonical engine by design.

## 5. Fixture expansion (before any TS twin, after extraction)

`engine-fixtures.json` grows from 12 to ~25 cases, covering each rule family at least twice: MCC include at nil-MCC (the permissive-fallback path) · MCC exclude · merchant exclude vs brand · effective-dating boundary (day-of flip) · FX simple + FX-allowance flag path · cap proration straddle · cap exhausted with `postCapEarn` · switch-threshold `both` vs `either` semantics · valuation floor/upside disclosure gate · owner-condition unresolved (fail-closed). Each keeps the existing discipline: pinned valuations, hand-derived arithmetic embedded in each case's `description` (the file's convention — there is no separate `notes` field).

**Status 2026-08-16: DONE — 27 cases at fixturesVersion 1.1, verified.**

## 6. Implementation chunks (each independently verifiable — orc-able per decision 10)

| # | Task | Verifier | Blocked by |
|---|---|---|---|
| a | Move files into `contracts/`, add schema + version check in SeedLoader, add a schema-validation test | `swift test` (Engine + Store) green | CI gate from chip task_1ea55992 |
| b | MoneyTalks: vendor copy + sync script + drift-check CI step; wallet/cap display reads catalogue data | `vitest` + `next build` + drift check | a |
| c | **Delete `MoneyTalks/src/engine/cards/`**, picker/cheatsheet/analyzer UI routes, and their 33 tests; keep manual `CardState` (caps/credits log) rendering from contract data | build + remaining ~199 unit tests + e2e (cards spec rewritten to wallet-display scope) | b |
| d | Expand fixtures per §5 | `swift test` fixture harness green | a |

**Done means:** one catalogue on disk in one repo, drift-checked copies elsewhere, MoneyTalks has zero recommendation code, fixtures ≥25 cases, CI gates on both repos.

## Out of scope (unchanged from decision record)

TS engine port · monorepo · catalogue content expansion beyond the 10 cards · any new picker surface.
