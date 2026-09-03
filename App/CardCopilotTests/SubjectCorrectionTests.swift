import XCTest
import SwiftData
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

/// Home's "not this store" correction.
///
/// The negative signal nothing in the app previously captured. `retarget` already re-points the
/// answer card, but re-pointing says only "I want this one now"; it never said "the one you named
/// was wrong", which is the half that makes a correction ground truth.
@MainActor
final class SubjectCorrectionTests: XCTestCase {

    private final class StubLocationProvider: CheckoutLocationProviding {
        var authorizedLocation: CheckoutLocationFix?

        func requestLocation() async throws -> CheckoutLocationFix {
            guard let authorizedLocation else { throw LocationUnavailable.fixFailed("no stub fix") }
            return authorizedLocation
        }

        func requestLocationIfAuthorized() async throws -> CheckoutLocationFix? {
            authorizedLocation
        }
    }

    private actor StubMerchantProvider: MerchantProviding {
        let merchants: [NearbyMerchant]

        init(merchants: [NearbyMerchant]) { self.merchants = merchants }

        func nearby(latitude: Double, longitude: Double) async throws -> [NearbyMerchant] {
            merchants
        }

        func search(text: String) async throws -> [NearbyMerchant] { [] }
    }

    private func merchant(_ name: String, metresNorth: Double,
                          poiCategoryRaw: String? = nil) -> NearbyMerchant {
        NearbyMerchant(id: "poi.\(name)", name: name, poiCategoryRaw: poiCategoryRaw,
                       latitude: 45 + metresNorth / 111_000, longitude: -75,
                       distanceMeters: metresNorth)
    }

    private var notaries: NearbyMerchant { merchant("Bergeron Notaries", metresNorth: 12) }
    private var shoppers: NearbyMerchant {
        merchant("Shoppers Drug Mart", metresNorth: 40, poiCategoryRaw: "MKPOICategoryPharmacy")
    }

    private func makeGraph(provider: any MerchantProviding) throws -> DependencyGraph {
        let schema = Schema(versionedSchema: CardCopilotSchema.current)
        let container = try ModelContainer(
            for: schema, migrationPlan: CardCopilotMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        return DependencyGraph(
            catalogue: catalogue, candidateCardIds: [], ownerState: owner,
            benefits: try SeedLoader.loadBenefitsCatalogue(),
            service: CheckoutService(catalogue: catalogue, ownerState: owner,
                                     context: ModelContext(container)),
            explainer: RecommendationExplainer(catalogue: catalogue),
            engine: RecommendationEngine(catalogue: catalogue, ownerState: owner),
            provider: provider)
    }

    /// A session that has already scanned, so the answer card has a subject and the field log has
    /// the record that produced it.
    private func scannedSession(store: ArrivalFieldLogStore) async throws
    -> (CopilotSession, DependencyGraph) {
        let location = StubLocationProvider()
        location.authorizedLocation = CheckoutLocationFix(latitude: 45, longitude: -75,
                                                          horizontalAccuracyMeters: 12)
        let session = CopilotSession(
            locationProvider: location,
            nearbyMetricsStore: NearbyLookupMetricsStore(
                defaults: UserDefaults(suiteName: "SubjectCorrection.\(UUID().uuidString)")!),
            fieldLogStore: store)
        let graph = try makeGraph(provider: StubMerchantProvider(merchants: [notaries, shoppers]))
        await session.prefetchNearby(using: graph)
        return (session, graph)
    }

    private func makeFieldLogStore() -> ArrivalFieldLogStore {
        ArrivalFieldLogStore(
            defaults: UserDefaults(suiteName: "SubjectCorrectionLog.\(UUID().uuidString)")!)
    }

    // MARK: -

    /// Through the existing confirmation writer, which is what promotes the terminal to
    /// `.verified` — not a second one that would have to agree with it forever.
    func testChoosingTheRightStoreWritesOneConfirmedMerchant() async throws {
        let (session, graph) = try await scannedSession(store: makeFieldLogStore())

        session.correctSubject(rejected: HomeAnswerSubject(nearby: notaries),
                               chosen: HomeAnswerSubject(nearby: shoppers),
                               offered: [HomeAnswerSubject(nearby: shoppers)],
                               using: graph)

        let merchants = try graph.service.knownMerchants()
        XCTAssertEqual(merchants.count, 1)
        XCTAssertEqual(merchants[0].name, "Shoppers Drug Mart")
        XCTAssertEqual(merchants[0].confirmedCategory, "drugStore")
    }

    /// The store the owner rejected is left alone. A correction says which store they were in; it
    /// says nothing about what the other one sells, and writing a category for it would invent
    /// evidence.
    func testTheRejectedStoreIsNotWritten() async throws {
        let (session, graph) = try await scannedSession(store: makeFieldLogStore())

        session.correctSubject(rejected: HomeAnswerSubject(nearby: notaries),
                               chosen: HomeAnswerSubject(nearby: shoppers),
                               offered: [HomeAnswerSubject(nearby: shoppers)],
                               using: graph)

        XCTAssertFalse(try graph.service.knownMerchants()
            .contains { $0.name == "Bergeron Notaries" })
    }

    /// A brand named from the offline index is not a terminal — it has no coordinates and its id
    /// is the brand. Confirming it would make a brand-wide claim out of a terminal-level one,
    /// which the truth graph explicitly forbids. The correction is still recorded.
    func testChoosingABrandWithNoRealLocationConfirmsNoTerminal() async throws {
        let store = makeFieldLogStore()
        let (session, graph) = try await scannedSession(store: store)
        let brand = NearbyMerchant(id: "preindex:pharmaprix", name: "Pharmaprix",
                                   poiCategoryRaw: nil, latitude: 0, longitude: 0,
                                   distanceMeters: nil)

        session.correctSubject(rejected: HomeAnswerSubject(nearby: notaries),
                               chosen: HomeAnswerSubject(nearby: brand, provenance: .searched),
                               offered: [HomeAnswerSubject(nearby: brand,
                                                            provenance: .searched)],
                               using: graph)

        XCTAssertTrue(try graph.service.knownMerchants().isEmpty)
        XCTAssertEqual(store.all().first?.correction?.chosenName, "Pharmaprix")
    }

    /// Appended to the record that produced the subject, not to a new one. The record already
    /// holds the candidate set and the ranking; the correction is what turns it into a labelled
    /// example.
    func testTheCorrectionIsAppendedToTheRecordThatProducedTheSubject() async throws {
        let store = makeFieldLogStore()
        let (session, graph) = try await scannedSession(store: store)

        session.correctSubject(rejected: HomeAnswerSubject(nearby: notaries),
                               chosen: HomeAnswerSubject(nearby: shoppers),
                               offered: [HomeAnswerSubject(nearby: shoppers)],
                               using: graph)

        XCTAssertEqual(store.all().count, 1)
        let correction = try XCTUnwrap(store.all()[0].correction)
        XCTAssertEqual(correction.rejectedName, "Bergeron Notaries")
        XCTAssertEqual(correction.chosenName, "Shoppers Drug Mart")
        XCTAssertEqual(correction.offeredNames, ["Shoppers Drug Mart"])
        // The rank is the payload: the right answer was one place down the list.
        XCTAssertEqual(correction.chosenCandidateIndex, 1)
    }

    /// The record keeps saying the app named the notary. Rewriting it to the truth would erase the
    /// only thing it is evidence of.
    func testCorrectingDoesNotRewriteWhatTheAppOriginallyAnswered() async throws {
        let store = makeFieldLogStore()
        let (session, graph) = try await scannedSession(store: store)

        session.correctSubject(rejected: HomeAnswerSubject(nearby: notaries),
                               chosen: HomeAnswerSubject(nearby: shoppers),
                               offered: [HomeAnswerSubject(nearby: shoppers)],
                               using: graph)

        XCTAssertEqual(store.all()[0].resolvedMerchantName, "Bergeron Notaries")
        XCTAssertEqual(store.all()[0].chosenCandidateIndex, 0)
    }
}
