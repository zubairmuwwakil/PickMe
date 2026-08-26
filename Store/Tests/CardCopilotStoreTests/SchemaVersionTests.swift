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

    func testV1DeclaresAVersionIdentifier() {
        XCTAssertEqual(CardCopilotSchemaV1.versionIdentifier, Schema.Version(1, 0, 0))
    }

    /// The migration plan must name V1, or `ModelContainer` has no starting point to migrate from
    /// and the plan is inert decoration.
    func testMigrationPlanStartsAtV1() {
        XCTAssertEqual(CardCopilotMigrationPlan.schemas.count, 1)
        XCTAssertTrue(CardCopilotMigrationPlan.schemas[0] == CardCopilotSchemaV1.self)
        XCTAssertTrue(CardCopilotMigrationPlan.stages.isEmpty,
                      "V1 is the first version; there is nothing to migrate from yet.")
    }

    /// Exercises the exact pairing the app uses, so a schema/plan mismatch fails here rather than
    /// at launch on someone's phone.
    func testContainerOpensWithVersionedSchemaAndPlan() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: CardCopilotSchemaV1.self),
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
}
