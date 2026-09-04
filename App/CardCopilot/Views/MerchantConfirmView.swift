import SwiftUI
import CardCopilotStore

/// Ranked nearby merchant list — lets the user confirm which merchant they are standing in.
struct MerchantConfirmView: View {
    let merchants: [NearbyPlace]
    let onConfirm: (NearbyPlace) -> Void
    let onSearch: (String) -> Void
    let onCancel: () -> Void
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                ForEach(merchants) { merchant in
                    let prediction = CardCopilotStore.predict(poiCategoryRaw: merchant.poiCategoryRaw, merchantName: merchant.name)
                    let meta = CategoryVisuals.meta(for: prediction.category)
                    let formattedPoi = meta.displayName

                    Button {
                        onConfirm(merchant)
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(meta.color.opacity(0.14))
                                    .frame(width: 42, height: 42)
                                Image(systemName: meta.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(meta.color)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(merchant.name)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)

                                HStack(spacing: 6) {
                                    if let d = merchant.distanceMeters {
                                        HStack(spacing: 3) {
                                            Image(systemName: "location.fill")
                                                .font(.system(size: 9))
                                            Text("\(Int(d)) m away")
                                        }
                                    }
                                    if merchant.distanceMeters != nil {
                                        Text("•")
                                    }
                                    Text(formattedPoi)
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Select your location")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
            } footer: {
                Text("Selecting the exact merchant helps PickMe determine the precise MCC and terminal rules.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search different merchant…")
        .onSubmit(of: .search) {
            if let text = SearchSubmission.query(from: searchText) { onSearch(text) }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }
}
