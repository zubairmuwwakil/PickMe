import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// The wallet editor. One screen for first run and edit — the three-page wizard is gone, because
/// paging exists to sequence questions and there are no longer questions to sequence: conditions
/// live on the card that raises them, and everything else has a working default.
///
/// Edits apply immediately (D6). There is no staged copy to discard, which is why "Done" is safe
/// here and was not before.
struct WalletEditorView: View {
    let catalogue: Catalogue
    let existing: OwnerState?
    let isFirstRun: Bool
    let onChange: (WalletSetup) -> Void
    let onCommitFirstRun: (WalletSetup) async -> Void
    let onRequestCard: (PendingCardRequest) async -> Bool
    let onDone: () -> Void

    @State private var setup: WalletSetup
    @State private var expandedCardId: String?
    @State private var showingAddSheet = false
    @State private var lastRemoved: (cardId: String, setup: WalletSetup)?

    init(catalogue: Catalogue, existing: OwnerState?, isFirstRun: Bool,
         onChange: @escaping (WalletSetup) -> Void,
         onCommitFirstRun: @escaping (WalletSetup) async -> Void,
         onRequestCard: @escaping (PendingCardRequest) async -> Bool,
         onDone: @escaping () -> Void) {
        self.catalogue = catalogue
        self.existing = existing
        self.isFirstRun = isFirstRun
        self.onChange = onChange
        self.onCommitFirstRun = onCommitFirstRun
        self.onRequestCard = onRequestCard
        self.onDone = onDone

        var initial = existing.map(OwnerStateBuilder.setup(from:))
            ?? WalletSetup(ownedCardIds: [], defaultCardId: "",
                           switchThreshold: OwnerStateBuilder.defaultSwitchThreshold,
                           valuationsCad: Valuations(programs: [:]))
        // Residency is inferred, then corrected in place (D1). A bundled seed is a developer
        // fallback, never a new customer's wallet.
        if initial.market == nil { initial.market = Self.inferredResidency() }
        _setup = State(initialValue: initial)
    }

    static func inferredResidency() -> Market {
        Locale.current.region?.identifier == "US" ? .us : .ca
    }

    private var ownedCards: [CardProduct] {
        setup.ownedCardIds.compactMap { id in catalogue.cards.first { $0.cardId == id } }
    }

    private var checklistItems: [WalletChecklistItem] {
        WalletChecklist.items(setup: setup, catalogue: catalogue)
    }

    var body: some View {
        List {
            if !checklistItems.isEmpty {
                Section {
                    WalletChecklistBanner(items: checklistItems, totalSteps: 3) { item in
                        if let cardId = item.cardId { expandedCardId = cardId }
                        else if item.kind == .addCards { showingAddSheet = true }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }

            Section {
                if ownedCards.isEmpty {
                    ContentUnavailableView(
                        "No cards yet", systemImage: "creditcard",
                        description: Text("PickMe only recommends cards you add here."))
                } else {
                    ForEach(ownedCards) { card in cardRow(card) }
                }
                Button { showingAddSheet = true } label: {
                    Label("Add a card", systemImage: "plus.circle.fill")
                }
            } header: {
                HStack {
                    Text("Your cards")
                    Spacer()
                    if !ownedCards.isEmpty { Text("\(ownedCards.count)") }
                }
            }

            preferencesSection
        }
        .navigationTitle(isFirstRun ? "Set up your wallet" : "Edit wallet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isFirstRun {
                ToolbarItem(placement: .topBarTrailing) { Button("Done", action: onDone) }
            }
        }
        .safeAreaInset(edge: .bottom) { firstRunCommitBar }
        .sheet(isPresented: $showingAddSheet) {
            AddCardSheet(catalogue: catalogue, ownedCardIds: setup.ownedCardIds,
                         residency: setup.market ?? .ca,
                         onAdd: add(_:), onRequestCard: onRequestCard,
                         onDismiss: { showingAddSheet = false })
        }
        .overlay(alignment: .bottom) { undoBar }
    }

    private func cardRow(_ card: CardProduct) -> some View {
        let conditionIds = WalletConditions.ids(for: card.cardId, catalogue: catalogue)
        let unanswered = conditionIds.filter {
            WalletConditions.condition($0)?.answerKind == .boolean
                && setup.conditionAnswers[card.cardId]?[$0] == nil
        }
        return DisclosureGroup(isExpanded: expansion(card.cardId)) {
            OwnerConditionEditor(
                cardId: card.cardId, conditionIds: conditionIds,
                answers: answersBinding(card.cardId),
                tangerineCategories: Binding(
                    get: { setup.tangerineSelectedCategories },
                    set: { setup.tangerineSelectedCategories = $0; commit() }))

            Toggle("Use by default", isOn: Binding(
                get: { setup.defaultCardId == card.cardId },
                set: { if $0 { setup.defaultCardId = card.cardId; commit() } }))

            Button("Remove from wallet", role: .destructive) { remove(card.cardId) }
        } label: {
            HStack(spacing: 12) {
                CardArtView(cardId: card.cardId, officialName: card.officialName, isHero: false)
                    .frame(width: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.officialName)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(card.issuer).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if setup.defaultCardId == card.cardId {
                    Text("DEFAULT").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                }
                if !unanswered.isEmpty {
                    Text("\(unanswered.count) ASK")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.orange)
                        .accessibilityLabel(Text("\(unanswered.count) unanswered question"))
                }
            }
        }
    }

    private var preferencesSection: some View {
        Section("Preferences") {
            Picker("Showing cards from", selection: Binding(
                get: { setup.market ?? .ca },
                set: { setup.market = $0; commit() })) {
                Text("Canada").tag(Market.ca)
                Text("United States").tag(Market.us)
            }
            DisclosureGroup("Advanced switch threshold") {
                Stepper("At least \(setup.switchThreshold.minAdvantagePercentagePoints, specifier: "%.1f") percentage points better",
                        value: Binding(get: { setup.switchThreshold.minAdvantagePercentagePoints },
                                       set: { setup.switchThreshold.minAdvantagePercentagePoints = $0; commit() }),
                        in: 0...10, step: 0.1)
                Stepper("At least $\(setup.switchThreshold.minAdvantageCad, specifier: "%.2f") more",
                        value: Binding(get: { setup.switchThreshold.minAdvantageCad },
                                       set: { setup.switchThreshold.minAdvantageCad = $0; commit() }),
                        in: 0...20, step: 0.05)
                Text("Both must be true before PickMe suggests switching cards.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var firstRunCommitBar: some View {
        if isFirstRun {
            Button("Start using PickMe") { Task { await onCommitFirstRun(setup) } }
                .buttonStyle(.borderedProminent)
                .disabled(setup.ownedCardIds.isEmpty)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.bar)
        }
    }

    @ViewBuilder
    private var undoBar: some View {
        if let removed = lastRemoved {
            let name = catalogue.cards.first { $0.cardId == removed.cardId }?.officialName ?? ""
            HStack {
                Text("Removed \(name)").font(.footnote).lineLimit(1)
                Spacer()
                Button("Undo") { setup = removed.setup; lastRemoved = nil; commit() }
                    .font(.footnote.weight(.semibold))
            }
            .padding(12)
            .background(.regularMaterial, in: Capsule())
            .padding(.horizontal)
            .padding(.bottom, isFirstRun ? 72 : 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: removed.cardId) {
                try? await Task.sleep(for: .seconds(6))
                withAnimation { lastRemoved = nil }
            }
        }
    }

    // MARK: - Mutations

    private func expansion(_ cardId: String) -> Binding<Bool> {
        Binding(get: { expandedCardId == cardId },
                set: { expandedCardId = $0 ? cardId : nil })
    }

    private func answersBinding(_ cardId: String) -> Binding<[String: Bool]> {
        Binding(get: { setup.conditionAnswers[cardId] ?? [:] },
                set: { setup.conditionAnswers[cardId] = $0.isEmpty ? nil : $0; commit() })
    }

    private func add(_ cardId: String) {
        guard !setup.ownedCardIds.contains(cardId) else { return }
        setup.ownedCardIds.append(cardId)
        normalizeDefault()
        commit()
    }

    private func remove(_ cardId: String) {
        let before = setup
        setup.ownedCardIds.removeAll { $0 == cardId }
        setup.conditionAnswers[cardId] = nil
        normalizeDefault()
        withAnimation { lastRemoved = (cardId: cardId, setup: before) }
        commit()
    }

    private func normalizeDefault() {
        if !setup.ownedCardIds.contains(setup.defaultCardId) {
            setup.defaultCardId = setup.ownedCardIds.first ?? ""
        }
    }

    /// Apply immediately. First run holds its changes until the explicit commit, because until
    /// then there is no wallet to update and `walletIsFirstRun` has not flipped.
    private func commit() {
        guard !isFirstRun else { return }
        onChange(setup)
    }
}
