import SwiftUI
import CardCopilotEngine
import CardCopilotStore
import SwiftData

@main
struct CardCopilotApp: App {
    var body: some Scene {
        WindowGroup {
            EngineSmokeTestView()
        }
        .modelContainer(for: [StoredPrediction.self, StoredObservation.self, StoredMerchant.self])
    }
}

/// Task 1 placeholder: proves the engine package links and its seed resources load
/// inside an iOS app bundle. Replaced by HomeView in Task 6.
struct EngineSmokeTestView: View {
    @State private var status: String = "loading…"
    @State private var headline: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Card Copilot").font(.largeTitle.bold())
                Text(status).font(.headline).foregroundStyle(.secondary)
                if !headline.isEmpty {
                    Text(headline).font(.body).padding(.top, 8)
                }
                #if DEBUG
                MerchantDetectionDebugView()
                #endif
            }
            .padding()
        }
        .task {
            do {
                let catalogue = try SeedLoader.loadCatalogue()
                let owner = try SeedLoader.loadOwnerState()
                let engine = RecommendationEngine(catalogue: catalogue, ownerState: owner)
                let explainer = RecommendationExplainer(catalogue: catalogue)
                let purchase = PurchaseContext(amountCad: 140, category: "grocery", mcc: 5411,
                                               merchantBrand: "loblaws")
                let recommendation = engine.recommend(purchase, asOf: "2026-08-20")
                status = "Engine linked — \(catalogue.cards.count) cards loaded"
                headline = explainer.explain(recommendation, purchase: purchase).headline
            } catch {
                status = "Engine failed to load: \(error)"
            }
        }
    }
}

#if DEBUG
/// Task 4 verification harness: drives `LocationProvider` → `LiveMerchantProvider.nearby`
/// and exercises `search` directly. Not part of the shipping UI — Task 5 replaces this with
/// `MerchantConfirmView`.
struct MerchantDetectionDebugView: View {
    @State private var nearbyStatus = "idle"
    @State private var nearbyResults: [NearbyMerchant] = []
    @State private var searchText = ""
    @State private var searchStatus = "idle"
    @State private var searchResults: [NearbyMerchant] = []

    private let locationProvider = LocationProvider()
    private let merchantProvider = LiveMerchantProvider()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().padding(.vertical, 4)
            Text("Merchant detection (debug)").font(.headline)

            Button("Find nearby (debug)") {
                Task { await findNearby() }
            }
            Text(nearbyStatus).font(.caption).foregroundStyle(.secondary)
            ForEach(nearbyResults) { merchant in
                VStack(alignment: .leading, spacing: 2) {
                    Text(merchant.name).font(.subheadline.bold())
                    Text("\(merchant.poiCategoryRaw ?? "unknown category") · \(distanceText(merchant.distanceMeters))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider().padding(.vertical, 4)

            Text("Manual search (debug)").font(.headline)
            TextField("Search merchants", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await runSearch() } }
            Text(searchStatus).font(.caption).foregroundStyle(.secondary)
            ForEach(searchResults) { merchant in
                Text("\(merchant.name) · \(merchant.poiCategoryRaw ?? "unknown category")")
                    .font(.subheadline)
            }
        }
    }

    private func findNearby() async {
        nearbyStatus = "locating…"
        do {
            let coordinate = try await locationProvider.requestLocation()
            nearbyStatus = "searching…"
            let results = try await merchantProvider.nearby(latitude: coordinate.latitude,
                                                             longitude: coordinate.longitude)
            nearbyResults = rankNearbyMerchants(results)
            nearbyStatus = "\(nearbyResults.count) nearby"
        } catch LocationUnavailable.permissionDenied, LocationUnavailable.permissionRestricted {
            nearbyStatus = "location denied — use manual search below"
        } catch {
            nearbyStatus = "error: \(error)"
        }
    }

    private func runSearch() async {
        guard !searchText.isEmpty else { return }
        searchStatus = "searching…"
        do {
            let results = try await merchantProvider.search(text: searchText)
            searchResults = rankNearbyMerchants(results)
            searchStatus = "\(searchResults.count) results"
        } catch {
            searchStatus = "error: \(error)"
        }
    }

    private func distanceText(_ meters: Double?) -> String {
        guard let meters else { return "distance unknown" }
        return String(format: "%.0f m", meters)
    }
}
#endif
