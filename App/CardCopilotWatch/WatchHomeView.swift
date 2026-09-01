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

    private var contextualSuggestion: (title: String, categoryId: String, name: String, icon: String, amount: Double) {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<11:
            return ("Morning Coffee", "dining", "Coffee & Bites", "cup.and.saucer.fill", 8.0)
        case 11..<15:
            return ("Lunch Hour", "dining", "Lunch Dining", "fork.knife", 25.0)
        case 15..<20:
            return ("Evening Groceries", "grocery", "Groceries", "cart.fill", 90.0)
        default:
            return ("Quick Checkout", "dining", "Dining & Eats", "fork.knife", 30.0)
        }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        WatchRecommendationView(
                            categoryName: contextualSuggestion.name,
                            categoryId: contextualSuggestion.categoryId,
                            icon: contextualSuggestion.icon,
                            amountCad: contextualSuggestion.amount
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(contextualSuggestion.title.uppercased())
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(.blue)
                                Spacer()
                                Image(systemName: contextualSuggestion.icon)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.blue)
                            }
                            Text(contextualSuggestion.name)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                }

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
