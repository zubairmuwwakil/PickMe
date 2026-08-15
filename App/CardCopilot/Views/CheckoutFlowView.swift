import SwiftUI
import SwiftData
import CardCopilotEngine
import CardCopilotStore

/// The core loop: find or search the merchant, capture the amount, show the answer.
struct CheckoutFlowView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var stage: Stage = .idle
    @State private var deps: Dependencies?
    @State private var locationDenied = false

    enum Stage {
        case idle
        case locating
        case confirming(merchants: [NearbyMerchant])
        case amount(merchant: NearbyMerchant)
        case recommendation(CheckoutResult)
        case failed(String)
    }

    struct Dependencies {
        let catalogue: Catalogue
        let service: CheckoutService
        let explainer: RecommendationExplainer
        let provider: LiveMerchantProvider
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Card Copilot")
        }
        .task { loadDependencies() }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .idle:
            IdleView(locationDenied: locationDenied,
                     onFindNearby: { Task { await findNearby() } },
                     onSearch: { text in Task { await search(text) } })
        case .locating:
            ProgressView("Finding nearby merchants…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .confirming(let merchants):
            MerchantConfirmView(merchants: merchants,
                                onConfirm: { stage = .amount(merchant: $0) },
                                onSearch: { text in Task { await search(text) } },
                                onCancel: { stage = .idle })
        case .amount(let merchant):
            AmountCaptureView(merchantName: merchant.name,
                              onAmount: { amount in recommend(merchant: merchant, amount: amount) },
                              onCancel: { stage = .idle })
        case .recommendation(let result):
            RecommendationView(result: result,
                               deps: deps,
                               onDone: { stage = .idle })
        case .failed(let message):
            ContentUnavailableView("Something went wrong", systemImage: "exclamationmark.triangle",
                                   description: Text(message))
            Button("Start over") { stage = .idle }
        }
    }

    private func loadDependencies() {
        guard deps == nil else { return }
        do {
            let catalogue = try SeedLoader.loadCatalogue()
            let owner = try SeedLoader.loadOwnerState()
            deps = Dependencies(
                catalogue: catalogue,
                service: CheckoutService(catalogue: catalogue, ownerState: owner,
                                         context: modelContext),
                explainer: RecommendationExplainer(catalogue: catalogue),
                provider: LiveMerchantProvider())
        } catch {
            stage = .failed("Seed data failed to load: \(error.localizedDescription)")
        }
    }

    private func findNearby() async {
        guard let deps else { return }
        stage = .locating
        do {
            let location = try await LocationProvider().requestLocation()
            let merchants = try await deps.provider.nearby(latitude: location.latitude,
                                                           longitude: location.longitude)
            stage = merchants.isEmpty
                ? .failed("No merchants found nearby — try manual search.")
                : .confirming(merchants: merchants)
        } catch is LocationUnavailable {
            // Permission declined: Apple requires the manual path to stand on its own.
            locationDenied = true
            stage = .idle
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func search(_ text: String) async {
        guard let deps, !text.isEmpty else { return }
        stage = .locating
        do {
            let merchants = try await deps.provider.search(text: text)
            stage = merchants.isEmpty
                ? .failed("Nothing found for “\(text)”.")
                : .confirming(merchants: merchants)
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }

    private func recommend(merchant: NearbyMerchant, amount: Double?) {
        guard let deps else { return }
        do {
            let today = Date().formatted(.iso8601.year().month().day())
            stage = .recommendation(try deps.service.recommend(merchant: merchant,
                                                               amountCad: amount,
                                                               asOf: today))
        } catch {
            stage = .failed(error.localizedDescription)
        }
    }
}

private struct IdleView: View {
    let locationDenied: Bool
    let onFindNearby: () -> Void
    let onSearch: (String) -> Void
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Button(action: onFindNearby) {
                Label("What card should I use here?", systemImage: "location")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(locationDenied)

            if locationDenied {
                Text("Location is off — search for the merchant instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                TextField("Search a merchant…", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { onSearch(searchText) }
                Button("Search") { onSearch(searchText) }
                    .disabled(searchText.isEmpty)
            }
            Spacer()
        }
        .padding()
    }
}
