# Contracts changelog

One entry per catalogue/fixture change (spec §3). Newest first.

## 2026-08-16 — Protection badge compares only what it shows

Fixes the `x-known-invariant-gap` recorded in the entry below; that key is gone from the schema,
replaced by `x-compared-vs-displayed`. No data change — engine, app, and schema documentation only.

- `maxAnnualCad` is now rendered by `BenefitsFormatting.factsLine` (`"$10,000/yr"`). It was voting in
  the dominance badge while invisible, so the badge's "equal or better on every line below" claim
  could turn on a row the user could not check. Concretely: Triangle's purchase protection displayed
  as `"90 days"`, character-identical to MBNA/Scotia/Tangerine/Rogers, while its unstated $10,000
  annual maximum strictly outranked all four.
- `maxOriginalWarrantyYears` is **removed from `BenefitsAdvisor.fieldSpecs`** and is now display-only
  (`"originals ≤ 5 yr"`). It is an eligibility ceiling, not a coverage magnitude: a certificate
  stating no ceiling plausibly means *no restriction* — the best case — but the code scored absence
  as worst, ranking the four cards carrying `5` above the five carrying `null` on a comparison that
  may have been exactly backwards. Absence is only rankable for magnitudes.
- The resulting invariant, now stated on `fieldSpecs` and `factsLine` and in the schema: **every
  compared field must be displayed; a displayed field need not be compared.** Pinned by
  `BenefitsComparisonTests.testOriginalWarrantyCeilingDoesNotDecideDominance` (ties instead of
  badging) and `testAnnualMaximumStillDecidesDominance` (the magnitude keeps its vote).

## 2026-08-16 — Benefits contract parity

- Added `schema/benefits-catalogue.schema.json`. The extraction below moved `benefits-catalogue.json`
  into this directory but wrote schemas only for the other two files — the spec's own §1 listing
  omitted it — so benefits data was canonical here while every consumer had to re-derive its shape by
  reading `BenefitsModels.swift`. MoneyTalks had already hand-derived a zod schema that way; this is
  the single authoritative reading that replaces it. Spec §1 listing updated to match.
  The schema documents two things a reader cannot recover from the JSON alone: `family`/`kind` are
  **open** vocabularies (plain `String` in Swift; the enums are non-`Codable` namespaces, so unknown
  values decode, round-trip, and are ignored rather than rejected — load-bearing forward
  compatibility), while `verificationStatus` is a **closed** enum whose unknown values are a hard
  decode failure. Also records `x-known-invariant-gap`: `maxAnnualCad` and `maxOriginalWarrantyYears`
  feed the Pareto dominance badge but are never rendered by `BenefitsFormatting.factsLine`, so the
  badge's "equal or better on every line below" claim can turn on a row the user cannot see —
  currently masked by the data, not fixed.
- Normalised `benefitsCatalogueVersion` from `"0.2.0"` to `"1.0"`, matching the MAJOR.MINOR
  convention `catalogueVersion` and `fixturesVersion` already use (spec §3). **Not a breaking change:**
  the shape is byte-identical apart from that string; this declares the existing shape as 1.0 rather
  than changing it. The field stays decoded-but-unread — unlike `catalogueVersion`, `SeedLoader` does
  not gate on it, because benefits are disclose-only and never feed scoring, so a mismatch degrades
  displayed coverage facts instead of corrupting dollar recommendations. Revisit if a second engine
  ever loads this file.
- Consumers with a vendored copy (MoneyTalks) must re-sync: the version string changed, so the
  pinned sha256 for `benefits-catalogue.json` no longer matches.

## 2026-08-16 — Extraction

- Moved `card-catalogue.json`, `benefits-catalogue.json`, `engine-fixtures.json` here from
  `Engine/Sources/CardCopilotEngine/Resources/` and `Engine/Tests/CardCopilotEngineTests/Fixtures/`.
  This directory is now the single canonical home; the Engine package keeps drift-checked
  copies at the old paths because SPM cannot declare resources outside a package's own root
  (see `scripts/sync-contracts-into-engine.sh` and `ContractsSyncTests`).
- Replaced the ad hoc `2026-08-15.1` date-stamp versioning with `catalogueVersion: "1.0"`
  (MAJOR.MINOR) and made it load-bearing: `SeedLoader` now parses MAJOR and refuses to load a
  catalogue whose MAJOR it does not recognize. `engine-fixtures.json` gained the matching
  `fixturesVersion: "1.0"` for the same convention, ahead of any future non-Swift consumer.
- Added `schema/card-catalogue.schema.json` and `schema/engine-fixtures.schema.json`,
  documenting the current shape as decoded by `CardCopilotEngine` — including fields the
  engine decodes but never acts on, and fields present in the JSON that the Swift model
  doesn't declare at all and so are silently dropped by `JSONDecoder`.
