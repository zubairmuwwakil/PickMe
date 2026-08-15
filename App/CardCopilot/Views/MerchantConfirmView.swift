import SwiftUI
import CardCopilotStore

/// Ranked nearby list — the user confirms rather than the app guessing. Search stays
/// available here too: the nearest POI is not always the right one inside a mall.
struct MerchantConfirmView: View {
    let merchants: [NearbyMerchant]
    let onConfirm: (NearbyMerchant) -> Void
    let onSearch: (String) -> Void
    let onCancel: () -> Void
    @State private var searchText = ""

    var body: some View {
        List {
            Section("Which merchant are you at?") {
                ForEach(merchants) { merchant in
                    Button { onConfirm(merchant) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(merchant.name).font(.body.weight(.medium))
                            HStack(spacing: 6) {
                                if let d = merchant.distanceMeters {
                                    Text("\(Int(d)) m")
                                }
                                if let raw = merchant.poiCategoryRaw {
                                    Text(raw.replacingOccurrences(of: "MKPOICategory", with: ""))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Not listed? Search…")
        .onSubmit(of: .search) { onSearch(searchText) }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}
