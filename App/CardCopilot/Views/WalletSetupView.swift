import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// First-run wallet setup and the re-editable Settings version of the same flow. It collects
/// facts; it never fills an uncertain condition with a convenient answer.
struct WalletSetupView: View {
    let catalogue: Catalogue
    let seed: OwnerState
    let isFirstRun: Bool
    let onSave: (WalletSetup) async -> Void
    let onRequestCard: (PendingCardRequest) async -> Bool
    let onDone: () -> Void

    @State private var page = 0
    @State private var setup: WalletSetup
    @State private var issuer = ""
    @State private var cardName = ""
    @State private var requestMessage: String?

    init(catalogue: Catalogue, seed: OwnerState, existing: OwnerState?, isFirstRun: Bool,
         onSave: @escaping (WalletSetup) async -> Void,
         onRequestCard: @escaping (PendingCardRequest) async -> Bool, onDone: @escaping () -> Void) {
        self.catalogue = catalogue
        self.seed = seed
        self.isFirstRun = isFirstRun
        self.onSave = onSave
        self.onRequestCard = onRequestCard
        self.onDone = onDone
        var initial = existing.map(OwnerStateBuilder.setup(from:)) ?? WalletSetup(
            ownedCardIds: [], defaultCardId: "", switchThreshold: OwnerStateBuilder.defaultSwitchThreshold,
            valuationsCad: seed.valuationsCad)
        // A bundled seed is a developer fallback, never a new customer's wallet.
        if existing == nil { initial.ownedCardIds = []; initial.defaultCardId = "" }
        _setup = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isFirstRun { ProgressView(value: Double(page + 1), total: 3).padding(.horizontal) }
            TabView(selection: $page) {
                pickerPage.tag(0)
                conditionsPage.tag(1)
                preferencesPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack {
                if page > 0 { Button("Back") { page -= 1 } }
                Spacer()
                if page < 2 {
                    Button("Continue") { page += 1 }
                        .buttonStyle(.borderedProminent)
                        .disabled(page == 0 && setup.ownedCardIds.isEmpty)
                } else {
                    Button(isFirstRun ? "Save my wallet" : "Save changes") {
                        Task { await onSave(setup) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(setup.ownedCardIds.isEmpty)
                }
            }
            .padding()
        }
        .navigationTitle(isFirstRun ? "Set up your wallet" : "Edit wallet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isFirstRun { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDone) } }
        }
    }

    private var pickerPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Which cards do you own?").font(.title2.bold())
                Text("Choose every card in your wallet. PickMe only recommends cards you select.")
                    .foregroundStyle(.secondary)
                ForEach(catalogue.cards) { card in
                    Button { toggle(card.cardId) } label: {
                        HStack {
                            CardArtView(cardId: card.cardId, officialName: card.officialName, isHero: false)
                            Image(systemName: setup.ownedCardIds.contains(card.cardId) ? "checkmark.circle.fill" : "circle")
                                .font(.title2)
                                .foregroundStyle(setup.ownedCardIds.contains(card.cardId) ? Color.accentColor : Color.secondary)
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(card.officialName)
                }
                GroupBox("My card isn't listed") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Issuer", text: $issuer).textInputAutocapitalization(.words)
                        TextField("Card name", text: $cardName).textInputAutocapitalization(.words)
                        Button("Request this card") {
                            Task {
                                let sent = await onRequestCard(PendingCardRequest(issuer: issuer, cardName: cardName))
                                requestMessage = sent ? "Request sent. Thank you." : "Saved on this iPhone. Sign in from Settings to send it."
                                if sent { issuer = ""; cardName = "" }
                            }
                        }
                        .disabled(issuer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || cardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if let requestMessage { Text(requestMessage).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }
            .padding()
        }
    }

    private var conditionsPage: some View {
        Form {
            Section {
                Text("Only cards with a condition need an answer. Leave anything uncertain unresolved — we'll skip this card's bonus until you confirm.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if setup.ownedCardIds.contains("rogers-red-we") {
                Section("Rogers Red World Elite") {
                    Text("The higher 2% rate requires an eligible Rogers, Fido, Shaw, Comwave, or Sportsnet+ service linked to your account.")
                    triStatePicker("Is an eligible service linked?", value: binding(\.rogersEligibleServiceLinked))
                }
            }
            if setup.ownedCardIds.contains("cryptocom-royal-indigo") {
                Section("Crypto.com Royal Indigo") {
                    Text("The 3% CRO reward applies only while your Level Up Pro plan is active.")
                    triStatePicker("Is Level Up Pro active?", value: binding(\.cryptoLevelUpProActive))
                }
            }
            if setup.ownedCardIds.contains("tangerine-moneyback-world") {
                Section("Tangerine Money-Back") {
                    Text("Choose up to three categories currently selected on your Tangerine account. Leave all unselected if you are not sure.")
                    ForEach(TangerineMoneyBackCategory.allCases, id: \.rawValue) { category in
                        Toggle(category.setupLabel, isOn: categoryBinding(category))
                            .disabled(!isTangerineCategorySelected(category)
                                      && (setup.tangerineSelectedCategories?.count ?? 0) >= 3)
                    }
                }
            }
            if !hasConditionalCard { ContentUnavailableView("No card conditions", systemImage: "checkmark.circle", description: Text("None of your selected cards needs an account-specific reward answer.")) }
        }
    }

    private var preferencesPage: some View {
        Form {
            Section("Default card") {
                Picker("Use by default", selection: $setup.defaultCardId) {
                    ForEach(selectedCards) { Text($0.officialName).tag($0.cardId) }
                }
                .onAppear { normalizeDefault() }
            }
            Section("Switch recommendations") {
                DisclosureGroup("Advanced switch threshold") {
                    Stepper("At least \(setup.switchThreshold.minAdvantagePercentagePoints, specifier: "%.1f") percentage points better", value: $setup.switchThreshold.minAdvantagePercentagePoints, in: 0...10, step: 0.1)
                    Stepper("At least $\(setup.switchThreshold.minAdvantageCad, specifier: "%.2f") more", value: $setup.switchThreshold.minAdvantageCad, in: 0...20, step: 0.05)
                    Text("Both must be true before PickMe suggests switching cards.").font(.footnote).foregroundStyle(.secondary)
                }
                Text("Default: 0.5 percentage points and $0.25 more — both conditions must be met.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Point valuations") {
                if let amex = centsPerPointBinding("amexMembershipRewards") {
                    valuationRow("Amex Membership Rewards", value: amex)
                }
                if let bonvoy = centsPerPointBinding("marriottBonvoy") {
                    valuationRow("Marriott Bonvoy", value: bonvoy)
                }
                if let mbna = centsPerPointBinding("mbnaRewards") {
                    valuationRow("MBNA Rewards", value: mbna)
                }
                Text("These published benchmarks are starting points. PickMe assumes the cents-per-point values above; recommendations disclose when the answer flips.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var selectedCards: [CardProduct] { catalogue.cards.filter { setup.ownedCardIds.contains($0.cardId) } }
    private var hasConditionalCard: Bool { ["rogers-red-we", "cryptocom-royal-indigo", "tangerine-moneyback-world"].contains { setup.ownedCardIds.contains($0) } }

    private func toggle(_ cardId: String) {
        if let index = setup.ownedCardIds.firstIndex(of: cardId) { setup.ownedCardIds.remove(at: index) }
        else { setup.ownedCardIds.append(cardId) }
        normalizeDefault()
    }

    private func normalizeDefault() { if !setup.ownedCardIds.contains(setup.defaultCardId) { setup.defaultCardId = setup.ownedCardIds.first ?? "" } }

    private func binding(_ keyPath: WritableKeyPath<WalletSetup, Bool?>) -> Binding<String> {
        Binding(get: { setup[keyPath: keyPath].map { $0 ? "yes" : "no" } ?? "unknown" }, set: { setup[keyPath: keyPath] = $0 == "unknown" ? nil : $0 == "yes" })
    }

    private func triStatePicker(_ title: String, value: Binding<String>) -> some View {
        Picker(title, selection: value) { Text("I’m not sure").tag("unknown"); Text("Yes").tag("yes"); Text("No").tag("no") }
    }

    private func isTangerineCategorySelected(_ category: TangerineMoneyBackCategory) -> Bool {
        setup.tangerineSelectedCategories?.contains(category.rawValue) == true
    }

    private func categoryBinding(_ category: TangerineMoneyBackCategory) -> Binding<Bool> {
        Binding(get: { isTangerineCategorySelected(category) }, set: { selected in
            let id = category.rawValue
            var categories = setup.tangerineSelectedCategories ?? []
            if selected, !categories.contains(id), categories.count < 3 { categories.append(id) }
            else { categories.removeAll { $0 == id } }
            setup.tangerineSelectedCategories = categories.isEmpty ? nil : categories
        })
    }

    private func valuationRow(_ name: String, value: Binding<Double>) -> some View {
        Stepper("\(name): \(value.wrappedValue, specifier: "%.2f")¢ / point", value: value, in: 0...10, step: 0.05)
    }

    /// A stepper binding into one points program's cents-per-point, or nil when the wallet holds
    /// no points valuation for it. Nil hides the row rather than showing 0.00¢: an editor
    /// pre-filled with a value nobody declared is the same lie as scoring the card at $0.00.
    private func centsPerPointBinding(_ programId: String) -> Binding<Double>? {
        guard setup.valuationsCad[points: programId] != nil else { return nil }
        return Binding(
            get: { setup.valuationsCad[points: programId]?.centsPerPoint ?? 0 },
            set: { setup.valuationsCad[points: programId]?.centsPerPoint = $0 }
        )
    }
}

private extension TangerineMoneyBackCategory {
    var setupLabel: LocalizedStringKey {
        switch self {
        case .grocery: "Grocery"
        case .dining: "Restaurants"
        case .gasStation: "Gas"
        case .entertainment: "Entertainment"
        case .furniture: "Furniture"
        case .lodging: "Hotel-Motel"
        case .drugStore: "Drug Store"
        case .recurring: "Recurring Bill Payments"
        case .homeImprovement: "Home Improvement"
        case .transit: "Public Transportation and Parking"
        case .eGames: "E-Games"
        case .fitness: "Fitness and Sports Clubs"
        case .foreignCurrency: "Foreign Currency Spend"
        }
    }
}
