import SwiftUI
import CardCopilotEngine

/// "Which card do I use for X?" — a category grid whose answer is amount bands, not a single
/// verdict, because the switch threshold and spend caps can change the winner as the amount
/// grows. Every pill and every band is derived from the loaded catalogue and owner state at
/// render time (see `CategoryPickerAdvisor`) — nothing here is a fixed list of categories or
/// cards.
struct CategoryPickerView: View {
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    private let distribution = SpendDistribution.placeholderCanadianHousehold
    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    private func categories(for graph: DependencyGraph) -> [String] {
        CategoryPickerAdvisor.derivedCategories(catalogue: graph.catalogue)
            .sorted { CategoryPickerAdvisor.label(for: $0, distribution: distribution)
                        < CategoryPickerAdvisor.label(for: $1, distribution: distribution) }
    }

    var body: some View {
        if let graph = environment.graph {
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("The answer can change with the amount — tap a category to see how.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(categories(for: graph), id: \.self) { category in
                        NavigationLink {
                            CategoryBandListView(category: category, deps: graph, distribution: distribution)
                        } label: {
                            pill(category)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Which Card?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                }
            }
        } else {
            EmptyView()
        }
    }

    private func pill(_ category: String) -> some View {
        let meta = CategoryVisuals.meta(for: category)
        let label = CategoryPickerAdvisor.label(for: category, distribution: distribution)
        return VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(meta.color.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: meta.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(meta.color)
            }
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(minHeight: 32)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

/// One category's amount-banded answer. A category with a single, amount-independent answer
/// shows one row with no band framing at all — the spec is explicit that band count is never
/// assumed, so this reads whatever `CategoryPickerAdvisor.bands` actually returns.
struct CategoryBandListView: View {
    let category: String
    let deps: DependencyGraph
    let distribution: SpendDistribution

    private var label: String {
        CategoryPickerAdvisor.label(for: category, distribution: distribution)
    }

    private var bands: [CategoryPickerAdvisor.AmountBand] {
        let asOf = Date().formatted(.iso8601.year().month().day())
        return CategoryPickerAdvisor.bands(for: category, catalogue: deps.catalogue,
                                           ownerState: deps.ownerState, distribution: distribution,
                                           asOf: asOf)
    }

    var body: some View {
        let resolvedBands = bands
        let showsRange = resolvedBands.count > 1

        List {
            Section {
                ForEach(Array(resolvedBands.enumerated()), id: \.offset) { _, band in
                    bandRow(band, showsRange: showsRange)
                }
            } footer: {
                if showsRange {
                    Text("The answer changes with the amount for this category — enter the exact figure at checkout for the precise cutoff.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(label)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func bandRow(_ band: CategoryPickerAdvisor.AmountBand, showsRange: Bool) -> some View {
        let cardName = deps.catalogue.cards.first { $0.cardId == band.cardId }?.officialName ?? band.cardId
        let lowerText = WalletHealthFormatting.cad(band.lowerBoundCad)

        VStack(alignment: .leading, spacing: 6) {
            if showsRange {
                rangeLabel(band, lowerText: lowerText)
            }
            HStack(spacing: 10) {
                CardMiniBadge(cardId: band.cardId, size: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cardName)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    detail(for: band)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.vertical, showsRange ? 6 : 3)
    }

    @ViewBuilder
    private func rangeLabel(_ band: CategoryPickerAdvisor.AmountBand, lowerText: String) -> some View {
        if let upperBoundCad = band.upperBoundCad {
            let upperText = WalletHealthFormatting.cad(upperBoundCad)
            if band.lowerBoundCad == 0 {
                Text("under \(upperText)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Text("\(lowerText) – \(upperText)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("over \(lowerText)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    /// Every fragment here is derived from the `Recommendation`/catalogue, never a card-specific
    /// hardcoded string: whether this band's card is the default (and whether something better
    /// was suppressed by the switch threshold), or — when it switched — the applied rule's own
    /// earn rate read straight from the catalogue.
    @ViewBuilder
    private func detail(for band: CategoryPickerAdvisor.AmountBand) -> some View {
        let rec = band.recommendation
        if band.cardId == deps.ownerState.defaultCardId, !rec.switchedFromDefault {
            if rec.suppressedBetterCard != nil {
                Text("your default — not worth switching")
            } else {
                Text("your default")
            }
        } else if let earn = appliedEarn(band) {
            earnDetail(earn)
        }
    }

    private func appliedEarn(_ band: CategoryPickerAdvisor.AmountBand) -> Earn? {
        guard let ruleId = band.recommendation.winner.appliedRuleId,
              let card = deps.catalogue.cards.first(where: { $0.cardId == band.cardId }) else { return nil }
        return card.earnRules.first(where: { $0.ruleId == ruleId })?.earn
    }

    @ViewBuilder
    private func earnDetail(_ earn: Earn) -> some View {
        switch earn {
        case .points(let perCad):
            Text("\(CategoryPickerFormatting.multiplier(perCad))x points")
        case .cashback(let rate, let currency):
            if let currency, currency != "CAD" {
                Text("\(CategoryPickerFormatting.percent(rate)) back in \(currency)")
            } else {
                Text("\(CategoryPickerFormatting.percent(rate)) cash back")
            }
        case .centsPerLitre:
            Text("fuel savings")
        }
    }
}

enum CategoryPickerFormatting {
    static func multiplier(_ perCad: Double) -> String {
        perCad.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", perCad)
            : String(format: "%.1f", perCad)
    }

    static func percent(_ rate: Double) -> String {
        let pct = rate * 100
        let number = pct.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", pct)
            : String(format: "%.1f", pct)
        return "\(number)%"
    }
}
