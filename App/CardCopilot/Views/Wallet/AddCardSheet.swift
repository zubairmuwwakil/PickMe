import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// Catalogue browsing, deliberately separate from wallet editing. The catalogue's stated horizon
/// is thousands of cards; keeping it behind its own surface is what stops that growth from
/// becoming the wallet screen's problem.
struct AddCardSheet: View {
    let catalogue: Catalogue
    let ownedCardIds: [String]
    let residency: Market
    let onAdd: (String) -> Void
    let onRequestCard: (PendingCardRequest) async -> Bool
    let onDismiss: () -> Void

    @AppStorage("ca.pickme.wallet.market-scope") private var storedScope: String = ""
    @State private var searchText = ""
    @State private var issuer = ""
    @State private var cardName = ""
    @State private var requestMessage: String?

    private var scope: MarketScope {
        MarketScope(rawValue: storedScope) ?? .default(for: residency)
    }

    private var results: [(issuer: String, cards: [CardProduct])] {
        let selectable = WalletCardCatalogue.selectable(catalogue.cards, scope: scope)
        return WalletCardCatalogue.groupedByIssuer(
            WalletCardCatalogue.filter(selectable, matching: searchText))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Market", selection: Binding(
                        get: { scope },
                        set: { storedScope = $0.rawValue })) {
                        ForEach(MarketScope.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                if results.isEmpty {
                    requestSection
                } else {
                    ForEach(results, id: \.issuer) { group in
                        Section(group.issuer) {
                            ForEach(group.cards) { card in row(card) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $searchText, prompt: Text("Search cards"))
            .navigationTitle("Add a card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done", action: onDismiss) }
            }
        }
    }

    private func row(_ card: CardProduct) -> some View {
        let owned = ownedCardIds.contains(card.cardId)
        return Button { if !owned { onAdd(card.cardId) } } label: {
            HStack(spacing: 12) {
                CardArtView(cardId: card.cardId, officialName: card.officialName, isHero: false)
                    .frame(width: 52)
                VStack(alignment: .leading, spacing: 2) {
                    // Full name, wrapping. The identifying text is the one thing that must never
                    // be truncated — the old row cut off 4 of 8 visible card names.
                    Text(card.officialName)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(feeLabel(card))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: owned ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(owned ? Color.secondary : Color.accentColor)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(owned)
        .accessibilityLabel(Text(card.officialName))
        .accessibilityValue(Text(owned ? "Already in your wallet" : "Not added"))
        .accessibilityHint(owned ? Text("") : Text("Adds this card to your wallet"))
    }

    /// One card's own fee in its own billing currency — never converted, because this is not a
    /// cross-card sum (see ReportingCurrency.swift).
    private func feeLabel(_ card: CardProduct) -> String {
        let amount = card.fee.annual?.amount ?? 0
        let currency = card.billingCurrency.rawValue
        return amount == 0
            ? String(localized: "\(card.network.rawValue.capitalized) · No annual fee")
            : String(localized: "\(card.network.rawValue.capitalized) · \(currency) \(Int(amount))/yr")
    }

    private var requestSection: some View {
        Section("My card isn't listed") {
            if !searchText.isEmpty {
                Text("No cards found for \"\(searchText)\"")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            TextField("Issuer", text: $issuer).textInputAutocapitalization(.words)
            TextField("Card name", text: $cardName).textInputAutocapitalization(.words)
            Button("Request this card") {
                Task {
                    let sent = await onRequestCard(
                        PendingCardRequest(issuer: issuer, cardName: cardName))
                    requestMessage = sent
                        ? String(localized: "Request sent. Thank you.")
                        : String(localized: "Saved on this iPhone. Sign in from Settings to send it.")
                    if sent { issuer = ""; cardName = "" }
                }
            }
            .disabled(issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || cardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let requestMessage {
                Text(requestMessage).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
