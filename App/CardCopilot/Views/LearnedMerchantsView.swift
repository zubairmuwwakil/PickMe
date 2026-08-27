import SwiftUI
import CardCopilotStore

/// Lists every merchant PickMe has learned the owner frequents, from Wallet captures alone — no
/// amount, no card, no coordinate, per `MerchantPatronageStore`'s retention promise. Swiping a
/// row forgets it; "Never learn this place" additionally stops it from ever re-accruing standing.
struct LearnedMerchantsView: View {
    let onDone: () -> Void

    @State private var merchants: [MerchantPatronageStore.LearnedMerchant] = []
    private let store = MerchantPatronageStore()

    var body: some View {
        List {
            if merchants.isEmpty {
                Section {
                    Text(String(localized: "learned-merchants.empty",
                                defaultValue: "PickMe hasn't learned any merchants yet. Arrival alerts get more confident once you've paid at the same place a few times."))
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(merchants) { merchant in
                        row(for: merchant)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    forget(merchant)
                                } label: {
                                    Label(String(localized: "learned-merchants.forget",
                                                 defaultValue: "Forget"), systemImage: "trash")
                                }
                                Button {
                                    block(merchant)
                                } label: {
                                    Label(String(localized: "learned-merchants.never-learn",
                                                 defaultValue: "Never learn this place"),
                                          systemImage: "hand.raised.slash")
                                }
                                .tint(.orange)
                            }
                    }
                } footer: {
                    Text(String(localized: "learned-merchants.footer",
                                defaultValue: "Standing is based only on which days you paid there — never the amount, the card, or where you were."))
                }
            }
        }
        .navigationTitle(String(localized: "learned-merchants.title", defaultValue: "Learned merchants"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "common.done", defaultValue: "Done"), action: onDone)
                    .font(.headline)
            }
        }
        .onAppear(perform: reload)
    }

    private func row(for merchant: MerchantPatronageStore.LearnedMerchant) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(merchant.displayName)
                .font(.body.weight(.semibold))
            HStack(spacing: 6) {
                if merchant.qualifies {
                    Label(String(localized: "learned-merchants.qualifies",
                                 defaultValue: "Recognized"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    let template = String(localized: "learned-merchants.progress",
                                          defaultValue: "%d of %d visits")
                    Label(String(format: template, merchant.visitCount, patronageVisitDaysRequired),
                          systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private func reload() {
        merchants = store.learnedMerchants().sorted { $0.latestDayKey > $1.latestDayKey }
    }

    private func forget(_ merchant: MerchantPatronageStore.LearnedMerchant) {
        store.forget(merchantKey: merchant.merchantKey)
        reload()
    }

    private func block(_ merchant: MerchantPatronageStore.LearnedMerchant) {
        store.block(merchantKey: merchant.merchantKey)
        reload()
    }
}
