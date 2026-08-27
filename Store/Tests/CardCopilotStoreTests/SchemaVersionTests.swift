import XCTest
import SwiftData
@testable import CardCopilotStore

/// Guards the SwiftData store's identity across releases.
///
/// SwiftData keys a persisted store on the entity names and property shapes it derives from the
/// model types. Those names are therefore a contract with every device that has already written
/// a `StoredPrediction` — and unlike the card catalogue, that contract has no version field to
/// refuse on, no fixture harness, and no second language asserting it. A rename that reaches an
/// installed build does not fail loudly; it orphans the prediction log, which is the one record
/// in this app that cannot be recomputed from anything else.
///
/// So the table below is a baseline, not documentation. It was captured from the running schema
/// before the models moved into `CardCopilotSchemaV1`, which is the point: it proves the move was
/// shape-preserving rather than asserting that it was.
final class SchemaVersionTests: XCTestCase {

    /// Entity name → sorted property names, as V1 ships.
    ///
    /// Editing an entry here is never the fix for a failing test in this file. A changed shape is
    /// a migration: add `CardCopilotSchemaV2`, add the `MigrationStage` that carries owners across,
    /// and leave V1's recorded shape alone. Silencing the diff by retyping the table is how a
    /// store stops being readable by the build that wrote it.
    private static let v1Shape: [String: [String]] = [
        "AreaMember": ["area", "identifier", "latitude", "longitude", "name", "poiCategoryRaw"],
        "ExploredCell": ["areaCount", "cellKey", "exploredAt"],
        "ShoppingArea": ["cellKey", "centroidLatitude", "centroidLongitude", "discoveredAt",
                         "id", "members", "radiusMeters"],
        "StoredMerchant": ["confirmationCount", "confirmedCategory", "id", "identifier",
                           "lastSeenAt", "latitude", "longitude", "name", "poiCategoryRaw"],
        "StoredObservation": ["confirmedAt", "id", "missClassRaw", "note", "observedCategory",
                              "observedRewardUnits", "purchase"],
        "StoredPrediction": ["confidenceSourceRaw", "defaultCardValueCad", "headline", "id",
                             "merchantIdentifier", "merchantName", "predictedCategory",
                             "predictedRewardUnitKind", "predictedRewardUnits", "purchase",
                             "recordedAt", "runnerUpCardId", "runnerUpValueCad", "scoredAmountCad",
                             "valuationCentsPerPoint", "winnerCardId", "winnerRuleId",
                             "winnerValueCad"],
        "StoredPurchase": ["amountCad", "amountSourceRaw", "cardSourceRaw", "cardUsedId",
                           "completedAt", "createdAt", "id", "observation", "prediction"],
    ]

    /// Entity name → sorted property names, as V2 ships. V1's table above stays frozen.
    ///
    /// This is a second baseline, not a replacement for the first. Both must keep passing: V1's
    /// table describes the bytes already on someone's phone, V2's describes what the app writes
    /// now, and the migration stage is the claim that the first can become the second.
    private static let v2Shape: [String: [String]] = [
        "AreaMember": ["area", "identifier", "latitude", "longitude", "name", "poiCategoryRaw"],
        "ExploredCell": ["areaCount", "cellKey", "exploredAt"],
        "ShoppingArea": ["cellKey", "centroidLatitude", "centroidLongitude", "discoveredAt",
                         "id", "members", "radiusMeters"],
        "StoredMerchant": ["confirmationCount", "confirmedCategory", "id", "identifier",
                           "lastSeenAt", "latitude", "longitude", "name", "poiCategoryRaw"],
        "StoredObservation": ["confirmedAt", "id", "missClassRaw", "note", "observedCategory",
                              "observedRewardUnits", "purchase"],
        "StoredPrediction": ["categoryCorrectedAt", "confidenceSourceRaw", "contractDigest", "contractRelease",
                             "defaultCardValueCad", "frozenInputs", "headline", "id",
                             "merchantIdentifier", "merchantName", "predictedCategory",
                             "predictedRewardUnitKind", "predictedRewardUnits", "purchase",
                             "recordedAt", "runnerUpCardId", "runnerUpValueCad", "scoredAmountCad",
                             "valuationCentsPerPoint", "winnerCardId", "winnerRuleId",
                             "winnerValueCad"],
        "StoredPurchase": ["amountCad", "amountSourceRaw", "cardSourceRaw", "cardUsedId",
                           "completedAt", "createdAt", "id", "observation", "prediction"],
    ]

    /// Entity name → sorted property names, as V3 ships. V1's and V2's tables above stay frozen.
    private static let v3Shape: [String: [String]] = [
        "AreaMember": ["area", "identifier", "latitude", "longitude", "name", "poiCategoryRaw"],
        "ExploredCell": ["areaCount", "cellKey", "exploredAt"],
        "ShoppingArea": ["cellKey", "centroidLatitude", "centroidLongitude", "discoveredAt",
                         "id", "members", "radiusMeters"],
        "StoredMerchant": ["confirmationCount", "confirmedCategory", "id", "identifier",
                           "lastSeenAt", "latitude", "longitude", "name", "poiCategoryRaw"],
        "StoredObservation": ["confirmedAt", "id", "missClassRaw", "note", "observedCategory",
                              "observedRewardUnits", "purchase"],
        "StoredPrediction": ["categoryCorrectedAt", "confidenceSourceRaw", "contractDigest", "contractRelease",
                             "defaultCardValueCad", "frozenInputs", "headline", "id",
                             "merchantIdentifier", "merchantName", "predictedCategory",
                             "predictedRewardUnitKind", "predictedRewardUnits", "purchase",
                             "recordedAt", "runnerUpCardId", "runnerUpValueCad", "scoredAmountCad",
                             "valuationCentsPerPoint", "winnerCardId", "winnerRuleId",
                             "winnerValueCad"],
        "StoredPurchase": ["amountCad", "amountSourceRaw", "cardSourceRaw", "cardUsedId",
                           "completedAt", "createdAt", "id", "merchantLabel", "observation",
                           "prediction", "walletEventId"],
    ]

    /// The failure this catches is adding an eighth `@Model` and not registering it. Such a model
    /// compiles, and every test that builds its own `ModelContainer(for:)` passes, because those
    /// name their types directly. It fails only on a real device, where the app's container is
    /// built from `CardCopilotSchemaV1.models` and simply has no table for the new type.
    func testV1RegistersEveryModel() {
        XCTAssertEqual(CardCopilotSchemaV1.models.count, Self.v1Shape.count,
                       "A model was added or removed without updating CardCopilotSchemaV1.models.")
    }

    func testV1EntityShapeIsUnchanged() {
        let entities = Schema(versionedSchema: CardCopilotSchemaV1.self).entities
        let actual = Dictionary(uniqueKeysWithValues:
            entities.map { ($0.name, $0.properties.map(\.name).sorted()) })

        XCTAssertEqual(Set(actual.keys), Set(Self.v1Shape.keys),
                       "V1's entity names changed. This is a migration, not an edit to the baseline.")

        for (name, expected) in Self.v1Shape {
            XCTAssertEqual(actual[name], expected,
                           "Entity '\(name)' changed shape. This is a migration, not an edit to the baseline.")
        }
    }

    /// V1 keeps its identifier and its place at the head of the plan. It is no longer the version
    /// the app opens, but it is still the version installed stores were written at, so removing it
    /// from the plan would leave those stores with nothing to migrate *from*.
    func testV1DeclaresAVersionIdentifierAndStaysFirst() {
        XCTAssertEqual(CardCopilotSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
        XCTAssertTrue(CardCopilotMigrationPlan.schemas[0] == CardCopilotSchemaV1.self,
                      "V1 must remain the starting point or installed stores have nothing to migrate from.")
    }

    /// Exercises the exact pairing the app uses, so a schema/plan mismatch fails here rather than
    /// at launch on someone's phone.
    ///
    /// It opens at `CardCopilotSchema.current`, not at a version named literally: a container is
    /// keyed by the model *types* in its schema, so opening at V1 while the unqualified
    /// `StoredPrediction` means V2's class is a mismatch this test would otherwise sail past.
    func testContainerOpensWithVersionedSchemaAndPlan() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: CardCopilotSchema.current),
            migrationPlan: CardCopilotMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))

        let context = ModelContext(container)
        context.insert(StoredPrediction(merchantName: "Loblaws",
                                        predictedCategory: "grocery",
                                        confidenceSource: .brandPrior,
                                        winnerCardId: "amex-cobalt",
                                        winnerValueCad: 2.50,
                                        headline: "Cobalt"))
        try context.save()

        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredPrediction>()).count, 1)
    }

    // MARK: - V2: provenance on StoredPrediction

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

    /// V2 adds exactly four properties to exactly one entity. Anything else riding along in
    /// this migration is a mistake — every other entity must be untouched.
    func testV2ChangesOnlyStoredPrediction() {
        for (name, v1Properties) in Self.v1Shape where name != "StoredPrediction" {
            XCTAssertEqual(Self.v2Shape[name], v1Properties,
                           "Entity '\(name)' changed in V2. Only StoredPrediction should.")
        }
        let added = Set(Self.v2Shape["StoredPrediction"]!)
            .subtracting(Self.v1Shape["StoredPrediction"]!)
        XCTAssertEqual(added, ["contractRelease", "contractDigest", "frozenInputs",
                               "categoryCorrectedAt"])
    }

    /// V1's entity names are unchanged in V2 on purpose: SwiftData keys a persisted store on them,
    /// so a rename here is what orphans the log. Adding columns is safe; renaming tables is not.
    func testV2KeepsEveryV1EntityName() {
        XCTAssertEqual(Set(Self.v2Shape.keys), Set(Self.v1Shape.keys),
                       "An entity was renamed, added, or dropped in V2. That is not a lightweight change.")
    }

    /// V1 and V2 must be *different* classes, not the same seven listed twice.
    ///
    /// If `CardCopilotSchemaV1.models` were ever pointed back at the live types — the obvious
    /// shortcut once the duplication starts to look like waste — `Schema(versionedSchema:)` would
    /// report V2's shape for V1, and `testV1StoreOpensUnderV2WithRowsIntact` would silently stop
    /// testing a migration: it would write a V2 store and then open a V2 store, and pass. This is
    /// the assertion that keeps the historical shapes historical.
    func testV1AndV2DeclareDistinctModelTypes() {
        let v1 = Set(CardCopilotSchemaV1.models.map(ObjectIdentifier.init))
        let v2 = Set(CardCopilotSchemaV2.models.map(ObjectIdentifier.init))
        XCTAssertTrue(v1.isDisjoint(with: v2),
                      "V1's frozen model types must not be the live ones, or the migration test proves nothing.")
    }

    /// Relationships must resolve to the classes belonging to their own schema version.
    func testRelationshipsStayWithinTheirSchemaVersion() {
        let v1Purchase: KeyPath<CardCopilotSchemaV1.StoredPrediction, CardCopilotSchemaV1.StoredPurchase?> = \.purchase
        let v2Purchase: KeyPath<CardCopilotSchemaV2.StoredPrediction, CardCopilotSchemaV2.StoredPurchase?> = \.purchase
        let v3Purchase: KeyPath<CardCopilotSchemaV3.StoredPrediction, CardCopilotSchemaV3.StoredPurchase?> = \.purchase

        XCTAssertEqual(v1Purchase, \CardCopilotSchemaV1.StoredPrediction.purchase)
        XCTAssertEqual(v2Purchase, \CardCopilotSchemaV2.StoredPrediction.purchase)
        XCTAssertEqual(v3Purchase, \CardCopilotSchemaV3.StoredPrediction.purchase)
    }

    func testMigrationPlanCarriesV1ToV2ToV3() {
        XCTAssertEqual(CardCopilotMigrationPlan.schemas.count, 3)
        XCTAssertTrue(CardCopilotMigrationPlan.schemas[0] == CardCopilotSchemaV1.self)
        XCTAssertTrue(CardCopilotMigrationPlan.schemas[1] == CardCopilotSchemaV2.self)
        XCTAssertTrue(CardCopilotMigrationPlan.schemas[2] == CardCopilotSchemaV3.self)
        XCTAssertEqual(CardCopilotMigrationPlan.stages.count, 2,
                       "A version with no stage is how a store gets orphaned.")
    }

    /// `CardCopilotSchema.current` is the one place a version is named for callers. This catches
    /// the half-finished migration: a new version added to the plan while every container still
    /// opens at the old one.
    func testCurrentSchemaIsTheNewestInTheMigrationPlan() {
        XCTAssertTrue(CardCopilotSchema.current == CardCopilotSchemaV3.self)
        XCTAssertTrue(CardCopilotSchema.current == CardCopilotMigrationPlan.schemas.last!,
                      "The current schema must be the plan's newest, or new stores open behind the plan.")
    }

    /// The test that actually matters. Writes a store under V1, closes it, reopens it under V2
    /// with the migration plan, and confirms the row survived with its new fields nil.
    /// `testContainerOpensWithVersionedSchemaAndPlan` proves the plan is well-formed;
    /// only this proves the stage carries real data.
    ///
    /// The V1 row is inserted through `CardCopilotSchemaV1.StoredPrediction` by name. Writing it
    /// through the unqualified alias would insert V2's class into a V1 container — which is the
    /// mistake this test exists to catch, not a shortcut it can afford to take.
    func testV1StoreOpensUnderV2WithRowsIntact() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("provenance-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("CardCopilot.store")

        do {
            let v1 = try ModelContainer(
                for: Schema(versionedSchema: CardCopilotSchemaV1.self),
                migrationPlan: CardCopilotMigrationPlan.self,
                configurations: ModelConfiguration(url: url))
            let context = ModelContext(v1)
            context.insert(CardCopilotSchemaV1.StoredPrediction(merchantName: "Loblaws",
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
        let migrated = try ModelContext(v2).fetch(
            FetchDescriptor<CardCopilotSchemaV2.StoredPrediction>())

        XCTAssertEqual(migrated.count, 1, "The V1 row did not survive migration.")
        XCTAssertEqual(migrated[0].merchantName, "Loblaws")
        XCTAssertEqual(migrated[0].winnerCardId, "amex-cobalt")
        XCTAssertEqual(migrated[0].winnerValueCad, 2.50)
        XCTAssertNil(migrated[0].contractRelease,
                     "Pre-provenance rows must stay nil — a backfilled value would be invented.")
        XCTAssertNil(migrated[0].contractDigest)
        XCTAssertNil(migrated[0].frozenInputs)
        XCTAssertNil(migrated[0].categoryCorrectedAt)
    }

    /// The other half of the migration: a store already at V2 keeps accepting provenance, and a
    /// row written after the migration reads its stamp back. Without this, "the fields exist" and
    /// "the fields persist" are the same assertion — and only the first is true of a broken column.
    func testProvenanceRoundTripsThroughAReopenedStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("provenance-roundtrip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("CardCopilot.store")

        let frozen = Data(#"{"snapshotVersion":1}"#.utf8)
        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: CardCopilotSchema.current),
                migrationPlan: CardCopilotMigrationPlan.self,
                configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            context.insert(StoredPrediction(merchantName: "Loblaws",
                                            predictedCategory: "grocery",
                                            confidenceSource: .brandPrior,
                                            winnerCardId: "amex-cobalt",
                                            winnerValueCad: 2.50,
                                            contractRelease: "card-contracts@1.6",
                                            contractDigest: "sha256:abc123",
                                            frozenInputs: frozen,
                                            headline: "Cobalt"))
            try context.save()
        }

        let reopened = try ModelContainer(
            for: Schema(versionedSchema: CardCopilotSchema.current),
            migrationPlan: CardCopilotMigrationPlan.self,
            configurations: ModelConfiguration(url: url))
        let rows = try ModelContext(reopened).fetch(FetchDescriptor<StoredPrediction>())

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].contractRelease, "card-contracts@1.6")
        XCTAssertEqual(rows[0].contractDigest, "sha256:abc123")
        XCTAssertEqual(rows[0].frozenInputs, frozen)
    }

    // MARK: - V3: walletEventId and merchantLabel on StoredPurchase

    func testV3RegistersEveryModel() {
        XCTAssertEqual(CardCopilotSchemaV3.models.count, Self.v3Shape.count,
                       "A model was added or removed without updating CardCopilotSchemaV3.models.")
    }

    func testV3EntityShapeIsAsDeclared() {
        let entities = Schema(versionedSchema: CardCopilotSchemaV3.self).entities
        let actual = Dictionary(uniqueKeysWithValues:
            entities.map { ($0.name, $0.properties.map(\.name).sorted()) })

        XCTAssertEqual(Set(actual.keys), Set(Self.v3Shape.keys))
        for (name, expected) in Self.v3Shape {
            XCTAssertEqual(actual[name], expected, "Entity '\(name)' is not the declared V3 shape.")
        }
    }

    /// V3 adds exactly two properties to exactly one entity. Anything else riding along in this
    /// migration is a mistake — every other entity must be untouched.
    func testV3ChangesOnlyStoredPurchase() {
        for (name, v2Properties) in Self.v2Shape where name != "StoredPurchase" {
            XCTAssertEqual(Self.v3Shape[name], v2Properties,
                           "Entity '\(name)' changed in V3. Only StoredPurchase should.")
        }
        let added = Set(Self.v3Shape["StoredPurchase"]!)
            .subtracting(Self.v2Shape["StoredPurchase"]!)
        XCTAssertEqual(added, ["walletEventId", "merchantLabel"])
    }

    func testV3KeepsEveryV2EntityName() {
        XCTAssertEqual(Set(Self.v3Shape.keys), Set(Self.v2Shape.keys),
                       "An entity was renamed, added, or dropped in V3. That is not a lightweight change.")
    }

    /// V2 and V3 must be *different* classes, not the same seven listed twice — see
    /// `testV1AndV2DeclareDistinctModelTypes` for why.
    func testV2AndV3DeclareDistinctModelTypes() {
        let v2 = Set(CardCopilotSchemaV2.models.map(ObjectIdentifier.init))
        let v3 = Set(CardCopilotSchemaV3.models.map(ObjectIdentifier.init))
        XCTAssertTrue(v2.isDisjoint(with: v3),
                      "V2's frozen model types must not be the live ones, or the migration test proves nothing.")
    }

    /// Writes a store under V2, reopens it under V3 with the migration plan, and confirms the row
    /// survived with its two new fields nil — the counterpart to `testV1StoreOpensUnderV2WithRowsIntact`.
    ///
    /// The V2 row is inserted through `CardCopilotSchemaV2.StoredPurchase`/`StoredPrediction` by
    /// name, for the same reason the V1 test does: writing it through the unqualified alias would
    /// insert V3's class into a V2 container, which is the mistake this test exists to catch.
    func testV2StoreOpensUnderV3WithRowsIntact() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallet-capture-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("CardCopilot.store")

        do {
            let v2 = try ModelContainer(
                for: Schema(versionedSchema: CardCopilotSchemaV2.self),
                migrationPlan: CardCopilotMigrationPlan.self,
                configurations: ModelConfiguration(url: url))
            let context = ModelContext(v2)
            let prediction = CardCopilotSchemaV2.StoredPrediction(merchantName: "Loblaws",
                                                                   predictedCategory: "grocery",
                                                                   confidenceSource: .brandPrior,
                                                                   winnerCardId: "amex-cobalt",
                                                                   winnerValueCad: 2.50,
                                                                   headline: "Cobalt")
            context.insert(prediction)
            let purchase = CardCopilotSchemaV2.StoredPurchase()
            context.insert(purchase)
            purchase.prediction = prediction
            purchase.cardUsedId = "amex-cobalt"
            purchase.amountCad = 47.83
            try context.save()
        }

        let v3 = try ModelContainer(
            for: Schema(versionedSchema: CardCopilotSchemaV3.self),
            migrationPlan: CardCopilotMigrationPlan.self,
            configurations: ModelConfiguration(url: url))
        let migrated = try ModelContext(v3).fetch(FetchDescriptor<StoredPurchase>())

        XCTAssertEqual(migrated.count, 1, "The V2 row did not survive migration.")
        XCTAssertEqual(migrated[0].cardUsedId, "amex-cobalt")
        XCTAssertEqual(migrated[0].amountCad, 47.83)
        XCTAssertEqual(migrated[0].prediction?.merchantName, "Loblaws")
        XCTAssertNil(migrated[0].walletEventId,
                     "A pre-V3 purchase must stay nil, never backfilled as though it were auto-logged.")
        XCTAssertNil(migrated[0].merchantLabel)
    }

    /// The other half: a store already at V3 keeps accepting the new fields, and a purchase
    /// `AutoCaptureLog` writes reads them back after a reopen — mirrors
    /// `testProvenanceRoundTripsThroughAReopenedStore`.
    func testWalletCaptureProvenanceRoundTripsThroughAReopenedStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallet-capture-roundtrip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("CardCopilot.store")

        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: CardCopilotSchema.current),
                migrationPlan: CardCopilotMigrationPlan.self,
                configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            context.insert(StoredPurchase(createdAt: Date(timeIntervalSince1970: 1_755_000_000),
                                          merchantLabel: "Tim Hortons",
                                          walletEventId: "wallet-evt-1"))
            try context.save()
        }

        let reopened = try ModelContainer(
            for: Schema(versionedSchema: CardCopilotSchema.current),
            migrationPlan: CardCopilotMigrationPlan.self,
            configurations: ModelConfiguration(url: url))
        let rows = try ModelContext(reopened).fetch(FetchDescriptor<StoredPurchase>())

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].walletEventId, "wallet-evt-1")
        XCTAssertEqual(rows[0].merchantLabel, "Tim Hortons")
        XCTAssertEqual(rows[0].displayMerchant, "Tim Hortons")
        XCTAssertTrue(rows[0].isAutoLogged)
    }
}
