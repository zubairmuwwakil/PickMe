import SwiftUI
import CardCopilotEngine
import CardCopilotStore

public struct WatchHomeView: View {
    private struct CategoryItem: Identifiable {
        let id: String
        let name: String
        let icon: String
        let amount: Double
    }

    private let categories: [CategoryItem] = [
        .init(id: "grocery", name: "Groceries", icon: "cart.fill", amount: 100),
        .init(id: "dining", name: "Dining", icon: "fork.knife", amount: 40),
        .init(id: "gasStation", name: "Gas", icon: "fuelpump.fill", amount: 60),
        .init(id: "transit", name: "Transit", icon: "tram.fill", amount: 15),
        .init(id: "wholesaleClub", name: "Costco", icon: "building.2.fill", amount: 200),
        .init(id: "other", name: "Other", icon: "bag.fill", amount: 50)
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section("Which Card?") {
                    ForEach(categories) { item in
                        NavigationLink {
                            WatchRecommendationView(categoryName: item.name,
                                                    categoryId: item.id,
                                                    icon: item.icon,
                                                    amountCad: item.amount)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: item.icon)
                                    .foregroundStyle(.blue)
                                Text(item.name)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        WatchCapView()
                    } label: {
                        HStack {
                            Image(systemName: "gauge.with.needle.fill")
                                .foregroundStyle(.orange)
                            Text("Monthly Caps")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                }
            }
            .navigationTitle("PickMe")
        }
    }
}
