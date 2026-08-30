---
name: card-contract-authoring
description: Use when changing PickMe card catalogue data, contract schemas, engine fixtures, scoring semantics, release stamps, or synchronized Swift/Kotlin contract resources.
---

# Authoring PickMe card contracts

PickMe owns every card-decision fact in the ecosystem. `contracts/` owns the
published bytes; the Swift engine owns their canonical interpretation. Kotlin
and the authorized TypeScript scoring twin must follow the same fixtures.

## Before editing

1. Read `Engine/AGENTS.md` and, for sourced card data, `catalogue-pipeline/AGENTS.md`.
2. Confirm `git branch --show-current` is `main`. Do not create a branch or PR.
3. Inspect `git status --short` for concurrent edits to every file you need. Stop
   rather than overwriting another workstream.
4. For a new or promoted card, enforce D3: issuer-confirmed sources are required;
   third-party data may route research but cannot verify a published card. There
   is no open card editor.

## Change order

1. Edit canonical data/schema under `contracts/`. If behavior changes, implement
   it in `Engine/` and add or update a hand-derived case in
   `contracts/engine-fixtures.json` in the same change.
2. Validate schemas: `python3 scripts/validate-catalogue-schema.py`.
3. Sync checked-in package resources:
   `scripts/sync-contracts-into-engine.sh` and
   `scripts/sync-contracts-into-android.sh`.
4. Run `(cd Engine && swift test)`. The Swift implementation and its contract-copy
   tests must pass before treating a twin as complete.
5. Implement any required Kotlin behavior, then run
   `(cd android && ./gradlew :core:engine:test)` against the same fixture bytes.
6. If any released contract byte changed, bump `catalogueVersion` according to
   compatibility, run `scripts/release-catalogue.sh`, sync Engine resources again,
   and verify with `scripts/release-catalogue.sh --check`.
7. Review the exact six-copy diff. Build outputs under `build/` and `.build/` are
   irrelevant and must never be used as sources.

## Commit and release

Commit the coherent contract, Swift semantics, fixtures, synchronized resources,
and release stamp together using a Conventional Commit with no co-author trailer.
Push `main` only after both native suites pass. Publishing a GitHub contract
release is a separate external mutation: run `scripts/publish-catalogue.sh` only
when the owner explicitly asked to publish, never merely because authoring passed.
