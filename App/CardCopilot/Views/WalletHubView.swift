import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// The redesigned Apple-grade Wallet hub:
///
/// Features:
/// - Executive portfolio summary bar with active card counts & default status
/// - Tactile snapping hero card carousel with pristine physical artwork & glossy rims
/// - Active card context pill with top multiplier highlights and 1-tap inspect button
/// - Interactive Apple-style `WalletCardDetailSheet` inspection for any card
/// - Modern 2x2 Bento Grid for Decision Tools (Which Card? Quick Category Chips, Wallet Health, Valuations, Rules)
/// - Seamless "+ Add Card" flows and haptic feedback
struct WalletHubView: View {
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(CheckoutRouter.self) private var router
    @Environment(CopilotSession.self) private var session

    @State private var selectedCardId: String = ""
    @State private var inspectingCard: CardProduct? = nil
    @State private var showingAddCardSheet = false

    private var cards: [CardProduct] {
        environment.graph?.walletCards ?? []
    }

    private var defaultCardId: String {
        environment.graph?.ownerState.defaultCardId ?? ""
    }

    private var activeCard: CardProduct? {
        cards.first { $0.cardId == selectedCardId } ?? cards.first
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                // 1. Executive Portfolio Header & Add Action
                walletSummaryHeader

                // 2. Tactile Hero Card Carousel
                if !cards.isEmpty {
                    heroCardsCarouselSection
                } else {
                    emptyWalletHero
                }

                // 3. Apple Bento Grid Decision Tools
                decisionToolsBentoSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 96) // Safe inset for FloatingGlassNavBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            if selectedCardId.isEmpty || !cards.contains(where: { $0.cardId == selectedCardId }) {
                selectedCardId = defaultCardId.isEmpty ? (cards.first?.cardId ?? "") : defaultCardId
            }
        }
        .sheet(item: $inspectingCard) { card in
            WalletCardDetailSheet(
                card: card,
                isDefault: card.cardId == defaultCardId,
                onSetDefault: { setDefaultCard(card.cardId) },
                onOpenConditions: { router.push(.walletSetup) },
                onRemoveCard: { removeCard(card.cardId) }
            )
        }
        .fullScreenCover(isPresented: $showingAddCardSheet) {
            if let graph = environment.graph {
                AddCardSheet(
                    catalogue: graph.catalogue,
                    ownedCardIds: graph.ownerState.ownedCardIds,
                    residency: graph.ownerState.market.flatMap(Market.init(rawValue:)) ?? .ca,
                    onAdd: { cardId in
                        addCard(cardId)
                        showingAddCardSheet = false
                    },
                    onRequestCard: { request in
                        await environment.requestCard(request)
                    },
                    onDismiss: { showingAddCardSheet = false }
                )
            }
        }
    }

    // MARK: - 1. Executive Summary Header
    private var walletSummaryHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Your Cards")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    if !cards.isEmpty {
                        Text("\(cards.count) active")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }

                if let defaultCard = cards.first(where: { $0.cardId == defaultCardId }) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.green)
                        Text("Default: \(defaultCard.officialName)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Manage cards & optimize reward rules")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Header Action Buttons: Add Card & Edit
            HStack(spacing: 8) {
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    showingAddCardSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [Color.blue, Color(red: 0.1, green: 0.45, blue: 0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: Capsule()
                    )
                    .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)

                Button {
                    router.push(.walletSetup)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(8)
                        .background(Color(.secondarySystemGroupedBackground), in: Circle())
                        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - 2. Hero Cards Carousel Section
    private var heroCardsCarouselSection: some View {
        VStack(spacing: 14) {
            // Horizontal Snapping Cards Deck
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(cards) { card in
                        let isSelected = (card.cardId == (activeCard?.cardId ?? ""))

                        Button {
                            let generator = UISelectionFeedbackGenerator()
                            generator.selectionChanged()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                selectedCardId = card.cardId
                            }
                            inspectingCard = card
                        } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                CardArtView(
                                    cardId: card.cardId,
                                    officialName: card.officialName,
                                    isHero: true,
                                    cleanArtwork: true
                                )
                                .frame(width: 272)
                                .scaleEffect(isSelected ? 1.0 : 0.94)
                                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isSelected)
                            }
                        }
                        .buttonStyle(PlainCardButtonStyle())
                        .contextMenu {
                            Button {
                                inspectingCard = card
                            } label: {
                                Label("Card Details & Multipliers", systemImage: "info.circle")
                            }

                            if card.cardId != defaultCardId {
                                Button {
                                    setDefaultCard(card.cardId)
                                } label: {
                                    Label("Set as Default Payment", systemImage: "checkmark.circle")
                                }
                            }

                            Button {
                                router.push(.walletSetup)
                            } label: {
                                Label("Configure Conditions", systemImage: "slider.horizontal.3")
                            }

                            Divider()

                            Button(role: .destructive) {
                                removeCard(card.cardId)
                            } label: {
                                Label("Remove from Wallet", systemImage: "trash")
                            }
                        }
                    }

                    // End Card: Add Another Card Quick Tile
                    Button {
                        showingAddCardSheet = true
                    } label: {
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "plus")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(.blue)
                            }

                            Text("Add Card")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            Text("Browse Canadian & US cards")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)
                        }
                        .frame(width: 140, height: 172)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 6]))
                                .foregroundStyle(Color.secondary.opacity(0.35))
                                .background(Color(.secondarySystemGroupedBackground).opacity(0.7), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }

            // Pagination Dots Indicator
            if cards.count > 1 {
                HStack(spacing: 6) {
                    ForEach(Array(cards.enumerated()), id: \.element.cardId) { index, card in
                        let isSelected = card.cardId == (activeCard?.cardId ?? "")
                        Circle()
                            .fill(isSelected ? Color.blue : Color.secondary.opacity(0.25))
                            .frame(width: isSelected ? 6.5 : 4.5, height: isSelected ? 6.5 : 4.5)
                            .animation(.spring(response: 0.3), value: isSelected)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    selectedCardId = card.cardId
                                }
                            }
                    }
                }
                .padding(.top, -4)
            }

            // Active Card Quick Info Pill & Action Bar
            if let card = activeCard {
                activeCardSummaryPill(card)
            }
        }
    }

    private func activeCardSummaryPill(_ card: CardProduct) -> some View {
        let isDefault = card.cardId == defaultCardId
        let topRules = card.earnRules
            .sorted { earnRateValue($0.earn) > earnRateValue($1.earn) }
            .prefix(2)

        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(card.officialName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isDefault {
                        Text("Default")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green, in: Capsule())
                    }
                }

                HStack(spacing: 6) {
                    let fee = card.fee.annual?.amount ?? 0
                    Text(fee == 0 ? "No Fee" : String(format: "$%.0f/yr", fee))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .foregroundStyle(.tertiary)

                    // Top earn categories preview
                    if !topRules.isEmpty {
                        let categoriesText = topRules.compactMap { rule -> String? in
                            guard let cat = rule.predicate.categories?.first else { return nil }
                            let name = CategoryVisuals.meta(for: cat).displayName
                            let rate = formatEarnRateShort(rule.earn)
                            return "\(rate) \(name)"
                        }.joined(separator: ", ")

                        Text(categoriesText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Button {
                inspectingCard = card
            } label: {
                HStack(spacing: 4) {
                    Text("Inspect")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 1)
        )
    }

    // MARK: - Empty Wallet State
    private var emptyWalletHero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 4) {
                Text("No Cards in Wallet")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Add your credit and charge cards to unlock instant 1-tap checkout picks, margin audits, and custom point valuations.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 16)
            }

            Button {
                showingAddCardSheet = true
            } label: {
                Label("Add Your First Card", systemImage: "plus.circle.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.blue, in: Capsule())
                    .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - 3. Apple Bento Grid Decision Tools
    private var decisionToolsBentoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Decision Tools")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(spacing: 12) {
                // Bento 1: Hero Which Card? Quick Category Lookup
                whichCardHeroBento

                // Bento 2 & 3: 2-Column Grid (Wallet Health & Valuation Sandbox)
                HStack(spacing: 12) {
                    walletHealthBentoTile
                    valuationSandboxBentoTile
                }

                // Bento 4: Manage Cards & Rules Tile
                manageWalletBentoTile
            }
        }
    }

    // MARK: Bento 1: Which Card?
    private var whichCardHeroBento: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.teal.opacity(0.16))
                        .frame(width: 38, height: 38)
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.teal)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Which Card?")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Instant Matrix")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.teal, in: Capsule())
                    }

                    Text("Compare earn rates per category across your wallet")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    router.push(.categoryPicker(nil))
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }

            // Interactive Quick Category Chips
            HStack(spacing: 8) {
                quickCategoryChip(title: "Dining", category: "dining", icon: "fork.knife", color: .orange)
                quickCategoryChip(title: "Grocery", category: "grocery", icon: "cart.fill", color: .green)
                quickCategoryChip(title: "Gas", category: "gasStation", icon: "fuelpump.fill", color: .blue)
                quickCategoryChip(title: "Travel", category: "travel", icon: "airplane", color: .indigo)
                quickCategoryChip(title: "Transit", category: "transit", icon: "tram.fill", color: .teal)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 1)
        )
    }

    private func quickCategoryChip(title: String, category: String, icon: String, color: Color) -> some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            router.push(.categoryPicker(CategoryTaxonomy.canonicalID(category)))
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.14))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color)
                }

                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Color(.tertiarySystemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Bento 2: Wallet Health Audit Tile
    private var walletHealthBentoTile: some View {
        Button {
            router.push(.walletHealth)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.mint.opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.mint)
                    }

                    Spacer()

                    Text("Audit")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.mint, in: Capsule())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Wallet Health")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Keep, cancel, or optimize annual fee ROI")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Bento 3: Valuation Sandbox Tile
    private var valuationSandboxBentoTile: some View {
        Button {
            router.push(.valuationSandbox)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.purple.opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.purple)
                    }

                    Spacer()

                    Text("Live")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple, in: Capsule())
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Valuations")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("MR, Aeroplan, Scene+ & Avion redemption rates")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Bento 4: Manage Cards & Rules Tile
    private var manageWalletBentoTile: some View {
        Button {
            router.push(.walletSetup)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: "creditcard.and.123")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Manage Cards & Spend Rules")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Setup")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue, in: Capsule())
                    }

                    Text("Configure default checkout card, spend caps, and custom condition rules")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helper Methods & Mutations

    private func setDefaultCard(_ cardId: String) {
        guard let graph = environment.graph else { return }
        var setup = OwnerStateBuilder.setup(from: graph.ownerState)
        setup.defaultCardId = cardId
        environment.applyWalletEdit(setup, session: session, router: router)
    }

    private func addCard(_ cardId: String) {
        guard let graph = environment.graph else { return }
        var setup = OwnerStateBuilder.setup(from: graph.ownerState)
        guard !setup.ownedCardIds.contains(cardId) else { return }
        setup.ownedCardIds.append(cardId)
        if setup.defaultCardId.isEmpty {
            setup.defaultCardId = cardId
        }
        selectedCardId = cardId
        environment.applyWalletEdit(setup, session: session, router: router)
    }

    private func removeCard(_ cardId: String) {
        guard let graph = environment.graph else { return }
        var setup = OwnerStateBuilder.setup(from: graph.ownerState)
        setup.ownedCardIds.removeAll { $0 == cardId }
        setup.conditionAnswers[cardId] = nil
        if setup.defaultCardId == cardId {
            setup.defaultCardId = setup.ownedCardIds.first ?? ""
        }
        if let next = setup.ownedCardIds.first {
            selectedCardId = next
        }
        environment.applyWalletEdit(setup, session: session, router: router)
    }

    private func earnRateValue(_ earn: Earn) -> Double {
        switch earn {
        case .points(let pts): return pts
        case .cashback(let rate, _): return rate * 100.0
        case .centsPerLitre: return 0.5
        }
    }

    private func formatEarnRateShort(_ earn: Earn) -> String {
        switch earn {
        case .points(let pts):
            let formatted = pts.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0fx", pts) : String(format: "%.1fx", pts)
            return formatted
        case .cashback(let rate, _):
            let percent = rate * 100.0
            let formatted = percent.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f%%", percent) : String(format: "%.1f%%", percent)
            return formatted
        case .centsPerLitre:
            return "¢/L"
        }
    }
}

/// Tactile button style for card taps in carousel
private struct PlainCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
