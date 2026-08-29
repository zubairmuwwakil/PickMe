import SwiftUI
import CardCopilotEngine
import CardCopilotStore

private let physicalCardAspectRatio: CGFloat = 85.60 / 53.98

/// The exact visual 2-column brand grid Add Card sheet matching the user mockup.
///
/// Features:
/// - Floating frosted glass header card containing "Add Card" and search bar
/// - Vertical icon-over-text square bank filter tiles (All, Amex, Scotiabank, RBC, TD, BMO, CIBC, Tangerine)
/// - 2-Column visual card grid with top-left fee tag, top-right perk multiplier badge, and frosted circular `+` button on card
/// - Bold title + subtitle beneath each card
/// - Live instant filtering and request drawer
struct AddCardSheet: View {
    let catalogue: Catalogue
    let ownedCardIds: [String]
    let residency: Market
    let onAdd: (String) -> Void
    let onRequestCard: (PendingCardRequest) async -> Bool
    let onDismiss: () -> Void

    @AppStorage("ca.pickme.wallet.market-scope") private var storedScope: String = ""
    @State private var searchText = ""
    @State private var selectedFilter: String = "All"
    @State private var issuer = ""
    @State private var cardName = ""
    @State private var requestMessage: String?
    @State private var isSubmittingRequest = false

    private var scope: MarketScope {
        MarketScope(rawValue: storedScope) ?? .default(for: residency)
    }

    // Bank Tile Model (Icon on top, Label on bottom)
    private struct BankTile: Identifiable {
        let id: String
        let title: String
        let icon: String
        let iconColor: Color
        let iconBgColor: Color
    }

    private let bankTiles: [BankTile] = [
        BankTile(id: "All", title: "All", icon: "square.grid.2x2", iconColor: .primary, iconBgColor: Color(.systemFill)),
        BankTile(id: "Amex", title: "Amex", icon: "creditcard.fill", iconColor: .white, iconBgColor: Color(red: 0.08, green: 0.42, blue: 0.76)),
        BankTile(id: "Scotiabank", title: "Scotiabank", icon: "flame.fill", iconColor: .white, iconBgColor: Color(red: 0.85, green: 0.12, blue: 0.12)),
        BankTile(id: "RBC", title: "RBC", icon: "shield.fill", iconColor: .white, iconBgColor: Color(red: 0.05, green: 0.28, blue: 0.68)),
        BankTile(id: "TD", title: "TD", icon: "square.fill", iconColor: .white, iconBgColor: Color(red: 0.08, green: 0.62, blue: 0.24)),
        BankTile(id: "BMO", title: "BMO", icon: "circle.fill", iconColor: .white, iconBgColor: Color(red: 0.0, green: 0.45, blue: 0.80)),
        BankTile(id: "CIBC", title: "CIBC", icon: "building.columns.fill", iconColor: .white, iconBgColor: Color(red: 0.70, green: 0.10, blue: 0.22)),
        BankTile(id: "Tangerine", title: "Tangerine", icon: "sun.max.fill", iconColor: .white, iconBgColor: Color(red: 0.95, green: 0.45, blue: 0.05)),
        BankTile(id: "No Fee", title: "No Fee", icon: "tag.fill", iconColor: .white, iconBgColor: .teal)
    ]

    private var filteredCards: [CardProduct] {
        let selectable = WalletCardCatalogue.selectable(catalogue.cards, scope: scope)
        let searchFiltered = WalletCardCatalogue.filter(selectable, matching: searchText)

        guard selectedFilter != "All" else { return searchFiltered }

        return searchFiltered.filter { card in
            switch selectedFilter {
            case "Amex":
                return card.issuer.localizedCaseInsensitiveContains("American Express") || card.network == .amex
            case "Scotiabank":
                return card.issuer.localizedCaseInsensitiveContains("Scotia")
            case "RBC":
                return card.issuer.localizedCaseInsensitiveContains("RBC") || card.issuer.localizedCaseInsensitiveContains("Royal Bank")
            case "TD":
                return card.issuer.localizedCaseInsensitiveContains("TD")
            case "BMO":
                return card.issuer.localizedCaseInsensitiveContains("BMO") || card.issuer.localizedCaseInsensitiveContains("Bank of Montreal")
            case "CIBC":
                return card.issuer.localizedCaseInsensitiveContains("CIBC")
            case "Tangerine":
                return card.issuer.localizedCaseInsensitiveContains("Tangerine")
            case "No Fee":
                return (card.fee.annual?.amount ?? 0) == 0
            default:
                return true
            }
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Floating White Header Card (Title + Done button + Search Bar)
                floatingHeaderCard
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Market Region Selector
                Picker("Market", selection: Binding(
                    get: { scope },
                    set: { storedScope = $0.rawValue })) {
                    ForEach(MarketScope.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                // Horizontal Bank Tiles Bar (Square icon-over-text)
                bankTilesBar
                    .padding(.horizontal, 16)

                // 2-Column Visual Card Grid
                if filteredCards.isEmpty {
                    emptyResultsAndRequestView
                        .padding(.horizontal, 16)
                } else {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(filteredCards) { card in
                            visualMockupCardCell(card)
                        }
                    }
                    .padding(.horizontal, 16)

                    // Request Card Drawer
                    missingCardFooter
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
            }
            .padding(.bottom, 36)
        }
        .background(
            LinearGradient(
                colors: [Color(.systemGroupedBackground), Color(.systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    // MARK: - Floating Header Card (from Mockup)
    private var floatingHeaderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text("Add Card")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Button("Done", action: onDismiss)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
            }

            // Integrated Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("Search cards or issuers", text: $searchText)
                    .font(.system(size: 14))
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 10, x: 0, y: 3)
        )
    }

    // MARK: - Bank Tiles Bar (Square icon-over-text from Mockup)
    private var bankTilesBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(bankTiles) { tile in
                    let isSelected = selectedFilter == tile.id

                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedFilter = tile.id
                        }
                    } label: {
                        VStack(spacing: 5) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(tile.iconBgColor)
                                    .frame(width: 24, height: 24)

                                Image(systemName: tile.icon)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(tile.iconColor)
                            }

                            Text(tile.title)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundStyle(isSelected ? Color.blue : Color.primary)
                                .lineLimit(1)
                        }
                        .frame(width: 60, height: 60)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? Color.blue.opacity(0.12) : Color(.secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(isSelected ? Color.blue : Color(.separator).opacity(0.3), lineWidth: isSelected ? 1.5 : 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Visual Card Grid Cell (Exact Mockup Match)
    private func visualMockupCardCell(_ card: CardProduct) -> some View {
        let isOwned = ownedCardIds.contains(card.cardId)
        let perk = perkBadge(for: card)
        let fee = feeBadge(for: card)
        let (primaryName, secondaryName) = splitCardName(card)

        return VStack(alignment: .leading, spacing: 6) {
            // Card Visual with Badges and Circular Floating `+` Button
            ZStack(alignment: .bottomTrailing) {
                // Card Graphic
                CardArtView(cardId: card.cardId, officialName: card.officialName, isHero: true)
                    .aspectRatio(physicalCardAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: Color.black.opacity(0.14), radius: 8, x: 0, y: 4)

                // Top Corner Badges
                VStack {
                    HStack(alignment: .top) {
                        // Top Left: Annual Fee Tag
                        Text(fee)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.black.opacity(0.55))
                            )
                            .padding(5)

                        Spacer()

                        // Top Right: Perk Badge
                        if let perk {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(perk.multiplier)
                                    .font(.system(size: 9, weight: .black, design: .rounded))
                                    .foregroundStyle(Color(red: 0.98, green: 0.90, blue: 0.55))
                                if let sub = perk.category {
                                    Text(sub)
                                        .font(.system(size: 7, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(Color.black.opacity(0.65))
                            )
                            .padding(5)
                        }
                    }
                    Spacer()
                }

                // Bottom Right: Circular Translucent `+` Button
                Button {
                    if !isOwned {
                        playAddHaptic()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            onAdd(card.cardId)
                        }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(isOwned ? Color.secondary.opacity(0.7) : Color.white.opacity(0.85))
                            .frame(width: 28, height: 28)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)

                        Image(systemName: isOwned ? "checkmark" : "plus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isOwned ? Color.white : Color.black)
                    }
                    .padding(6)
                }
                .buttonStyle(.plain)
                .disabled(isOwned)
            }

            // Text Beneath Card (Title + Subtitle from Mockup)
            VStack(alignment: .leading, spacing: 1) {
                Text(primaryName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(secondaryName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
    }

    private struct PerkInfo {
        let multiplier: String
        let category: String?
    }

    private func perkBadge(for card: CardProduct) -> PerkInfo? {
        let name = card.officialName.lowercased()
        if name.contains("cobalt") {
            return PerkInfo(multiplier: "5x", category: "Dining")
        } else if name.contains("gold") {
            return PerkInfo(multiplier: "4x", category: "Dining")
        } else if name.contains("momentum") {
            return PerkInfo(multiplier: "4%", category: "Groceries")
        } else if name.contains("aeroplan") {
            return PerkInfo(multiplier: "1.5x", category: "Travel")
        } else if name.contains("avion") {
            return PerkInfo(multiplier: "1.25", category: "pts/$")
        } else if name.contains("simplycash") {
            return PerkInfo(multiplier: "4%", category: "Groceries")
        } else if name.contains("sapphire") {
            return PerkInfo(multiplier: "2x", category: "Travel")
        } else if name.contains("custom cash") {
            return PerkInfo(multiplier: "5%", category: "Top Cat")
        }
        return nil
    }

    private func feeBadge(for card: CardProduct) -> String {
        let amount = card.fee.annual?.amount ?? 0
        let currency = card.billingCurrency.rawValue
        return amount == 0 ? "No Annual Fee" : "\(currency) \(Int(amount))"
    }

    private func splitCardName(_ card: CardProduct) -> (String, String) {
        let style = CardVisualTheme.style(for: card.cardId)
        return (style.shortName, "\(style.issuer) · \(style.network.rawValue)")
    }

    // MARK: - Missing Card & Empty Results
    private var emptyResultsAndRequestView: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
                Text(searchText.isEmpty ? "No cards found" : "No results for \"\(searchText)\"")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("Can't find your card? Request it below and we'll add it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            requestForm
        }
    }

    private var missingCardFooter: some View {
        VStack(alignment: .leading, spacing: 10) {
            DisclosureGroup {
                requestForm
                    .padding(.top, 8)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Can't find your card? Request it")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.blue)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
        )
    }

    private var requestForm: some View {
        VStack(spacing: 10) {
            TextField("Bank or Issuer (e.g. Scotiabank, Chase)", text: $issuer)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .font(.system(size: 13))

            TextField("Card Name (e.g. Passport Visa Infinite)", text: $cardName)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.words)
                .font(.system(size: 13))

            Button {
                isSubmittingRequest = true
                Task {
                    let sent = await onRequestCard(
                        PendingCardRequest(issuer: issuer, cardName: cardName))
                    requestMessage = sent
                        ? String(localized: "Request sent. Thank you!")
                        : String(localized: "Saved on this iPhone. Sign in from Settings to submit.")
                    if sent { issuer = ""; cardName = "" }
                    isSubmittingRequest = false
                }
            } label: {
                if isSubmittingRequest {
                    ProgressView().tint(.white)
                } else {
                    Text("Request this card")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isRequestDisabled ? Color.secondary.opacity(0.3) : Color.blue)
            )
            .foregroundStyle(.white)
            .disabled(isRequestDisabled || isSubmittingRequest)

            if let requestMessage {
                Text(requestMessage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var isRequestDisabled: Bool {
        issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || cardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func playAddHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
}
