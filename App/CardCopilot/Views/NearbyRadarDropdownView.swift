import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// An Apple-grade inline expandable dropdown and swipeable carousel for Radar Ready nearby merchants.
///
/// Instead of navigating away to a separate "Select your location" modal, this view expands inline
/// on the home screen to display the winning card recommendation immediately. If the user is at a
/// different nearby merchant in the area (e.g. plaza, mall, street corner), they can swipe or tap
/// across the ranked nearby locations in order of distance.
struct NearbyRadarDropdownView: View {
    let merchants: [NearbyMerchant]
    let deps: DependencyGraph
    let onViewAllNearby: () -> Void

    @Environment(CopilotSession.self) private var session
    @Environment(CheckoutRouter.self) private var router
    @Environment(\.openURL) private var openURL

    @State private var isExpanded: Bool = false
    @State private var selectedMerchantID: String?
    @State private var selectedAmount: Double = InstantRepeatAdvisor.comparisonAmountCad

    init(
        merchants: [NearbyMerchant],
        deps: DependencyGraph,
        onViewAllNearby: @escaping () -> Void
    ) {
        self.merchants = merchants
        self.deps = deps
        self.onViewAllNearby = onViewAllNearby
    }

    private var activeMerchant: NearbyMerchant? {
        if let selectedMerchantID,
           let match = merchants.first(where: { $0.id == selectedMerchantID }) {
            return match
        }
        return merchants.first
    }

    private var isConfident: Bool {
        guard let active = activeMerchant else { return false }
        return session.confidentPreparedMerchant?.id == active.id
    }

    var body: some View {
        if let current = activeMerchant {
            VStack(spacing: 0) {
                // 1. Collapsed / Expandable Header Bar
                headerBar(for: current)

                // 2. Expandable Tray: Nearby Locations Carousel & Card Recommendation
                if isExpanded {
                    expandedTray(active: current)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                        ))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(isExpanded ? 0.08 : 0.03), radius: isExpanded ? 12 : 6, x: 0, y: isExpanded ? 4 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        isExpanded ? Color.blue.opacity(0.18) : Color.blue.opacity(0.08),
                        lineWidth: 1.2
                    )
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isExpanded)
            .onAppear {
                if selectedMerchantID == nil {
                    selectedMerchantID = merchants.first?.id
                }
            }
            .onChange(of: merchants) { _, newMerchants in
                if let currentID = selectedMerchantID, !newMerchants.contains(where: { $0.id == currentID }) {
                    selectedMerchantID = newMerchants.first?.id
                } else if selectedMerchantID == nil {
                    selectedMerchantID = newMerchants.first?.id
                }
            }
        }
    }

    // MARK: - 1. Header Bar

    private func headerBar(for merchant: NearbyMerchant) -> some View {
        let prediction = CardCopilotStore.predict(poiCategoryRaw: merchant.poiCategoryRaw,
                                                  merchantName: merchant.name)
        let distanceText = merchant.distanceMeters.map { "\(Int($0.rounded())) m away" }

        return Button {
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                // Branded circular icon
                MerchantBrandIconView(
                    merchantName: merchant.name,
                    category: prediction.category,
                    size: 32
                )

                // Location Details
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(isConfident ? "Likely here" : "Closest nearby")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(isConfident ? Color.green : Color.blue)
                            .textCase(.uppercase)

                        if let distanceText {
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text(distanceText)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(merchant.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Trailing Action Pill / Expand Chevron
                HStack(spacing: 5) {
                    Text(isExpanded ? "Hide" : "Card Pick")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.blue)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.blue)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.10), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded
            ? "Collapse nearby card recommendations for \(merchant.name)"
            : "Expand nearby card recommendations, closest is \(merchant.name)")
    }

    // MARK: - 2. Expanded Tray

    private func expandedTray(active: NearbyMerchant) -> some View {
        VStack(spacing: 14) {
            Divider()
                .padding(.horizontal, 14)

            // Location Selector Pill Bar (When multiple nearby locations exist)
            if merchants.count > 1 {
                locationChipsBar(activeID: active.id)
            }

            // Swipeable Recommendation Cards Carousel
            if merchants.count == 1 {
                recommendationCardContent(for: merchants[0])
                    .padding(.horizontal, 14)
            } else {
                VStack(spacing: 10) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(merchants) { item in
                                recommendationCardContent(for: item)
                                    .containerRelativeFrame(.horizontal)
                                    .id(item.id)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .scrollPosition(id: $selectedMerchantID)
                    .contentMargins(.horizontal, 14, for: .scrollContent)

                    // Page Indicator Dots
                    HStack(spacing: 6) {
                        ForEach(merchants) { item in
                            Circle()
                                .fill(active.id == item.id ? Color.blue : Color(.tertiarySystemFill))
                                .frame(
                                    width: active.id == item.id ? 7 : 5,
                                    height: active.id == item.id ? 7 : 5
                                )
                                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: active.id)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }
            }

            // Fallback / View All Link
            HStack {
                Spacer()
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    onViewAllNearby()
                } label: {
                    HStack(spacing: 4) {
                        Text("Not here? Choose from all places")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.bottom, 10)
        }
    }

    // MARK: - Location Chips Bar

    private func locationChipsBar(activeID: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Nearby Places")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Text("Swipe cards or tap to switch")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(merchants) { merchant in
                            let isSelected = merchant.id == activeID
                            let prediction = CardCopilotStore.predict(
                                poiCategoryRaw: merchant.poiCategoryRaw,
                                merchantName: merchant.name
                            )
                            let distance = merchant.distanceMeters.map { "\(Int($0.rounded()))m" }

                            Button {
                                let selectionFeedback = UISelectionFeedbackGenerator()
                                selectionFeedback.selectionChanged()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    selectedMerchantID = merchant.id
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    MerchantBrandIconView(
                                        merchantName: merchant.name,
                                        category: prediction.category,
                                        size: 20
                                    )

                                    Text(merchant.name)
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .foregroundStyle(isSelected ? Color.blue : Color.primary)
                                        .lineLimit(1)

                                    if let distance {
                                        Text(distance)
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundStyle(isSelected ? Color.blue.opacity(0.8) : Color.secondary)
                                    }
                                }
                                .padding(.leading, 6)
                                .padding(.trailing, 9)
                                .padding(.vertical, 6)
                                .background(
                                    isSelected ? Color.blue.opacity(0.12) : Color(.tertiarySystemFill),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .id(merchant.id)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                }
                .contentMargins(.horizontal, 14, for: .scrollContent)
                .onChange(of: selectedMerchantID) { _, newID in
                    if let newID {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recommendation Card Content

    @ViewBuilder
    private func recommendationCardContent(for merchant: NearbyMerchant) -> some View {
        let eval = InstantRepeatAdvisor.evaluate(
            merchant: merchant,
            amountCad: selectedAmount,
            catalogue: deps.catalogue,
            ownerState: deps.ownerState,
            engine: deps.engine
        )

        VStack(alignment: .leading, spacing: 12) {
            if let eval {
                let cardDisplayName = CardVisualTheme.style(for: eval.winnerCardId).shortName.isEmpty
                    ? eval.winnerCardName
                    : CardVisualTheme.style(for: eval.winnerCardId).shortName

                HStack(alignment: .center, spacing: 14) {
                    // Physical Hero Card Art
                    CardArtView(
                        cardId: eval.winnerCardId,
                        officialName: eval.winnerCardName,
                        isHero: true,
                        cleanArtwork: true
                    )
                    .frame(width: 110)
                    .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)

                    // Recommendation Details
                    VStack(alignment: .leading, spacing: 3) {
                        Text("USE THIS CARD")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .tracking(0.5)

                        Text(cardDisplayName)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(eval.multiplierText)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.green)

                        if let adv = eval.advantageText, eval.switchedFromDefault {
                            Text(adv)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                        }

                        if let networkBadge = eval.networkBadge {
                            Label(networkBadge, systemImage: "creditcard.trianglebadge.exclamationmark")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundStyle(.orange)
                        }
                    }

                    Spacer(minLength: 0)
                }

                // Amount What-If Selector
                HStack(spacing: 6) {
                    Text("Spend:")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    ForEach([25.0, 50.0, 100.0, 250.0], id: \.self) { amt in
                        Button {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                selectedAmount = amt
                            }
                        } label: {
                            Text("$\(Int(amt))")
                                .font(.system(size: 11, weight: selectedAmount == amt ? .bold : .medium, design: .rounded))
                                .foregroundStyle(selectedAmount == amt ? Color.blue : Color.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    selectedAmount == amt ? Color.blue.opacity(0.12) : Color(.tertiarySystemFill),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Text(String(format: "$%.2f return", eval.returnCad))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.green)
                }
                .padding(.top, 2)

                // 1-Tap Action Buttons
                HStack(spacing: 10) {
                    // Apple Wallet Direct Action Button
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        if let walletURL = URL(string: "shoebox://") {
                            openURL(walletURL)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "wallet.pass.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Pay with Apple Wallet")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Color.blue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .shadow(color: Color.blue.opacity(0.25), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)

                    // Full Breakdown Action
                    Button {
                        let impact = UIImpactFeedbackGenerator(style: .light)
                        impact.impactOccurred()
                        _ = session.preparedOutcomeForTap()
                        router.step = session.recommend(merchant: merchant, amount: selectedAmount, using: deps)
                    } label: {
                        HStack(spacing: 3) {
                            Text("Breakdown")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Color.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            } else {
                HStack {
                    Label("Recommendation unavailable", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }
}
