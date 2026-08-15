import SwiftUI
import CardCopilotStore

struct HomeView: View {
    let valueRecoveredCad: Double
    let merchants: [StoredMerchant]
    let isSortedByRecentLocation: Bool
    let locationDenied: Bool
    let onInstantRepeat: (StoredMerchant) -> Void
    let onFindNearby: () -> Void
    let onSearch: (String) -> Void

    @State private var searchText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                primaryActions
                instantRepeats
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Value recovered")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(valueRecoveredText)
                .font(.largeTitle.bold())
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var primaryActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onFindNearby) {
                Label("Somewhere new", systemImage: "location")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(locationDenied)

            if locationDenied {
                Text("Location is off. Search still works.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                TextField("Search a merchant", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitSearch() }
                Button("Search") { submitSearch() }
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var instantRepeats: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Instant repeats")
                    .font(.title3.weight(.semibold))
                Spacer()
                if !merchants.isEmpty {
                    Label(isSortedByRecentLocation ? "Nearby" : "Recent",
                          systemImage: isSortedByRecentLocation ? "location.fill" : "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if merchants.isEmpty {
                ContentUnavailableView("No repeats yet",
                                       systemImage: "clock.arrow.circlepath",
                                       description: Text("Use Somewhere new or Search once, then this list becomes one tap."))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(merchants) { merchant in
                        Button {
                            onInstantRepeat(merchant)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.counterclockwise.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(merchant.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("Last seen \(merchant.lastSeenAt, style: .relative)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground),
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func submitSearch() {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSearch(text)
    }

    private var valueRecoveredText: String {
        String(format: "$%.2f so far", valueRecoveredCad)
    }
}
