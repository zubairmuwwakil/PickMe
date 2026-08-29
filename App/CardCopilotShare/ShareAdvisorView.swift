import SwiftUI
import CardCopilotEngine
import CardCopilotStore

public struct ShareAdvisorView: View {
    let url: URL?
    let pageTitle: String?
    let onDone: () -> Void

    @State private var sampleSpend: Double = 100.0

    private var domain: String {
        guard let host = url?.host?.lowercased() else {
            return pageTitle ?? "Online Checkout"
        }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    private var resolvedContext: (category: String, mcc: Int?, brand: String?, name: String) {
        let cleanDomain = domain.lowercased()

        if cleanDomain.contains("aircanada") {
            return ("travel", 3000, "air-canada", "Air Canada")
        } else if cleanDomain.contains("westjet") {
            return ("travel", 3001, "westjet", "WestJet")
        } else if cleanDomain.contains("porter") {
            return ("travel", 3002, "porter", "Porter Airlines")
        } else if cleanDomain.contains("amazon") {
            return ("other", 5999, "amazon", "Amazon Canada")
        } else if cleanDomain.contains("costco") {
            return ("wholesaleClub", 5300, "costco", "Costco.ca")
        } else if cleanDomain.contains("bestbuy") {
            return ("other", 5732, "bestbuy", "Best Buy")
        } else if cleanDomain.contains("apple.com") {
            return ("other", 5732, "apple", "Apple Store")
        } else if cleanDomain.contains("ubereats") || cleanDomain.contains("doordash") || cleanDomain.contains("skipthedishes") {
            return ("foodDelivery", 5814, nil, "Food Delivery")
        } else if cleanDomain.contains("loblaws") || cleanDomain.contains("metro") || cleanDomain.contains("sobeys") || cleanDomain.contains("voila") {
            return ("grocery", 5411, nil, "Online Grocery")
        } else if cleanDomain.contains("walmart") {
            return ("other", 5310, "walmart", "Walmart.ca")
        } else {
            // General online retailer
            return ("other", nil, nil, domain)
        }
    }

    public init(url: URL?, pageTitle: String? = nil, onDone: @escaping () -> Void) {
        self.url = url
        self.pageTitle = pageTitle
        self.onDone = onDone
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    merchantHeaderCard
                    winnerRecommendationCard
                    purchaseProtectionsSection
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("PickMe Online Advisor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone).font(.headline)
                }
            }
        }
    }

    private var merchantHeaderCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "globe")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(resolvedContext.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(resolvedContext.category.capitalized)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var winnerRecommendationCard: some View {
        let (cardName, headline, advantage) = evaluateWinner()

        return VStack(alignment: .leading, spacing: 12) {
            Label("Recommended Card", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.blue)

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(cardName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    if !headline.isEmpty {
                        Text(headline)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.teal)
                    }
                }
                Spacer()
                if let advantage {
                    Text(String(format: "+$%.2f", advantage))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private var purchaseProtectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Included Card Protections").font(.headline)

            let isTravel = resolvedContext.category == "travel"
            if isTravel {
                protectionRow(icon: "airplane.circle.fill", color: .purple,
                              title: "Flight Delay & Cancellation",
                              detail: "Compare this card's delay, cancellation, interruption, and baggage terms in PickMe.")
                protectionRow(icon: "cross.case.fill", color: .red,
                              title: "Out-of-Country Medical",
                              detail: "Check the certificate for destination, trip-length, age, and eligibility conditions.")
            } else {
                protectionRow(icon: "shield.lefthalf.filled.badge.checkmark", color: .indigo,
                              title: "Extended Warranty",
                              detail: "Warranty extensions and eligible original terms vary by card. Verify before buying.")
                protectionRow(icon: "lock.shield.fill", color: .teal,
                              title: "Purchase Protection",
                              detail: "Open PickMe to compare the certificate's purchase window, limits, deductible, and exclusions.")
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func protectionRow(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func evaluateWinner() -> (cardName: String, headline: String, advantageCad: Double?) {
        let catalogue = (try? SeedLoader.loadCatalogue()) ?? Catalogue.empty
        let ownerState = OwnerStateLocalStore().load()

        guard let ownerState else {
            return ("Add cards in PickMe", "Open app to set up wallet", nil)
        }

        let context = PurchaseContext(
            amountCad: sampleSpend,
            category: resolvedContext.category,
            mcc: resolvedContext.mcc,
            merchantBrand: resolvedContext.brand,
            channel: "online"
        )
        let today = Date().formatted(.iso8601.year().month().day())
        guard case .advised(let rec) = RecommendationEngine(catalogue: catalogue, ownerState: ownerState).recommend(context, asOf: today) else {
            return ("No recommendation", "Unable to advise for this wallet", nil)
        }
        let card = catalogue.cards.first(where: { $0.cardId == rec.winner.cardId })
        let explanation = RecommendationExplainer(catalogue: catalogue).explain(rec, purchase: context)
        return (card?.officialName ?? rec.winner.cardId, explanation.headline, rec.advantageOverDefaultCad)
    }
}
