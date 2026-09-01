import SwiftUI

/// Amount, in place, on the answer already shown.
///
/// Replaces the old pre-answer `AmountCaptureView` gate (removed 2026-08-31): the owner sees a
/// category-estimate recommendation first, and this row is how they correct it if the estimate
/// is off, rather than a screen they clear before seeing anything. Collapsed, it states the
/// figure the answer was scored against and offers to change it. Expanded, it is the same
/// presets/custom-field/tax-chip controls the old gate had — refining is optional, never
/// required to see or act on an answer.
struct AmountRefineRow: View {
    let effectiveAmountCad: Double
    let amountWasEstimated: Bool
    let onRefine: (Double) -> Void

    @State private var isExpanded = false
    @State private var customText = ""
    @FocusState private var isInputFocused: Bool

    private let presets: [Double] = [10, 25, 50, 100, 200]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            collapsedSummary
            if isExpanded {
                expandedControls
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.blue.opacity(0.08))
        )
        .animation(.spring(duration: 0.3), value: isExpanded)
    }

    private var collapsedSummary: some View {
        Button {
            withAnimation { isExpanded.toggle() }
            if isExpanded { isInputFocused = true }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.blue)
                Text(summaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
            }
        }
        .buttonStyle(.plain)
    }

    private var summaryText: String {
        amountWasEstimated
            ? "Based on a typical ~$\(Int(effectiveAmountCad)) purchase. Enter the exact amount to refine this."
            : "Updated for $\(String(format: "%.2f", effectiveAmountCad))."
    }

    private var expandedControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { amount in
                    Button {
                        submit(amount)
                    } label: {
                        Text("$\(Int(amount))")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Text("$")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $customText)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .keyboardType(.decimalPad)
                        .focused($isInputFocused)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isInputFocused ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 1.5)
                        )
                )

                Button {
                    if let value = customAmount { submit(value) }
                } label: {
                    Text("Update")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(customAmount != nil ? Color.blue : Color.gray.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .disabled(customAmount == nil)
            }

            HStack(spacing: 6) {
                Text("Add Tax:")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                ForEach(SalesTaxHelper.presets.prefix(3), id: \.id) { preset in
                    Button {
                        let base = customAmount ?? 0
                        if base > 0 {
                            customText = String(format: "%.2f", SalesTaxHelper.addTax(base: base, ratePct: preset.ratePct))
                        }
                    } label: {
                        Text(preset.shortLabel)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(Capsule())
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var customAmount: Double? {
        guard let value = Double(customText.replacingOccurrences(of: "$", with: "")
            .trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value
    }

    private func submit(_ amount: Double) {
        onRefine(amount)
        withAnimation { isExpanded = false }
        customText = ""
        isInputFocused = false
    }
}
