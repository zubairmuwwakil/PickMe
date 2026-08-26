import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// A dynamic, glanceable checkout tile for an Instant Repeat merchant.
/// Displays the winning card, calculation, network constraints, and an interactive amount simulator.
struct InstantRepeatCardView: View {
    let merchant: StoredMerchant
    let deps: CheckoutFlowView.Dependencies
    let onLogPurchase: (StoredMerchant, Double) -> Void
    let onOpenDetails: (StoredMerchant, Double) -> Void

    @State private var selectedAmount: Double = 50
    @State private var isCustomInputActive = false
    @State private var customAmountText = ""
    @FocusState private var isCustomFocused: Bool

    private let presets: [Double] = [10, 25, 50, 100]

    private var evaluation: InstantRepeatEvaluation? {
        InstantRepeatAdvisor.evaluate(
            merchant: merchant,
            amountCad: selectedAmount,
            catalogue: deps.catalogue,
            ownerState: deps.ownerState,
            engine: deps.engine
        )
    }

    private var meta: CategoryVisuals.Meta {
        CategoryVisuals.meta(for: merchant.confirmedCategory ?? merchant.poiCategoryRaw ?? "general")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - Header Row: Merchant & Category
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(meta.color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: meta.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(meta.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(merchant.name)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if let networkBadge = evaluation?.networkBadge {
                            Text(networkBadge)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }

                    HStack(spacing: 6) {
                        Text(evaluation?.formattedCategory ?? meta.displayName)
                        Text("•")
                        Text(CategoryVisuals.relativeTime(from: merchant.lastSeenAt))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Details button
                Button {
                    onOpenDetails(merchant, selectedAmount)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View full card breakdown")
            }

            // MARK: - Winning Card Display
            if let eval = evaluation {
                Button {
                    onOpenDetails(merchant, selectedAmount)
                } label: {
                    HStack(spacing: 12) {
                        CardMiniBadge(cardId: eval.winnerCardId, size: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(eval.winnerCardName)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(eval.multiplierText)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
                            }

                            Text(eval.calculationText)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "$%.2f", eval.returnCad))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.green)
                            Text("back")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
                }
                .buttonStyle(.plain)
            }

            // MARK: - Interactive Amount Bar
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Text("Amount:")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    ForEach(presets, id: \.self) { preset in
                        let isSelected = !isCustomInputActive && selectedAmount == preset
                        Button {
                            withAnimation(.spring(duration: 0.25)) {
                                isCustomInputActive = false
                                isCustomFocused = false
                                selectedAmount = preset
                            }
                        } label: {
                            Text("$\(Int(preset))")
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    isSelected
                                        ? Color.blue
                                        : Color(.tertiarySystemFill),
                                    in: Capsule()
                                )
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }

                    // Custom Amount Button
                    Button {
                        withAnimation(.spring(duration: 0.25)) {
                            isCustomInputActive.toggle()
                            if isCustomInputActive {
                                customAmountText = "\(Int(selectedAmount))"
                                isCustomFocused = true
                            } else {
                                isCustomFocused = false
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .bold))
                            if isCustomInputActive && !presets.contains(selectedAmount) {
                                Text("$\(Int(selectedAmount))")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                            } else {
                                Text("Custom")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            isCustomInputActive && !presets.contains(selectedAmount)
                                ? Color.blue
                                : Color(.tertiarySystemFill),
                            in: Capsule()
                        )
                        .foregroundStyle(isCustomInputActive && !presets.contains(selectedAmount) ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                // Inline Custom Amount Editor
                if isCustomInputActive {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("$")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            TextField("Amount", text: $customAmountText)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .keyboardType(.decimalPad)
                                .focused($isCustomFocused)
                                .onSubmit { applyCustomAmount() }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))

                        Button("Set") {
                            applyCustomAmount()
                        }
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            // MARK: - Action Buttons
            HStack(spacing: 8) {
                Button {
                    onLogPurchase(merchant, selectedAmount)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .bold))
                        Text("Log $\(Int(selectedAmount)) on \(shortCardName)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: Color.blue.opacity(0.25), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)

                Button {
                    onOpenDetails(merchant, selectedAmount)
                } label: {
                    HStack(spacing: 4) {
                        Text("Pick")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        )
    }

    private var shortCardName: String {
        guard let winnerId = evaluation?.winnerCardId else { return "Card" }
        return CardVisualTheme.style(for: winnerId).shortName
    }

    private func applyCustomAmount() {
        if let val = Double(customAmountText.replacingOccurrences(of: "$", with: "").trimmingCharacters(in: .whitespaces)), val > 0 {
            withAnimation(.spring(duration: 0.25)) {
                selectedAmount = val
                isCustomFocused = false
            }
        }
    }
}
