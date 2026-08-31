import SwiftUI
import CardCopilotEngine
import CardCopilotStore

private let physicalCardAspectRatio: CGFloat = 85.60 / 53.98

/// An Apple-grade, production-quality Add Card sheet featuring:
/// - Native Large-Title Navigation shell with integrated `.searchable`
/// - Multi-dimensional category/goal capsule filters (Dining, Groceries, Travel, No Fee, FX)
/// - Bank selector dropdown menu
/// - Grid ⊞ vs. List ☰ layout toggle
/// - Pristine, physical card rendering without intrusive text overlays or dark boxes
/// - Tap-to-inspect Apple Pay-style Card Quick Look detail sheet
/// - One-tap rapid adding with spring animations and haptic feedback
/// - Streamlined auto-filling Missing Card Request flow
struct AddCardSheet: View {
    let catalogue: Catalogue
    let ownedCardIds: [String]
    let residency: Market
    let onAdd: (String) -> Void
    let onRequestCard: (PendingCardRequest) async -> Bool
    let onDismiss: () -> Void

    @AppStorage("ca.pickme.wallet.market-scope") private var storedScope: String = ""
    @AppStorage("ca.pickme.wallet.add-card-view-mode") private var isGridView: Bool = true

    @State private var searchText = ""
    @State private var selectedCategoryFilter: String = "All"
    @State private var selectedBankFilter: String = "All"
    @State private var quickLookCard: CardProduct? = nil

    // Request missing card state
    @State private var showingRequestSheet = false
    @State private var issuer = ""
    @State private var cardName = ""
    @State private var requestMessage: String?
    @State private var isSubmittingRequest = false
    @State private var newlyAddedCardIds: Set<String> = []

    private var scope: MarketScope {
        MarketScope(rawValue: storedScope) ?? .default(for: residency)
    }

    // MARK: - Category Filter Definitions
    private struct CategoryPill: Identifiable {
        let id: String
        let title: String
        let icon: String
    }

    private let categoryPills: [CategoryPill] = [
        CategoryPill(id: "All", title: "All", icon: "square.grid.2x2.fill"),
        CategoryPill(id: "Dining", title: "Dining (5x)", icon: "fork.knife"),
        CategoryPill(id: "Groceries", title: "Groceries (4-5%)", icon: "cart.fill"),
        CategoryPill(id: "Travel", title: "Travel", icon: "airplane"),
        CategoryPill(id: "No Fee", title: "No Fee", icon: "tag.fill"),
        CategoryPill(id: "Cashback", title: "Cashback", icon: "dollarsign.circle.fill"),
        CategoryPill(id: "No FX", title: "0% FX", icon: "globe")
    ]

    private let bankOptions: [String] = [
        "All", "Amex", "Scotiabank", "RBC", "TD", "BMO", "CIBC", "Tangerine",
        "MBNA", "Rogers", "Desjardins", "National Bank", "PC Financial", "Triangle",
        "Wealthsimple", "Neo", "Capital One", "Chase", "Citi", "Bank of America",
        "Discover", "Wells Fargo", "Barclays", "U.S. Bank", "Apple", "Bilt"
    ]

    // MARK: - Filtered Cards
    private var filteredCards: [CardProduct] {
        let selectable = WalletCardCatalogue.selectable(catalogue.cards, scope: scope)
        let searchFiltered = WalletCardCatalogue.filter(selectable, matching: searchText)

        // Filter by Bank
        let bankFiltered: [CardProduct]
        if selectedBankFilter == "All" {
            bankFiltered = searchFiltered
        } else {
            bankFiltered = searchFiltered.filter { WalletCardCatalogue.matchesBankFilter($0, bankFilter: selectedBankFilter) }
        }

        // Filter by Category
        guard selectedCategoryFilter != "All" else { return bankFiltered }

        return bankFiltered.filter { card in
            switch selectedCategoryFilter {
            case "Dining":
                return matchesCategory(card, categoryKeywords: ["dining", "restaurant", "food"])
                    || card.cardId.contains("cobalt")
                    || card.cardId.contains("gold")
                    || card.cardId.contains("simplii-cash-back")
            case "Groceries":
                return matchesCategory(card, categoryKeywords: ["grocer", "supermarket"])
                    || card.cardId.contains("momentum")
                    || card.cardId.contains("simplycash")
                    || card.cardId.contains("cobalt")
            case "Travel":
                return matchesCategory(card, categoryKeywords: ["travel", "flight", "airline", "hotel"])
                    || card.cardId.contains("aeroplan")
                    || card.cardId.contains("avion")
                    || card.cardId.contains("passport")
                    || card.cardId.contains("sapphire")
                    || card.cardId.contains("bonvoy")
            case "No Fee":
                return (card.fee.annual?.amount ?? 0) == 0
            case "Cashback":
                return card.earnRules.contains(where: {
                    if case .cashback = $0.earn { return true }
                    return false
                }) || card.cardId.contains("cash") || card.cardId.contains("money-back")
            case "No FX":
                return card.fxRules.contains(where: { $0.rate == 0 })
                    || card.cardId.contains("passport")
                    || card.cardId.contains("we-mastercard")
                    || card.cardId.contains("wealthsimple")
            default:
                return true
            }
        }
    }

    private func matchesCategory(_ card: CardProduct, categoryKeywords: [String]) -> Bool {
        for rule in card.earnRules {
            let categories = rule.predicate.categories ?? []
            for cat in categories {
                let lower = cat.lowercased()
                if categoryKeywords.contains(where: { lower.contains($0) }) {
                    return true
                }
            }
        }
        return false
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    // MARK: 1. Controls Bar (Market Scope & Bank Selector)
                    controlsBar
                        .padding(.horizontal, 16)
                        .padding(.top, 4)

                    // MARK: 2. Goal / Category Filter Pills
                    categoryFilterBar
                        .padding(.horizontal, 16)

                    // MARK: 3. Cards Content (Grid vs List)
                    if filteredCards.isEmpty {
                        emptyResultsAndRequestView
                            .padding(.horizontal, 16)
                            .padding(.top, 24)
                    } else {
                        if isGridView {
                            LazyVGrid(columns: gridColumns, spacing: 16) {
                                ForEach(filteredCards) { card in
                                    gridCardCell(card)
                                }
                            }
                            .padding(.horizontal, 16)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredCards) { card in
                                    listCardRow(card)
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        // Bottom missing card callout banner
                        missingCardBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Add Card")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search cards, issuers, or perks"
            )
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done", action: onDismiss)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                }
            }
            .sheet(item: $quickLookCard) { card in
                CardQuickLookSheet(
                    card: card,
                    isOwned: isCardOwned(card.cardId),
                    onAdd: {
                        addCardWithHaptics(card.cardId)
                    },
                    onDismiss: {
                        quickLookCard = nil
                    }
                )
            }
            .sheet(isPresented: $showingRequestSheet) {
                requestModalSheet
            }
        }
    }

    // MARK: - Controls Bar (Market & Bank Menu)
    private var controlsBar: some View {
        HStack(spacing: 10) {
            // Market Scope Picker (Canada / US / Both)
            Picker("Market", selection: Binding(
                get: { scope },
                set: { storedScope = $0.rawValue })) {
                ForEach(MarketScope.allCases, id: \.self) { scopeItem in
                    Text(scopeItem.title).tag(scopeItem)
                }
            }
            .pickerStyle(.segmented)

            // Bank Filter Menu Capsule
            Menu {
                ForEach(bankOptions, id: \.self) { bank in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedBankFilter = bank
                        }
                    } label: {
                        if selectedBankFilter == bank {
                            Label(bank, systemImage: "checkmark")
                        } else {
                            Text(bank)
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "building.columns.fill")
                        .font(.system(size: 12))
                    Text(selectedBankFilter == "All" ? "Bank" : selectedBankFilter)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(selectedBankFilter == "All" ? Color(.secondarySystemGroupedBackground) : Color.blue.opacity(0.15))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(selectedBankFilter == "All" ? Color(.separator).opacity(0.4) : Color.blue, lineWidth: 1)
                )
                .foregroundStyle(selectedBankFilter == "All" ? Color.primary : Color.blue)
            }
        }
    }

    // MARK: - Category Filter Bar (Capsule Pills)
    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categoryPills) { pill in
                    let isSelected = selectedCategoryFilter == pill.id

                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedCategoryFilter = pill.id
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: pill.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(pill.title)
                                .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? Color.blue : Color(.separator).opacity(0.3), lineWidth: isSelected ? 0 : 0.5)
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .shadow(color: isSelected ? Color.blue.opacity(0.25) : Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Grid Card Cell (Pristine Visual First)
    private func gridCardCell(_ card: CardProduct) -> some View {
        let isOwned = isCardOwned(card.cardId)
        let style = CardVisualTheme.style(for: card.cardId)
        let perk = extractTopPerk(for: card)
        let fee = formatFee(for: card)

        return VStack(alignment: .leading, spacing: 8) {
            // Pristine Card Art (Interactive Tap to inspect)
            Button {
                quickLookCard = card
            } label: {
                CardArtView(cardId: card.cardId, officialName: card.officialName, isHero: true, cleanArtwork: true)
                    .aspectRatio(physicalCardAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: style.gradientColors.first?.opacity(0.25) ?? Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
            }
            .buttonStyle(CardScaleButtonStyle())

            // Metadata Below Card
            VStack(alignment: .leading, spacing: 3) {
                Text(style.shortName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(style.issuer) · \(style.network.rawValue)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)

            // Micro-Badges Row (Perk & Fee)
            HStack(spacing: 6) {
                if let perk {
                    HStack(spacing: 3) {
                        Image(systemName: perk.icon)
                            .font(.system(size: 9, weight: .bold))
                        Text(perk.label)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .foregroundStyle(Color.blue)
                    .clipShape(Capsule())
                }

                Text(fee)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)

            // Action Button (+ Add to Wallet / ✓ In Wallet)
            Button {
                if !isOwned {
                    addCardWithHaptics(card.cardId)
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isOwned ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text(isOwned ? "In Wallet" : "Add")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(isOwned ? Color(.tertiarySystemFill) : Color.blue.opacity(0.12))
                .foregroundStyle(isOwned ? Color.secondary : Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isOwned)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - List Card Row (Dense Information First)
    private func listCardRow(_ card: CardProduct) -> some View {
        let isOwned = isCardOwned(card.cardId)
        let style = CardVisualTheme.style(for: card.cardId)
        let perk = extractTopPerk(for: card)
        let fee = formatFee(for: card)

        return Button {
            quickLookCard = card
        } label: {
            HStack(spacing: 14) {
                // Mini Card Graphic
                CardArtView(cardId: card.cardId, officialName: card.officialName, isHero: true, cleanArtwork: true)
                    .frame(width: 68, height: 43)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)

                // Info Center
                VStack(alignment: .leading, spacing: 3) {
                    Text(style.shortName)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("\(style.issuer) · \(style.network.rawValue)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let perk {
                            Text(perk.label)
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12))
                                .foregroundStyle(Color.blue)
                                .clipShape(Capsule())
                        }

                        Text(fee)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Action Pill
                Button {
                    if !isOwned {
                        addCardWithHaptics(card.cardId)
                    }
                } label: {
                    Text(isOwned ? "ADDED" : "+ ADD")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isOwned ? Color(.tertiarySystemFill) : Color.blue)
                        .foregroundStyle(isOwned ? Color.secondary : Color.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isOwned)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Missing Card Callout Banner
    private var missingCardBanner: some View {
        Button {
            prefillAndOpenRequest()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 36, height: 36)

                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.blue)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Can't find your card?")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Tell us and our research team will add it.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Zero Results State
    private var emptyResultsAndRequestView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .padding(.top, 12)

                Text(searchText.isEmpty ? "No cards found" : "No results for \"\(searchText)\"")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("We might not have catalogued this card yet.\nRequest it below and we'll source it.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            inlineRequestForm
        }
    }

    // MARK: - Inline & Modal Request Form
    private var inlineRequestForm: some View {
        VStack(spacing: 12) {
            TextField("Bank / Issuer (e.g. Scotiabank, Chase)", text: $issuer)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .font(.system(size: 14))

            TextField("Card Name (e.g. Passport Visa Infinite)", text: $cardName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .font(.system(size: 14))

            Button {
                submitCardRequest()
            } label: {
                if isSubmittingRequest {
                    ProgressView().tint(.white)
                } else {
                    Text("Submit Card Request")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isRequestDisabled ? Color.secondary.opacity(0.3) : Color.blue)
            )
            .foregroundStyle(.white)
            .disabled(isRequestDisabled || isSubmittingRequest)

            if let requestMessage {
                Text(requestMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var requestModalSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text("Request a Missing Card")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Enter the bank and card name. Our pipeline will research official issuer terms.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 16)

                inlineRequestForm

                Spacer()
            }
            .padding(20)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingRequestSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers
    private struct TopPerk {
        let label: String
        let icon: String
    }

    private func extractTopPerk(for card: CardProduct) -> TopPerk? {
        let name = card.officialName.lowercased()
        let cid = card.cardId.lowercased()

        if cid.contains("cobalt") {
            return TopPerk(label: "5x Dining", icon: "fork.knife")
        } else if cid.contains("gold-amex") || name.contains("gold") {
            return TopPerk(label: "4x Dining", icon: "fork.knife")
        } else if cid.contains("momentum") {
            return TopPerk(label: "4% Groceries", icon: "cart.fill")
        } else if cid.contains("simplycash-preferred") {
            return TopPerk(label: "4% Groceries & Gas", icon: "cart.fill")
        } else if cid.contains("simplycash") {
            return TopPerk(label: "2% Groceries & Gas", icon: "cart.fill")
        } else if cid.contains("aeroplan") {
            return TopPerk(label: "1.5x Travel", icon: "airplane")
        } else if cid.contains("avion") {
            return TopPerk(label: "1.25x Travel", icon: "airplane")
        } else if cid.contains("sapphire") {
            return TopPerk(label: "3x Dining", icon: "fork.knife")
        } else if cid.contains("tangerine") {
            return TopPerk(label: "2% Top Categories", icon: "star.fill")
        } else if cid.contains("wealthsimple") {
            return TopPerk(label: "1% Cash + 0% FX", icon: "globe")
        }

        // Dynamically inspect rules
        for rule in card.earnRules {
            let categories = rule.predicate.categories ?? []
            if !categories.isEmpty {
                let cat = categories[0].capitalized
                switch rule.earn {
                case .points(let pts):
                    let mult = pts == floor(pts) ? "\(Int(pts))x" : String(format: "%.1fx", pts)
                    return TopPerk(label: "\(mult) \(cat)", icon: "sparkles")
                case .cashback(let rate, _):
                    let pct = Int(rate * 100)
                    return TopPerk(label: "\(pct)% \(cat)", icon: "sparkles")
                case .centsPerLitre:
                    return TopPerk(label: "¢/L Gas", icon: "fuelpump.fill")
                }
            }
        }
        return nil
    }

    private func formatFee(for card: CardProduct) -> String {
        let amount = card.fee.annual?.amount ?? 0
        let currency = card.billingCurrency.rawValue
        return amount == 0 ? "No Annual Fee" : "\(currency) \(Int(amount))"
    }

    private func isCardOwned(_ cardId: String) -> Bool {
        ownedCardIds.contains(cardId) || newlyAddedCardIds.contains(cardId)
    }

    private func addCardWithHaptics(_ cardId: String) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            newlyAddedCardIds.insert(cardId)
            onAdd(cardId)
        }
    }

    private func prefillAndOpenRequest() {
        if !searchText.isEmpty {
            cardName = searchText
        }
        showingRequestSheet = true
    }

    private func submitCardRequest() {
        isSubmittingRequest = true
        Task {
            let sent = await onRequestCard(
                PendingCardRequest(issuer: issuer, cardName: cardName))
            requestMessage = sent
                ? String(localized: "Request submitted! We'll research and catalogue it.")
                : String(localized: "Saved locally on this device.")
            if sent {
                issuer = ""
                cardName = ""
            }
            isSubmittingRequest = false
        }
    }

    private var isRequestDisabled: Bool {
        issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || cardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Button Press Scaling
private struct CardScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
