import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// An Apple-grade interactive detail and inspection sheet for a single wallet card.
///
/// Features:
/// - Pristine hero card visual with ambient glow and glossy border
/// - 1-tap "Default Payment Card" status toggle with immediate haptic response
/// - Full earn rate & multiplier breakdown per category with icons
/// - Included annual statement credits and certificate-verified perks
/// - Active spend caps and custom condition rules
/// - Quick action shortcuts for wallet management
struct WalletCardDetailSheet: View {
    let card: CardProduct
    let isDefault: Bool
    let onSetDefault: () -> Void
    let onOpenConditions: () -> Void
    let onRemoveCard: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(CopilotEnvironment.self) private var environment

    @State private var showingRemoveAlert = false
    @State private var isDefaultLocal: Bool = false
    @State private var accountOpenedDate = Date()
    @State private var hasAccountOpenedDate = false
    @State private var accountDateSaveFailed = false

    private var style: CardVisualTheme.CardStyle {
        CardVisualTheme.style(for: card.cardId)
    }

    private var annualFeeText: String {
        let fee = card.fee.annual?.amount ?? 0
        if fee == 0 {
            return "No Annual Fee"
        } else {
            return String(format: "$%.0f / year", fee)
        }
    }

    private var verifiedBenefitCount: Int {
        guard let graph = environment.graph else { return 0 }
        return graph.benefits.cards.first(where: { $0.cardId == card.cardId })?.benefits.count ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // 1. Hero Card Presentation
                    heroCardSection

                    // 2. Default Card Quick Switcher Card
                    defaultCardToggle

                    // 3. Earning Multipliers & Category Rates
                    earnMultipliersSection

                    // 4. Annual Statement Credits & Perks
                    if let credits = card.credits, !credits.isEmpty {
                        creditsSection(credits)
                    }

                    // 5. Card Metadata & Verification
                    metadataSection

                    // 6. Danger Zone / Remove Card
                    removeCardButton
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(card.officialName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear {
                isDefaultLocal = isDefault
                if let openedAt = environment.graph?.ownerState.cardStates[card.cardId]?.accountOpenedAt,
                   let date = parseISODate(openedAt) {
                    accountOpenedDate = date
                    hasAccountOpenedDate = true
                }
            }
            .alert("Remove Card?", isPresented: $showingRemoveAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    onRemoveCard()
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to remove \(card.officialName) from your active wallet?")
            }
        }
        .presentationDetents([.fraction(0.92), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    // MARK: - 1. Hero Card Presentation
    private var heroCardSection: some View {
        VStack(spacing: 12) {
            ZStack {
                // Ambient colorful floor glow
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(style.gradientColors.first?.opacity(0.35) ?? Color.blue.opacity(0.2))
                    .frame(width: 260, height: 160)
                    .blur(radius: 24)
                    .offset(y: 12)

                CardArtView(
                    cardId: card.cardId,
                    officialName: card.officialName,
                    isHero: true,
                    cleanArtwork: true
                )
                .frame(maxWidth: 320)
                .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 10)
            }
            .padding(.top, 6)

            // Card quick subtitle
            HStack(spacing: 8) {
                Text(card.issuer)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("•")
                    .foregroundStyle(.tertiary)

                Text(style.network.rawValue)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text("•")
                    .foregroundStyle(.tertiary)

                Text(annualFeeText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 2. Default Card Toggle
    private var defaultCardToggle: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isDefaultLocal ? Color.green.opacity(0.16) : Color(.tertiarySystemFill))
                    .frame(width: 38, height: 38)
                Image(systemName: isDefaultLocal ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isDefaultLocal ? Color.green : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Default Payment Card")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(isDefaultLocal
                     ? "Selected by default when cards earn equally"
                     : "Tap to set as your primary card")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isDefaultLocal },
                set: { newValue in
                    if newValue {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        isDefaultLocal = true
                        onSetDefault()
                    }
                }
            ))
            .labelsHidden()
            .tint(Color.green)
            .disabled(isDefaultLocal)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 1)
        )
    }

    // MARK: - 3. Earn Multipliers Section
    private var earnMultipliersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Earn Multipliers")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(card.earnRules.count) categories")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill), in: Capsule())
            }

            VStack(spacing: 0) {
                let sortedRules = card.earnRules.sorted { rule1, rule2 in
                    earnRateValue(rule1.earn) > earnRateValue(rule2.earn)
                }

                ForEach(Array(sortedRules.enumerated()), id: \.element.ruleId) { index, rule in
                    earnRuleRow(rule: rule)

                    if index < sortedRules.count - 1 {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 1)
            )
        }
    }

    private func earnRuleRow(rule: EarnRule) -> some View {
        let categoryName = rule.predicate.categories?.first ?? "General / All Purchases"
        let meta = CategoryVisuals.meta(for: categoryName)
        let rateFormatted = formatEarnRate(rule.earn)

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(meta.color.opacity(0.14))
                    .frame(width: 34, height: 34)

                Image(systemName: meta.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(meta.color)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.predicate.categories?.first.map { CategoryVisuals.meta(for: $0).displayName } ?? "All other spending")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                if let cap = card.caps.first(where: { rule.effectiveCapIds.contains($0.capId) }) {
                    Text("Cap: $\(Int(cap.limit))/\(cap.period.rawValue.replacingOccurrences(of: "calendar", with: "").lowercased())")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Unlimited earn")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(rateFormatted)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(meta.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(meta.color.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func earnRateValue(_ earn: Earn) -> Double {
        switch earn {
        case .points(let pts): return pts
        case .cashback(let rate, _): return rate * 100.0
        case .centsPerLitre: return 0.5
        }
    }

    private func formatEarnRate(_ earn: Earn) -> String {
        switch earn {
        case .points(let pts):
            let formatted = pts.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0fx", pts) : String(format: "%.1fx", pts)
            return "\(formatted) pts"
        case .cashback(let rate, _):
            let percent = rate * 100.0
            let formatted = percent.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f%%", percent) : String(format: "%.1f%%", percent)
            return formatted
        case .centsPerLitre:
            return "¢/L rebate"
        }
    }

    // MARK: - 4. Statement Credits & Perks Section
    private func creditsSection(_ credits: [CardCredit]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Included Statement Credits")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            if credits.contains(where: { $0.effectiveSchedule?.basis == .accountAnniversary }) {
                VStack(alignment: .leading, spacing: 8) {
                    DatePicker("Account opened",
                               selection: $accountOpenedDate,
                               in: ...Date(), displayedComponents: .date)
                        .font(.subheadline.weight(.medium))
                    HStack {
                        Text(hasAccountOpenedDate
                             ? "Used to calculate anniversary-year credit windows."
                             : "Required for anniversary-year expiry dates.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(hasAccountOpenedDate ? "Update" : "Save") {
                            accountDateSaveFailed = !environment.setAccountOpenedAt(
                                isoDate(accountOpenedDate), cardId: card.cardId
                            )
                            if !accountDateSaveFailed { hasAccountOpenedDate = true }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    if accountDateSaveFailed {
                        Text("Couldn’t save the date. Your wallet was not changed.")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
            }

            VStack(spacing: 8) {
                ForEach(credits) { credit in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.orange.opacity(0.14))
                                .frame(width: 36, height: 36)
                            Image(systemName: "gift.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.orange)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(credit.label)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)

                            Text(creditCadenceLabel(credit) + " credit")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(String(format: "$%.0f", credit.value.amount))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                }
            }
        }
    }

    private func creditCadenceLabel(_ credit: CardCredit) -> String {
        guard let schedule = credit.effectiveSchedule else { return "Recurring" }
        switch (schedule.basis, schedule.unit, schedule.intervalMonths) {
        case (.calendar, .month, _): return "Monthly"
        case (.calendar, .quarter, _): return "Quarterly"
        case (.calendar, .halfYear, _): return "Semi-annual"
        case (.calendar, .year, _): return "Annual"
        case (.accountAnniversary, _, let months?):
            return months == 12 ? "Anniversary-year" : "Every \(months) months"
        case (.rolling, _, let months?): return "Every \(months) months"
        default: return "Recurring"
        }
    }

    private func parseISODate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func isoDate(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }

    // MARK: - 5. Metadata & Settings Shortcuts
    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Configuration & Rules")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                Button {
                    dismiss()
                    onOpenConditions()
                } label: {
                    HStack {
                        Label("Spend Rules & Condition Triggers", systemImage: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)

                if verifiedBenefitCount > 0 {
                    Divider().padding(.leading, 14)

                    HStack {
                        Label("Certificate Protection Benefits", systemImage: "checkmark.shield.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(verifiedBenefitCount) verified")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.indigo)
                    }
                    .padding(14)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 1)
            )
        }
    }

    // MARK: - 6. Remove Card Button
    private var removeCardButton: some View {
        Button {
            showingRemoveAlert = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                Text("Remove from Wallet")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(Color.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.red.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}
