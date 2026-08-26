# Catalogue Provenance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every stored prediction say which contract release scored it and freeze the rule inputs that produced it, so the accuracy claim survives the catalogue changing underneath it.

**Architecture:** Hybrid storage. `contractRelease` and `contractDigest` become flat SwiftData columns because the accuracy claim aggregates across many rows; the full frozen rule snapshot becomes a versioned `Codable` blob because the explain path is always a single-row lookup. Card ids gain a permanence guarantee enforced in CI rather than by convention.

**Tech Stack:** Swift 5.9+, SwiftData (`VersionedSchema` / `SchemaMigrationPlan`), XCTest, bash + `gh` for contract tooling, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-26-catalogue-provenance-design.md`

## Global Constraints

- `engine-fixtures.json` MUST NOT change. This work is additive; any fixture edit breaks MoneyTalks and the Android consumer and is out of scope.
- `contracts/` is canonical. Engine's `Resources/` copies are byte-identical mirrors, enforced by `ContractsSyncTests` and resynced with `scripts/sync-contracts-into-engine.sh`. Never edit a `Resources/*.json` directly.
- `catalogueVersion` MAJOR stays `1`. Nothing here is a breaking shape change. `SeedLoader.supportedCatalogueMajorVersion` is not bumped.
- Never edit the `v1Shape` baseline table in `SchemaVersionTests.swift`. A changed shape is a new schema version, never a baseline edit.
- `StoredPrediction` is append-only. All new properties are optional; no existing property changes type, name, or nullability.
- Existing test suites must stay green: `Engine` 164 tests, `Store` 69 tests.
- Do not commit unless the task's final step says to.

---

### Task 1: Ship the release stamp at runtime

`RELEASE.json` exists in `contracts/` but is not bundled, so the release id and digest are unreachable from running code.

**Files:**
- Create: `Engine/Sources/CardCopilotEngine/Resources/RELEASE.json` (copy of `contracts/RELEASE.json`)
- Create: `Engine/Sources/CardCopilotEngine/Models/ContractRelease.swift`
- Modify: `Engine/Sources/CardCopilotEngine/Loading/SeedLoader.swift`
- Modify: `scripts/sync-contracts-into-engine.sh`
- Test: `Engine/Tests/CardCopilotEngineTests/ContractReleaseTests.swift`
- Test: `Engine/Tests/CardCopilotEngineTests/ContractsSyncTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `ContractRelease` (properties `release: String`, `catalogueVersion: String`, `digest: String`, `files: [String: String]`) and `SeedLoader.loadContractRelease() throws -> ContractRelease`. Task 4 calls this.

- [ ] **Step 1: Write the failing test**

Create `Engine/Tests/CardCopilotEngineTests/ContractReleaseTests.swift`:

```swift
import XCTest
@testable import CardCopilotEngine

final class ContractReleaseTests: XCTestCase {

    /// The stamp must be reachable from running code, not just from CI. Without this, a
    /// prediction can record which rules it used only by implication from the build.
    func testReleaseStampLoadsFromBundle() throws {
        let stamp = try SeedLoader.loadContractRelease()
        XCTAssertFalse(stamp.release.isEmpty)
        XCTAssertTrue(stamp.digest.hasPrefix("sha256:"),
                      "digest is content-addressed and carries its algorithm prefix")
        XCTAssertFalse(stamp.files.isEmpty)
    }

    /// The stamp travels with the bytes it describes. If these disagree, the stamp is
    /// describing a catalogue that is not the one loaded.
    func testStampAgreesWithTheLoadedCatalogue() throws {
        let stamp = try SeedLoader.loadContractRelease()
        let catalogue = try SeedLoader.loadCatalogue()
        XCTAssertEqual(stamp.catalogueVersion, catalogue.catalogueVersion)
    }

    /// Every file the release claims to cover must be one this build can name.
    func testStampCoversTheCardCatalogue() throws {
        let stamp = try SeedLoader.loadContractRelease()
        XCTAssertNotNil(stamp.files["card-catalogue.json"])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Engine && swift test --filter ContractReleaseTests`
Expected: FAIL — "type 'SeedLoader' has no member 'loadContractRelease'"

- [ ] **Step 3: Add the model type**

Create `Engine/Sources/CardCopilotEngine/Models/ContractRelease.swift`:

```swift
import Foundation

/// The stamp describing which contract bytes this build shipped.
///
/// Mirrors `contracts/RELEASE.json`, which `scripts/release-catalogue.sh` writes and
/// `scripts/publish-catalogue.sh` publishes. Bundling it is what lets a prediction record the
/// contract that scored it rather than leaving that answerable only by implication from the
/// build number.
///
/// `digest` carries its `sha256:` prefix exactly as recorded, so a stored value stays
/// self-describing if the algorithm ever changes.
public struct ContractRelease: Codable, Equatable, Sendable {
    /// The published release id, e.g. `card-contracts@1.6`. Immutable once published: a release
    /// id never describes two different byte sets (publish-catalogue.sh refuses).
    public var release: String
    public var catalogueVersion: String
    /// sha256 over the sorted "name<TAB>sha256" lines of `files`.
    public var digest: String
    /// Filename → sha256 of that file's bytes.
    public var files: [String: String]

    public init(release: String, catalogueVersion: String, digest: String, files: [String: String]) {
        self.release = release
        self.catalogueVersion = catalogueVersion
        self.digest = digest
        self.files = files
    }
}
```

- [ ] **Step 4: Copy the file into Engine resources**

Run: `cp contracts/RELEASE.json Engine/Sources/CardCopilotEngine/Resources/RELEASE.json`

No `Package.swift` change is needed — the target already declares `.process("Resources")`, which picks up every file in that directory.

- [ ] **Step 5: Add the loader**

In `Engine/Sources/CardCopilotEngine/Loading/SeedLoader.swift`, add after `loadPrograms()`:

```swift
    /// Which published contract release this build shipped.
    ///
    /// Deliberately does NOT verify that the bundled bytes hash to `digest`. That check belongs
    /// to `scripts/release-catalogue.sh --check` in CI, and at this phase the stamp and the rules
    /// ship in the same signed bundle — if one is corrupt, both are. It becomes worth paying for
    /// at runtime when the catalogue starts arriving over the network.
    public static func loadContractRelease() throws -> ContractRelease {
        try load("RELEASE")
    }
```

- [ ] **Step 6: Run test to verify it passes**

Run: `cd Engine && swift test --filter ContractReleaseTests`
Expected: PASS (3 tests)

- [ ] **Step 7: Add the drift guardrail**

In `Engine/Tests/CardCopilotEngineTests/ContractsSyncTests.swift`, add alongside the other `testXMatchesContract` methods:

```swift
    func testReleaseStampMatchesContract() throws {
        try assertSynced(contractsRelativePath: "RELEASE.json",
                         engineRelativePath: "Sources/CardCopilotEngine/Resources/RELEASE.json")
    }
```

- [ ] **Step 8: Teach the sync script about the new file**

Open `scripts/sync-contracts-into-engine.sh` and add `RELEASE.json` to whatever list of filenames it copies, following the existing style exactly. Then verify the script is idempotent:

Run: `scripts/sync-contracts-into-engine.sh && git diff --stat`
Expected: no changes (the file was already copied by hand in Step 4)

- [ ] **Step 9: Run the full Engine suite**

Run: `cd Engine && swift test`
Expected: PASS — 164 existing + 4 new

- [ ] **Step 10: Commit**

```bash
git add Engine/Sources/CardCopilotEngine/Models/ContractRelease.swift Engine/Sources/CardCopilotEngine/Resources/RELEASE.json Engine/Sources/CardCopilotEngine/Loading/SeedLoader.swift Engine/Tests/CardCopilotEngineTests/ContractReleaseTests.swift Engine/Tests/CardCopilotEngineTests/ContractsSyncTests.swift scripts/sync-contracts-into-engine.sh
git commit -m "feat(contracts): the release stamp is reachable at runtime"
```

---

### Task 2: The frozen rule snapshot

**Files:**
- Create: `Engine/Sources/CardCopilotEngine/Models/ScoredRuleSnapshot.swift`
- Test: `Engine/Tests/CardCopilotEngineTests/ScoredRuleSnapshotTests.swift`

**Interfaces:**
- Consumes: `CandidateScore` (from `Scorer.swift`), `CardProduct` and `EarnRule` (from `CatalogueModels.swift`).
- Produces: `ScoredRuleSnapshot` and `ScoredRuleSnapshot.capture(score:card:asOf:programId:unit:centsPerPoint:) -> ScoredRuleSnapshot`. Task 4 calls this.

**Design note for the implementer:** the snapshot freezes the whole `EarnRule` that won, not a copy of selected fields from it. `EarnRule` is already `Codable`, it is the actual input the scorer consumed, and copying selected fields is how the frozen record drifts from what really happened.

Cap headroom is deliberately NOT captured in version 1. `CandidateScore` does not carry it — surfacing it would mean changing the engine's core output type, which is a wider change than this task. The `capNearlyExhausted` warning preserves the qualitative signal, and `snapshotVersion` exists precisely so headroom can be added later without a SwiftData migration.

- [ ] **Step 1: Write the failing test**

Create `Engine/Tests/CardCopilotEngineTests/ScoredRuleSnapshotTests.swift`:

```swift
import XCTest
@testable import CardCopilotEngine

final class ScoredRuleSnapshotTests: XCTestCase {

    private func sampleRule() -> EarnRule {
        EarnRule(ruleId: "test-grocery-5x",
                 status: .current,
                 effectiveFrom: "2026-01-01",
                 sourceType: .issuerConfirmed,
                 earn: .points(pointsPerCad: 5),
                 predicate: Predicate())
    }

    private func sampleCard(rule: EarnRule) -> CardProduct {
        CardProduct(cardId: "amex-cobalt",
                    officialName: "Cobalt",
                    issuer: "American Express Canada",
                    network: .amex,
                    kind: .credit,
                    fee: Fee(annualCad: 156),
                    program: Program(programId: "amexMembershipRewards", unit: "point"),
                    fxRules: [],
                    earnRules: [rule],
                    caps: [],
                    perTransactionRewardVisibility: "none",
                    lastVerifiedAt: "2026-08-15",
                    credits: nil)
    }

    private func sampleScore(ruleId: String?) -> CandidateScore {
        CandidateScore(cardId: "amex-cobalt", appliedRuleId: ruleId, rewardUnits: 500,
                       grossRewardCad: 10, fxCostCad: 0, netValueCad: 10,
                       floorNetValueCad: 5, aspirationalNetValueCad: 12,
                       warnings: [.capNearlyExhausted], excluded: false, exclusionReason: nil)
    }

    /// The snapshot must survive a round trip through the exact encoding the store persists.
    func testRoundTripsThroughJSON() throws {
        let rule = sampleRule()
        let snapshot = ScoredRuleSnapshot.capture(
            score: sampleScore(ruleId: rule.ruleId), card: sampleCard(rule: rule),
            asOf: "2026-08-26", programId: "amexMembershipRewards",
            unit: "point", centsPerPoint: 2.0)

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ScoredRuleSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }

    /// The whole rule is frozen, not a re-derived summary of it.
    func testFreezesTheRuleThatActuallyWon() {
        let rule = sampleRule()
        let snapshot = ScoredRuleSnapshot.capture(
            score: sampleScore(ruleId: rule.ruleId), card: sampleCard(rule: rule),
            asOf: "2026-08-26", programId: "amexMembershipRewards",
            unit: "point", centsPerPoint: 2.0)

        XCTAssertEqual(snapshot.appliedRule, rule)
        XCTAssertEqual(snapshot.appliedRule?.earn, .points(pointsPerCad: 5))
    }

    /// An excluded card has no applied rule. That is a real outcome, not a capture failure.
    func testCapturesAnExclusionWithNoRule() {
        let rule = sampleRule()
        var score = sampleScore(ruleId: nil)
        score = CandidateScore(cardId: "amex-cobalt", appliedRuleId: nil, rewardUnits: 0,
                               grossRewardCad: 0, fxCostCad: 0, netValueCad: 0,
                               floorNetValueCad: 0, aspirationalNetValueCad: 0,
                               warnings: [.networkNotAccepted], excluded: true,
                               exclusionReason: "amex not accepted")

        let snapshot = ScoredRuleSnapshot.capture(
            score: score, card: sampleCard(rule: rule), asOf: "2026-08-26",
            programId: "amexMembershipRewards", unit: "point", centsPerPoint: 2.0)

        XCTAssertNil(snapshot.appliedRule)
        XCTAssertTrue(snapshot.excluded)
        XCTAssertEqual(snapshot.exclusionReason, "amex not accepted")
    }

    /// The valuation is an input, and a changed valuation must not retroactively rewrite
    /// what a past prediction was based on.
    func testFreezesTheValuationUsed() {
        let rule = sampleRule()
        let snapshot = ScoredRuleSnapshot.capture(
            score: sampleScore(ruleId: rule.ruleId), card: sampleCard(rule: rule),
            asOf: "2026-08-26", programId: "amexMembershipRewards",
            unit: "point", centsPerPoint: 2.0)

        XCTAssertEqual(snapshot.programId, "amexMembershipRewards")
        XCTAssertEqual(snapshot.unit, "point")
        XCTAssertEqual(snapshot.centsPerPoint, 2.0)
    }

    func testDeclaresItsOwnVersion() {
        let rule = sampleRule()
        let snapshot = ScoredRuleSnapshot.capture(
            score: sampleScore(ruleId: rule.ruleId), card: sampleCard(rule: rule),
            asOf: "2026-08-26", programId: "amexMembershipRewards",
            unit: "point", centsPerPoint: 2.0)

        XCTAssertEqual(snapshot.snapshotVersion, ScoredRuleSnapshot.currentVersion)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Engine && swift test --filter ScoredRuleSnapshotTests`
Expected: FAIL — "cannot find 'ScoredRuleSnapshot' in scope"

- [ ] **Step 3: Write the implementation**

Create `Engine/Sources/CardCopilotEngine/Models/ScoredRuleSnapshot.swift`:

```swift
import Foundation

/// Everything that produced one card's score, frozen at the moment it was produced.
///
/// This exists because `StoredPrediction` is the append-only log the accuracy claim is measured
/// against, and it recorded only the *outputs* of a decision. That was implicitly safe while the
/// catalogue could change only when the binary changed. Remote catalogue delivery ends that, so
/// the inputs have to travel with the row.
///
/// Declared in Engine rather than Store because it describes contract semantics. Store persists
/// it as opaque `Data` and never reasons about its contents.
///
/// `snapshotVersion` evolves in Swift, independently of the SwiftData schema. Adding a field here
/// is a decoder change, never a store migration — which is the whole reason this is a blob and
/// not a widening set of columns.
public struct ScoredRuleSnapshot: Codable, Equatable, Sendable {

    /// Bump when fields are added. Decoders must tolerate reading an older version.
    public static let currentVersion = 1

    public var snapshotVersion: Int
    /// The date the rules were resolved against — the same `asOf` handed to
    /// `RecommendationEngine.recommend(_:asOf:)`.
    public var asOf: String
    public var cardId: String

    /// The rule that won, frozen whole.
    ///
    /// Stored as the entire `EarnRule` rather than a summary of its fields: it is the actual
    /// input the scorer consumed, so a summary could only ever drift from what happened. Nil when
    /// the card was excluded before any rule matched.
    public var appliedRule: EarnRule?

    /// The valuation in force at scoring time. A later valuation change must not retroactively
    /// rewrite what past advice was based on.
    public var programId: String
    public var unit: String
    public var centsPerPoint: Double?

    public var rewardUnits: Double
    public var grossRewardCad: Double
    public var fxCostCad: Double
    public var netValueCad: Double
    public var floorNetValueCad: Double
    public var aspirationalNetValueCad: Double

    public var warnings: [Warning]
    public var excluded: Bool
    public var exclusionReason: String?

    public init(snapshotVersion: Int = ScoredRuleSnapshot.currentVersion,
                asOf: String, cardId: String, appliedRule: EarnRule?,
                programId: String, unit: String, centsPerPoint: Double?,
                rewardUnits: Double, grossRewardCad: Double, fxCostCad: Double,
                netValueCad: Double, floorNetValueCad: Double, aspirationalNetValueCad: Double,
                warnings: [Warning], excluded: Bool, exclusionReason: String?) {
        self.snapshotVersion = snapshotVersion
        self.asOf = asOf
        self.cardId = cardId
        self.appliedRule = appliedRule
        self.programId = programId
        self.unit = unit
        self.centsPerPoint = centsPerPoint
        self.rewardUnits = rewardUnits
        self.grossRewardCad = grossRewardCad
        self.fxCostCad = fxCostCad
        self.netValueCad = netValueCad
        self.floorNetValueCad = floorNetValueCad
        self.aspirationalNetValueCad = aspirationalNetValueCad
        self.warnings = warnings
        self.excluded = excluded
        self.exclusionReason = exclusionReason
    }

    /// Builds a snapshot from a score and the card it scored.
    ///
    /// Resolves the applied rule out of the card by id rather than taking it as a parameter, so
    /// the frozen rule is always the one the catalogue actually held for that id at this moment.
    public static func capture(score: CandidateScore, card: CardProduct, asOf: String,
                               programId: String, unit: String,
                               centsPerPoint: Double?) -> ScoredRuleSnapshot {
        let rule = score.appliedRuleId.flatMap { id in
            card.earnRules.first { $0.ruleId == id }
        }
        return ScoredRuleSnapshot(
            asOf: asOf, cardId: score.cardId, appliedRule: rule,
            programId: programId, unit: unit, centsPerPoint: centsPerPoint,
            rewardUnits: score.rewardUnits, grossRewardCad: score.grossRewardCad,
            fxCostCad: score.fxCostCad, netValueCad: score.netValueCad,
            floorNetValueCad: score.floorNetValueCad,
            aspirationalNetValueCad: score.aspirationalNetValueCad,
            warnings: score.warnings, excluded: score.excluded,
            exclusionReason: score.exclusionReason)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd Engine && swift test --filter ScoredRuleSnapshotTests`
Expected: PASS (5 tests)

- [ ] **Step 5: Confirm no fixture drift**

Run: `cd Engine && swift test`
Expected: PASS. `engine-fixtures.json` is untouched; if any fixture test fails, stop — this task must be purely additive.

- [ ] **Step 6: Commit**

```bash
git add Engine/Sources/CardCopilotEngine/Models/ScoredRuleSnapshot.swift Engine/Tests/CardCopilotEngineTests/ScoredRuleSnapshotTests.swift
git commit -m "feat(engine): freeze the rule and valuation that produced a score"
```

---

### Task 3: Store schema V2

The highest-risk task in this plan. `StoredPrediction` is the one record that cannot be recomputed. Read `Store/Sources/CardCopilotStore/Schema.swift` in full before starting — its doc comments describe exactly the situation this task is in.

**Files:**
- Modify: `Store/Sources/CardCopilotStore/Schema.swift`
- Modify: `Store/Sources/CardCopilotStore/Models.swift`
- Test: `Store/Tests/CardCopilotStoreTests/SchemaVersionTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `CardCopilotSchemaV2`; `StoredPrediction` gains `contractRelease: String?`, `contractDigest: String?`, `frozenInputs: Data?`, and its `init` gains those three as trailing defaulted parameters. Task 4 passes them.

**Critical constraints:**
- Do NOT edit the `v1Shape` table. Add a separate `v2Shape`.
- All three new properties are optional. This keeps the migration `.lightweight`.
- Pre-provenance rows are NOT backfilled. `contractRelease == nil` is the queryable meaning of "scored before provenance existed", and inventing values would corrupt the exact measurement this protects.

- [ ] **Step 1: Write the failing tests**

Add to `Store/Tests/CardCopilotStoreTests/SchemaVersionTests.swift`. Keep every existing test and the `v1Shape` table exactly as they are, except `testMigrationPlanStartsAtV1`, which is replaced in Step 5.

```swift
    /// Entity name → sorted property names, as V2 ships. V1's table above stays frozen.
    private static let v2Shape: [String: [String]] = [
        "AreaMember": ["area", "identifier", "latitude", "longitude", "name", "poiCategoryRaw"],
        "ExploredCell": ["areaCount", "cellKey", "exploredAt"],
        "ShoppingArea": ["cellKey", "centroidLatitude", "centroidLongitude", "discoveredAt",
                         "id", "members", "radiusMeters"],
        "StoredMerchant": ["confirmationCount", "confirmedCategory", "id", "identifier",
                           "lastSeenAt", "latitude", "longitude", "name", "poiCategoryRaw"],
        "StoredObservation": ["confirmedAt", "id", "missClassRaw", "note", "observedCategory",
                              "observedRewardUnits", "purchase"],
        "StoredPrediction": ["confidenceSourceRaw", "contractDigest", "contractRelease",
                             "defaultCardValueCad", "frozenInputs", "headline", "id",
                             "merchantIdentifier", "merchantName", "predictedCategory",
                             "predictedRewardUnitKind", "predictedRewardUnits", "purchase",
                             "recordedAt", "runnerUpCardId", "runnerUpValueCad", "scoredAmountCad",
                             "valuationCentsPerPoint", "winnerCardId", "winnerRuleId",
                             "winnerValueCad"],
        "StoredPurchase": ["amountCad", "amountSourceRaw", "cardSourceRaw", "cardUsedId",
                           "completedAt", "createdAt", "id", "observation", "prediction"],
    ]

    func testV2RegistersEveryModel() {
        XCTAssertEqual(CardCopilotSchemaV2.models.count, Self.v2Shape.count,
                       "A model was added or removed without updating CardCopilotSchemaV2.models.")
    }

    func testV2EntityShapeIsAsDeclared() {
        let entities = Schema(versionedSchema: CardCopilotSchemaV2.self).entities
        let actual = Dictionary(uniqueKeysWithValues:
            entities.map { ($0.name, $0.properties.map(\.name).sorted()) })

        XCTAssertEqual(Set(actual.keys), Set(Self.v2Shape.keys))
        for (name, expected) in Self.v2Shape {
            XCTAssertEqual(actual[name], expected, "Entity '\(name)' is not the declared V2 shape.")
        }
    }

    /// V2 adds exactly three properties to exactly one entity. Anything else riding along in
    /// this migration is a mistake — every other entity must be untouched.
    func testV2ChangesOnlyStoredPrediction() {
        for (name, v1Properties) in Self.v1Shape where name != "StoredPrediction" {
            XCTAssertEqual(Self.v2Shape[name], v1Properties,
                           "Entity '\(name)' changed in V2. Only StoredPrediction should.")
        }
        let added = Set(Self.v2Shape["StoredPrediction"]!)
            .subtracting(Self.v1Shape["StoredPrediction"]!)
        XCTAssertEqual(added, ["contractRelease", "contractDigest", "frozenInputs"])
    }

    func testMigrationPlanCarriesV1ToV2() {
        XCTAssertEqual(CardCopilotMigrationPlan.schemas.count, 2)
        XCTAssertTrue(CardCopilotMigrationPlan.schemas[0] == CardCopilotSchemaV1.self)
        XCTAssertTrue(CardCopilotMigrationPlan.schemas[1] == CardCopilotSchemaV2.self)
        XCTAssertEqual(CardCopilotMigrationPlan.stages.count, 1,
                       "A V2 with no stage is how a store gets orphaned.")
    }

    /// The test that actually matters. Writes a store under V1, closes it, reopens it under V2
    /// with the migration plan, and confirms the row survived with its new fields nil.
    /// `testContainerOpensWithVersionedSchemaAndPlan` proves the plan is well-formed;
    /// only this proves the stage carries real data.
    func testV1StoreOpensUnderV2WithRowsIntact() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("provenance-migration-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let v1 = try ModelContainer(
                for: Schema(versionedSchema: CardCopilotSchemaV1.self),
                configurations: ModelConfiguration(url: url))
            let context = ModelContext(v1)
            context.insert(StoredPrediction(merchantName: "Loblaws",
                                            predictedCategory: "grocery",
                                            confidenceSource: .brandPrior,
                                            winnerCardId: "amex-cobalt",
                                            winnerValueCad: 2.50,
                                            headline: "Cobalt"))
            try context.save()
        }

        let v2 = try ModelContainer(
            for: Schema(versionedSchema: CardCopilotSchemaV2.self),
            migrationPlan: CardCopilotMigrationPlan.self,
            configurations: ModelConfiguration(url: url))
        let migrated = try ModelContext(v2).fetch(FetchDescriptor<StoredPrediction>())

        XCTAssertEqual(migrated.count, 1, "The V1 row did not survive migration.")
        XCTAssertEqual(migrated[0].merchantName, "Loblaws")
        XCTAssertNil(migrated[0].contractRelease,
                     "Pre-provenance rows must stay nil — a backfilled value would be invented.")
        XCTAssertNil(migrated[0].frozenInputs)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd Store && swift test --filter SchemaVersionTests`
Expected: FAIL — "cannot find 'CardCopilotSchemaV2' in scope"

- [ ] **Step 3: Move the models to V2**

In `Store/Sources/CardCopilotStore/Models.swift`, change the extension declaration from `extension CardCopilotSchemaV1 {` to `extension CardCopilotSchemaV2 {`. Do the same in `Store/Sources/CardCopilotStore/DiscoveryCache.swift` for the spatial-cache models.

V1's models are then declared by the historical schema alone — see Step 4.

- [ ] **Step 4: Declare V2 and keep V1's shape available**

In `Store/Sources/CardCopilotStore/Schema.swift`, keep `CardCopilotSchemaV1` exactly as it is and add:

```swift
/// Version 2 of the on-device store: provenance on `StoredPrediction`.
///
/// Adds `contractRelease`, `contractDigest`, and `frozenInputs`. All three are optional, which is
/// what makes the stage `.lightweight` — SwiftData can add a nullable column without rewriting
/// rows. Rows written under V1 arrive here with all three nil, and that is their correct value:
/// they were scored before provenance existed, and `contractRelease == nil` is the queryable
/// predicate that keeps them out of any per-release accuracy figure.
public enum CardCopilotSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            StoredPrediction.self,
            StoredPurchase.self,
            StoredObservation.self,
            StoredMerchant.self,
            ExploredCell.self,
            ShoppingArea.self,
            AreaMember.self,
        ]
    }
}
```

Update the migration plan in the same file:

```swift
public enum CardCopilotMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [CardCopilotSchemaV1.self, CardCopilotSchemaV2.self]
    }

    /// Lightweight because every added property is optional. `.custom` would be required only if
    /// data had to be rewritten — and there is nothing to rewrite: a pre-provenance row's correct
    /// provenance is "none".
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: CardCopilotSchemaV1.self, toVersion: CardCopilotSchemaV2.self)]
    }
}
```

Then repoint the typealiases at the bottom of the file from `CardCopilotSchemaV1.` to `CardCopilotSchemaV2.` for all seven types. This single edit is what moves ~195 call sites to the new shape at once.

**Note on V1's model types:** `CardCopilotSchemaV1.models` must still resolve. Since the `@Model` classes now live under V2, V1 needs its own declarations of the shapes it shipped. Declare them as a nested `extension CardCopilotSchemaV1` in `Schema.swift` holding the seven V1 classes with exactly the properties listed in `v1Shape` — no new fields. If that duplication proves impractical in SwiftData, stop and report back rather than editing `v1Shape` to make a test pass.

- [ ] **Step 5: Update the V1 plan assertion**

Replace `testMigrationPlanStartsAtV1` with:

```swift
    func testV1DeclaresAVersionIdentifierAndStaysFirst() {
        XCTAssertEqual(CardCopilotSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertTrue(CardCopilotMigrationPlan.schemas[0] == CardCopilotSchemaV1.self,
                      "V1 must remain the starting point or installed stores have nothing to migrate from.")
    }
```

- [ ] **Step 6: Add the properties**

In `Models.swift`, add to `StoredPrediction` after `valuationCentsPerPoint`:

```swift
        /// The contract release that scored this prediction, e.g. `card-contracts@1.6`.
        ///
        /// Flat rather than inside `frozenInputs` because the accuracy claim aggregates over it —
        /// "what was our hit rate under 1.6?" is a predicate across many rows, and a blob would
        /// force decoding every one. Nil means the row predates provenance; it is never backfilled.
        public private(set) var contractRelease: String?
        /// The digest of the contract bytes, recorded alongside the release id so the row is
        /// self-verifying against RELEASE.json rather than trusting a version string.
        public private(set) var contractDigest: String?
        /// The winning card's `ScoredRuleSnapshot`, JSON-encoded. Opaque here on purpose: the
        /// snapshot's shape is contract semantics and versions itself, so widening it must never
        /// require a store migration.
        public private(set) var frozenInputs: Data?
```

Add the three parameters to `init`, after `valuationCentsPerPoint` and before `headline`:

```swift
                    contractRelease: String? = nil, contractDigest: String? = nil,
                    frozenInputs: Data? = nil,
```

and the matching assignments in the body:

```swift
            self.contractRelease = contractRelease
            self.contractDigest = contractDigest
            self.frozenInputs = frozenInputs
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd Store && swift test --filter SchemaVersionTests`
Expected: PASS, including `testV1StoreOpensUnderV2WithRowsIntact`

- [ ] **Step 8: Run the full Store suite**

Run: `cd Store && swift test`
Expected: PASS — 69 existing + 5 new. Existing tests should be unaffected: the new parameters are defaulted.

- [ ] **Step 9: Commit**

```bash
git add Store/Sources/CardCopilotStore/Schema.swift Store/Sources/CardCopilotStore/Models.swift Store/Sources/CardCopilotStore/DiscoveryCache.swift Store/Tests/CardCopilotStoreTests/SchemaVersionTests.swift
git commit -m "feat(store): schema V2 carries prediction provenance"
```

---

### Task 4: Capture provenance at the write site

**Files:**
- Modify: `Store/Sources/CardCopilotStore/CheckoutService.swift:150`
- Test: `Store/Tests/CardCopilotStoreTests/ProvenanceCaptureTests.swift`

**Interfaces:**
- Consumes: `SeedLoader.loadContractRelease()` (Task 1); `ScoredRuleSnapshot.capture(score:card:asOf:programId:unit:centsPerPoint:)` (Task 2); `StoredPrediction.init(..., contractRelease:contractDigest:frozenInputs:...)` (Task 3).
- Produces: nothing later tasks depend on.

**Design note — read this before writing code.** Two traps here:

1. `CheckoutService` does **not** store the catalogue. It holds `engine`, `explainer`, `log`, `context`, `mrCentsPerPoint`, `defaultCardId`, and `rewardUnitKinds`, all derived in `init` from the `catalogue:` parameter. So the winning `CardProduct` must be looked up from a new index built in `init`, exactly as `rewardUnitKinds` already is.
2. `mrCentsPerPoint` is **Amex Membership Rewards specific** — it is `ownerState.valuationsCad[points: "amexMembershipRewards"]`. Freezing it as the snapshot's valuation would record an MR rate against a cashback or Aeroplan winner. The snapshot needs the valuation for *the winning card's own program*.

`primary.winner` is the `CandidateScore` and `asOf` is already a parameter. Load the release stamp **once** at init; it cannot change while the process runs.

- [ ] **Step 1: Write the failing test**

Create `Store/Tests/CardCopilotStoreTests/ProvenanceCaptureTests.swift`:

```swift
import XCTest
import SwiftData
import CardCopilotEngine
@testable import CardCopilotStore

final class ProvenanceCaptureTests: XCTestCase {

    /// Mirrors the construction in `CheckoutServiceTests.setUpWithError` exactly — the live seed,
    /// not a pinned fixture, because this test asserts on the release the build actually ships.
    private func makeService() throws -> (CheckoutService, ModelContext) {
        let container = try ModelContainer(
            for: StoredPrediction.self, StoredPurchase.self, StoredObservation.self,
                StoredMerchant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let service = CheckoutService(catalogue: try SeedLoader.loadCatalogue(),
                                      ownerState: try SeedLoader.loadOwnerState(),
                                      context: context)
        return (service, context)
    }

    private func merchant(_ name: String, poi: String?) -> NearbyMerchant {
        NearbyMerchant(id: "poi-1", name: name, poiCategoryRaw: poi,
                       latitude: 43.65, longitude: -79.38, distanceMeters: 40)
    }

    func testRecommendStampsTheContractRelease() throws {
        let (service, context) = try makeService()
        let expected = try SeedLoader.loadContractRelease()

        _ = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket"),
                                  amountCad: 140, asOf: "2026-08-26")

        let stored = try context.fetch(FetchDescriptor<StoredPrediction>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].contractRelease, expected.release)
        XCTAssertEqual(stored[0].contractDigest, expected.digest)
    }

    func testRecommendFreezesTheWinningRule() throws {
        let (service, context) = try makeService()

        _ = try service.recommend(merchant: merchant("Loblaws", poi: "MKPOICategoryFoodMarket"),
                                  amountCad: 140, asOf: "2026-08-26")

        let stored = try context.fetch(FetchDescriptor<StoredPrediction>())
        let blob = try XCTUnwrap(stored[0].frozenInputs, "the winning rule was not frozen")
        let snapshot = try JSONDecoder().decode(ScoredRuleSnapshot.self, from: blob)

        XCTAssertEqual(snapshot.cardId, stored[0].winnerCardId)
        XCTAssertEqual(snapshot.appliedRule?.ruleId, stored[0].winnerRuleId)
        XCTAssertEqual(snapshot.asOf, "2026-08-26")
        XCTAssertEqual(snapshot.netValueCad, stored[0].winnerValueCad, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Store && swift test --filter ProvenanceCaptureTests`
Expected: FAIL — `contractRelease` is nil

- [ ] **Step 3: Load the stamp once at init**

In `CheckoutService.swift`, add a stored property alongside `log`:

```swift
    /// The contract release this build ships. Loaded once: it cannot change while the process
    /// runs, and re-reading it per checkout would be a bundle read on the critical path.
    private let contractRelease: ContractRelease?
    /// The winning card has to be resolvable to freeze the rule it won on. Indexed here for the
    /// same reason `rewardUnitKinds` is: the catalogue is an init parameter, not a stored one.
    private let cardsById: [String: CardProduct]
    /// programId -> the owner's valuation for that program. Keyed by program rather than reusing
    /// `mrCentsPerPoint`, which is Membership Rewards only: freezing an MR rate against a
    /// cashback winner would record a valuation that never applied to it.
    private let programCentsPerPoint: [String: Double]
```

and in `init`, after `self.log = PredictionLog(context: context)`:

```swift
        // A missing stamp must not block a checkout. Provenance is a property of the record,
        // not a precondition for giving advice — an unstamped row is honest about being unstamped.
        self.contractRelease = try? SeedLoader.loadContractRelease()
        self.cardsById = Dictionary(uniqueKeysWithValues: catalogue.cards.map { ($0.cardId, $0) })
        self.programCentsPerPoint = Dictionary(
            catalogue.cards.compactMap { card -> (String, Double)? in
                guard let cpp = ownerState.valuationsCad[points: card.program.programId]?.centsPerPoint
                else { return nil }
                return (card.program.programId, cpp)
            }, uniquingKeysWith: { first, _ in first })
```

- [ ] **Step 4: Capture at the write site**

In `recommend(merchant:amountCad:asOf:)`, immediately before `let stored = try log.record(...)`:

```swift
        let frozen = cardsById[primary.winner.cardId].map { card in
            ScoredRuleSnapshot.capture(score: primary.winner, card: card, asOf: asOf,
                                       programId: card.program.programId,
                                       unit: card.program.unit,
                                       centsPerPoint: programCentsPerPoint[card.program.programId])
        }
```

Then extend the `StoredPrediction(...)` call, adding after `valuationCentsPerPoint: mrCentsPerPoint,`:

```swift
            contractRelease: contractRelease?.release,
            contractDigest: contractRelease?.digest,
            frozenInputs: frozen.flatMap { try? JSONEncoder().encode($0) },
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd Store && swift test --filter ProvenanceCaptureTests`
Expected: PASS (2 tests)

- [ ] **Step 6: Run the full Store suite**

Run: `cd Store && swift test`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add Store/Sources/CardCopilotStore/CheckoutService.swift Store/Tests/CardCopilotStoreTests/ProvenanceCaptureTests.swift
git commit -m "feat(store): stamp and freeze provenance on every prediction"
```

---

### Task 5: Card-level tombstoning

**Files:**
- Modify: `Engine/Sources/CardCopilotEngine/Models/CatalogueModels.swift`
- Modify: `Engine/Sources/CardCopilotEngine/Engine/Scorer.swift`
- Modify: `contracts/schema/card-catalogue.schema.json`
- Test: `Engine/Tests/CardCopilotEngineTests/TombstoneTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `CardStatus` (`.active` / `.withdrawn`); `CardProduct.status: CardStatus?` and `CardProduct.effectiveTo: String?`; `CardProduct.isScoreable(asOf:) -> Bool`.

**Critical:** do NOT reuse `RuleStatus`. It is `current` / `announced` — a rule-lifecycle concept, not a product-lifecycle one. Conflating them would make `status: "announced"` meaningful on a card, which it is not.

Both properties are optional so that a catalogue written before tombstoning still decodes — the same pattern `CardProduct.credits` already uses. Absent `status` means active.

- [ ] **Step 1: Write the failing test**

Create `Engine/Tests/CardCopilotEngineTests/TombstoneTests.swift`:

```swift
import XCTest
@testable import CardCopilotEngine

final class TombstoneTests: XCTestCase {

    private func card(status: CardStatus?, effectiveTo: String?) -> CardProduct {
        CardProduct(cardId: "dead-card", officialName: "Discontinued", issuer: "Test",
                    network: .visa, kind: .credit, fee: Fee(annualCad: 0),
                    program: Program(programId: "cash", unit: "cad"),
                    fxRules: [], earnRules: [], caps: [],
                    perTransactionRewardVisibility: "none", lastVerifiedAt: "2026-08-15",
                    credits: nil, status: status, effectiveTo: effectiveTo)
    }

    /// A card written before tombstoning existed has no status and must keep scoring.
    func testAbsentStatusMeansActive() {
        XCTAssertTrue(card(status: nil, effectiveTo: nil).isScoreable(asOf: "2026-08-26"))
    }

    func testWithdrawnCardIsNotScoreable() {
        XCTAssertFalse(card(status: .withdrawn, effectiveTo: "2026-01-01")
            .isScoreable(asOf: "2026-08-26"))
    }

    /// Withdrawal is dated: before the date the product was real and must still score, so
    /// historical asOf queries stay correct.
    func testWithdrawnCardStillScoresBeforeItsEndDate() {
        XCTAssertTrue(card(status: .withdrawn, effectiveTo: "2026-12-31")
            .isScoreable(asOf: "2026-08-26"))
    }

    /// The whole point of tombstoning: the id keeps resolving so history can render.
    func testWithdrawnCardStillDecodesAndKeepsItsIdentity() throws {
        let withdrawn = card(status: .withdrawn, effectiveTo: "2026-01-01")
        let data = try JSONEncoder().encode(withdrawn)
        let decoded = try JSONDecoder().decode(CardProduct.self, from: data)
        XCTAssertEqual(decoded.cardId, "dead-card")
        XCTAssertEqual(decoded.officialName, "Discontinued")
        XCTAssertEqual(decoded.status, .withdrawn)
    }

    /// Every card in the shipped catalogue must be scoreable today, or the catalogue is
    /// carrying a tombstone that was never meant to be one.
    func testShippedCatalogueHasNoUnexpectedTombstones() throws {
        let catalogue = try SeedLoader.loadCatalogue()
        let withdrawn = catalogue.cards.filter { $0.status == .withdrawn }
        XCTAssertTrue(withdrawn.allSatisfy { $0.effectiveTo != nil },
                      "A withdrawn card must say when it was withdrawn: \(withdrawn.map(\.cardId))")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Engine && swift test --filter TombstoneTests`
Expected: FAIL — "cannot find type 'CardStatus' in scope"

- [ ] **Step 3: Add the type and properties**

In `CatalogueModels.swift`, add next to the other catalogue enums at the top:

```swift
/// A card product's lifecycle, distinct from `RuleStatus` (which is `current`/`announced` and
/// describes a rule, not a product). Absent means active: a catalogue written before tombstoning
/// existed must keep scoring unchanged.
public enum CardStatus: String, Codable, Sendable { case active, withdrawn }
```

Add to `CardProduct`, after `credits`:

```swift
    /// Set when the issuer has discontinued the product. The card is never deleted from the
    /// catalogue and its id is never reused: ledgers, prediction rows, and other repos' vendored
    /// copies all key on that id, and an id that stops resolving turns history into orphans.
    public var status: CardStatus?
    /// The date the product stopped being available. Scoring respects it, so an `asOf` before
    /// this date still scores the card exactly as it scored at the time.
    public var effectiveTo: String?

    /// Whether this product can win a pick on the given date.
    ///
    /// Dated rather than a flat boolean so that historical `asOf` queries stay truthful — a card
    /// withdrawn last month was a legitimate answer the month before.
    public func isScoreable(asOf: String) -> Bool {
        guard status == .withdrawn else { return true }
        guard let effectiveTo else { return false }
        return asOf <= effectiveTo
    }
```

`CardProduct` uses the compiler-synthesised memberwise initialiser, so both properties must be added in the position the test's initialiser call expects — last, after `credits`.

- [ ] **Step 4: Exclude withdrawn cards from scoring**

In `Scorer.score(card:purchase:ownerState:asOf:)`, add immediately before the `acceptedNetworks` guard:

```swift
        guard card.isScoreable(asOf: asOf) else {
            return excludedScore(.drawerCard, "product withdrawn")
        }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd Engine && swift test --filter TombstoneTests`
Expected: PASS (5 tests)

- [ ] **Step 6: Update the contract schema**

In `contracts/schema/card-catalogue.schema.json`, add to the card object's `properties` (do not add either to `required` — both are optional):

```json
        "status": { "enum": ["active", "withdrawn"] },
        "effectiveTo": { "type": "string", "format": "date" }
```

- [ ] **Step 7: Run the full Engine suite**

Run: `cd Engine && swift test`
Expected: PASS. No catalogue card is withdrawn yet, so no scoring result changes and the golden fixtures are unaffected. If any fixture test fails, stop — the guard is firing when it should not.

- [ ] **Step 8: Commit**

```bash
git add Engine/Sources/CardCopilotEngine/Models/CatalogueModels.swift Engine/Sources/CardCopilotEngine/Engine/Scorer.swift contracts/schema/card-catalogue.schema.json Engine/Tests/CardCopilotEngineTests/TombstoneTests.swift
git commit -m "feat(contracts): withdrawn cards are tombstoned, never deleted"
```

---

### Task 6: CI gate for id permanence

"Ids are permanent" is a promise. A promise nothing enforces is one that breaks the first busy week.

**Files:**
- Create: `scripts/check-id-permanence.sh`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: the tombstoning semantics from Task 5 (a withdrawn card stays present).
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Write the script**

Create `scripts/check-id-permanence.sh`:

```bash
#!/usr/bin/env bash
# Fails when a cardId that a published release contained has vanished from the working catalogue.
#
# WHY
#
# Card ids are keyed on by prediction rows, owner state, MoneyTalks, and the Android consumer.
# A withdrawn product is tombstoned (status: withdrawn) and keeps its id forever; it is never
# deleted and never reused. That rule is cheap to state and easy to break during a cleanup, and
# nothing else in the pipeline notices — the catalogue still validates, the tests still pass, and
# the damage only appears on a device holding history for an id nobody defines any more.
#
#   scripts/check-id-permanence.sh              # compare against the latest published release
#   scripts/check-id-permanence.sh <release>    # compare against a specific one
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${CATALOGUE_REPO:-zubairmuwwakil/PickMe}"

command -v gh >/dev/null 2>&1 || { echo "check-id-permanence: gh CLI not found" >&2; exit 1; }

release="${1:-}"
if [ -z "$release" ]; then
  release="$(gh release list --repo "$REPO" --limit 1 --json tagName -q '.[0].tagName' 2>/dev/null || true)"
fi

if [ -z "$release" ]; then
  echo "check-id-permanence: no published release to compare against — nothing to enforce yet"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! gh release download "$release" --repo "$REPO" --pattern card-catalogue.json --dir "$tmp" 2>/dev/null; then
  echo "check-id-permanence: could not download card-catalogue.json from $release" >&2
  exit 1
fi

published_ids="$(node -e 'require(process.argv[1]).cards.forEach(c=>console.log(c.cardId))' "$tmp/card-catalogue.json" | sort)"
working_ids="$(node -e 'require(process.argv[1]).cards.forEach(c=>console.log(c.cardId))' "$ROOT/contracts/card-catalogue.json" | sort)"

missing="$(comm -23 <(echo "$published_ids") <(echo "$working_ids"))"

if [ -n "$missing" ]; then
  echo "check-id-permanence: these cardIds were in $release and are gone from contracts/card-catalogue.json:" >&2
  echo "$missing" | sed 's/^/  /' >&2
  echo "check-id-permanence:" >&2
  echo "check-id-permanence: card ids are permanent. A discontinued product is tombstoned, not" >&2
  echo "check-id-permanence: deleted — set \"status\": \"withdrawn\" and \"effectiveTo\", and leave" >&2
  echo "check-id-permanence: the card in place. Prediction rows and other repos key on these ids." >&2
  exit 1
fi

echo "check-id-permanence: every cardId in $release is still present ($(echo "$working_ids" | wc -l | tr -d ' ') cards)"
```

- [ ] **Step 2: Make it executable and run it**

```bash
chmod +x scripts/check-id-permanence.sh
scripts/check-id-permanence.sh
```

Expected: PASS — "every cardId in card-contracts@1.6 is still present"

- [ ] **Step 3: Prove the gate actually catches a deletion**

```bash
node -e 'const f="contracts/card-catalogue.json";const c=require("./"+f);c.cards.shift();require("fs").writeFileSync(f,JSON.stringify(c,null,2))'
scripts/check-id-permanence.sh; echo "exit=$?"
git checkout contracts/card-catalogue.json
```

Expected: FAIL listing the removed cardId, `exit=1`. Then the checkout restores the file — confirm with `git status` that `contracts/` is clean before continuing.

- [ ] **Step 4: Wire it into CI**

In `.github/workflows/ci.yml`, add a step to the same job that runs the existing contract stamp gate, following that step's style:

```yaml
      - name: Card ids are permanent
        run: scripts/check-id-permanence.sh
        env:
          GH_TOKEN: ${{ github.token }}
```

- [ ] **Step 5: Verify the workflow parses**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('ok')"`
Expected: `ok`

- [ ] **Step 6: Commit**

```bash
git add scripts/check-id-permanence.sh .github/workflows/ci.yml
git commit -m "feat(ci): card ids are permanent, and CI now says so"
```

---

## Task dependency order

```
Task 1 (stamp) ─┐
Task 2 (snapshot) ─┼─→ Task 4 (capture)
Task 3 (schema V2) ─┘

Task 5 (tombstoning) — independent
Task 6 (CI gate) — independent, but its failure message describes Task 5's semantics
```

**Known collision:** Task 2's test fixtures build `CardProduct` with the compiler-synthesised memberwise initialiser, and Task 5 adds two properties to that struct. Whichever of the two lands second must add `status: nil, effectiveTo: nil` to the `CardProduct(...)` calls in `ScoredRuleSnapshotTests.swift`. This is a one-line fix, not a design problem — but it will surface as a compile error, so expect it.

Tasks 1, 2, 3, and 5 can proceed in parallel. Task 4 needs all of 1–3 merged. Task 6 is best done after Task 5 so the remediation message it prints matches shipped behaviour.
