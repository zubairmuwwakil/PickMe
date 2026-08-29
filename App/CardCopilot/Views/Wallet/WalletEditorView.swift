import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// The redesigned wallet editor matching the exact visual mockup photo.
///
/// Features:
/// - Studio lighting soft gradient background
/// - 3D radial spoke carousel where vertical portrait cards stand along a glowing circular ring arena
/// - Concentric glowing neon rings with central spotlight disc
/// - Front active card is centered flat facing forward with elevated scale
/// - Standalone "Set as Default Payment" toggle card with green iOS switch
/// - Grouped "Custom Conditions" card with chevron rows and centered red "Remove Card"
/// - Explanatory caption: "Removing this card will deactivate it for future transactions."
/// - Interactive condition customization sheets
struct WalletEditorView: View {
    let catalogue: Catalogue
    let existing: OwnerState?
    let isFirstRun: Bool
    let onChange: (WalletSetup) -> Void
    let onCommitFirstRun: (WalletSetup) async -> Void
    let onRequestCard: (PendingCardRequest) async -> Bool
    let onDone: () -> Void

    @State private var setup: WalletSetup
    @State private var selectedCardId: String = ""
    @State private var showingAddSheet = false
    @State private var showingSpendConditionSheet = false
    @State private var showingCategoryConditionSheet = false
    @State private var showingMerchantConditionSheet = false
    @State private var selectedConditionIdForEditing: String? = nil
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
        if initial.market == nil { initial.market = Self.inferredResidency() }
        _setup = State(initialValue: initial)
    }

    static func inferredResidency() -> Market {
        Locale.current.region?.identifier == "US" ? .us : .ca
    }

    private var currencySymbol: String {
        switch setup.market {
        case .us: return "$"
        case .ca: return "$"
        case .none: return "$"
        }
    }

    private var ownedCards: [CardProduct] {
        setup.ownedCardIds.compactMap { id in catalogue.cards.first { $0.cardId == id } }
    }

    private var activeCard: CardProduct? {
        ownedCards.first { $0.cardId == selectedCardId } ?? ownedCards.first
    }

    var body: some View {
        ZStack {
            // Studio gradient background (from photo)
            LinearGradient(
                colors: [
                    Color(red: 0.93, green: 0.94, blue: 0.97),
                    Color(red: 0.96, green: 0.97, blue: 0.99),
                    Color(red: 0.94, green: 0.95, blue: 0.98)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    // 3D Circular Orbit Spoke Carousel with glowing rings arena
                    Card3DCircleCarousel(
                        cards: ownedCards,
                        selectedCardId: $selectedCardId,
                        onAddCard: { showingAddSheet = true }
                    )
                    .padding(.top, 8)

                    // Active Card Management Controls (Exact Mockup Layout)
                    if let card = activeCard {
                        activeCardManagementSection(card)
                            .padding(.horizontal, 16)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }

                    // Optional Quick Add Button beneath configuration
                    Button {
                        showingAddSheet = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Add Another Card")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Color.blue)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.bottom, isFirstRun ? 100 : 40)
            }
        }
        .navigationTitle("Edit Wallet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    onDone()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 17))
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Done", action: onDone)
                    .font(.system(size: 17, weight: .bold))
            }
        }
        .safeAreaInset(edge: .bottom) { firstRunCommitBar }
        .fullScreenCover(isPresented: $showingAddSheet) {
            AddCardSheet(catalogue: catalogue, ownedCardIds: setup.ownedCardIds,
                         residency: setup.market ?? .ca,
                         onAdd: add(_:), onRequestCard: onRequestCard,
                         onDismiss: { showingAddSheet = false })
        }
        .sheet(isPresented: $showingSpendConditionSheet) {
            spendThresholdSheet
        }
        .sheet(isPresented: $showingCategoryConditionSheet) {
            categorySelectionSheet
        }
        .sheet(isPresented: $showingMerchantConditionSheet) {
            merchantConditionsSheet
        }
        .sheet(item: Binding(
            get: { selectedConditionIdForEditing.map { ConditionEditItem(id: $0) } },
            set: { selectedConditionIdForEditing = $0?.id }
        )) { item in
            conditionAnswerSheet(for: item.id)
        }
        .overlay(alignment: .bottom) { undoBar }
        .onAppear {
            if selectedCardId.isEmpty || !setup.ownedCardIds.contains(selectedCardId) {
                selectedCardId = setup.defaultCardId.isEmpty ? (setup.ownedCardIds.first ?? "") : setup.defaultCardId
            }
        }
    }

    private struct ConditionEditItem: Identifiable {
        let id: String
    }

    // MARK: - Active Card Management Controls (Exact Mockup Layout)
    private func activeCardManagementSection(_ card: CardProduct) -> some View {
        let conditionIds = WalletConditions.ids(for: card.cardId, catalogue: catalogue)

        return VStack(alignment: .leading, spacing: 14) {
            // Card 1: "Set as Default Payment" Standalone Toggle Card
            HStack {
                Text("Set as Default Payment")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                Toggle("", isOn: Binding(
                    get: { setup.defaultCardId == card.cardId },
                    set: { if $0 { setup.defaultCardId = card.cardId; commit() } }
                ))
                .labelsHidden()
                .tint(Color(red: 0.20, green: 0.82, blue: 0.38))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            )

            // Section Header: "Custom Conditions"
            Text("Custom Conditions")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
                .padding(.top, 6)

            // Card 2: Unified Grouped Conditions Card with Chevrons & Centered Red "Remove Card"
            VStack(spacing: 0) {
                // Row 1: Spend Condition ("When spending > £50" / "$50")
                Button {
                    showingSpendConditionSheet = true
                } label: {
                    conditionRow(title: "When spending > \(currencySymbol)50")
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 16)

                // Row 2: Category Condition ("For 'Travel' category")
                Button {
                    showingCategoryConditionSheet = true
                } label: {
                    conditionRow(title: "For 'Travel' category")
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 16)

                // Row 3: Merchant Condition ("For specific merchants")
                Button {
                    showingMerchantConditionSheet = true
                } label: {
                    conditionRow(title: "For specific merchants")
                }
                .buttonStyle(.plain)

                // Engine Owner Conditions (e.g. Prime, Rogers, Crypto.com)
                if !conditionIds.isEmpty {
                    ForEach(conditionIds, id: \.self) { id in
                        Divider()
                            .padding(.leading, 16)

                        Button {
                            selectedConditionIdForEditing = id
                        } label: {
                            conditionRow(title: WalletConditions.prompt(for: id))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                // Row 4: Centered Red "Remove Card" Button
                Button {
                    remove(card.cardId)
                } label: {
                    Text("Remove Card")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color(red: 0.94, green: 0.25, blue: 0.25))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            )

            // Explanatory Caption (from Mockup)
            Text("Removing this card will deactivate it for future transactions.")
                .font(.system(size: 12.5, weight: .regular))
                .foregroundStyle(Color(.secondaryLabel))
                .padding(.horizontal, 6)
        }
    }

    private func conditionRow(title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    // MARK: - Condition Detail Sheets

    private var spendThresholdSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Minimum Spend Advantage")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Choose when this card should be recommended over your default card based on transaction amount.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)

                VStack(spacing: 16) {
                    Stepper("Advantage: \(setup.switchThreshold.minAdvantagePercentagePoints, specifier: "%.1f") % pts",
                            value: Binding(get: { setup.switchThreshold.minAdvantagePercentagePoints },
                                           set: { setup.switchThreshold.minAdvantagePercentagePoints = $0; commit() }),
                            in: 0...10, step: 0.1)

                    Stepper("Threshold: \(currencySymbol)\(setup.switchThreshold.minAdvantageCad, specifier: "%.2f")",
                            value: Binding(get: { setup.switchThreshold.minAdvantageCad },
                                           set: { setup.switchThreshold.minAdvantageCad = $0; commit() }),
                            in: 0...20, step: 0.05)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )

                Spacer()
            }
            .padding(16)
            .navigationTitle("Spend Condition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingSpendConditionSheet = false }
                        .font(.system(size: 16, weight: .bold))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var categorySelectionSheet: some View {
        NavigationStack {
            List {
                Section("Category Condition") {
                    Text("This card will be prioritized for Travel and bonus reward categories.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let card = activeCard, card.cardId.contains("tangerine") {
                    Section("Tangerine 2% Categories (Pick up to 3)") {
                        ForEach(TangerineMoneyBackCategory.allCases, id: \.rawValue) { category in
                            Toggle(category.setupLabel, isOn: Binding(
                                get: { setup.tangerineSelectedCategories?.contains(category.rawValue) == true },
                                set: { selected in
                                    var categories = setup.tangerineSelectedCategories ?? []
                                    if selected, !categories.contains(category.rawValue), categories.count < 3 {
                                        categories.append(category.rawValue)
                                    } else {
                                        categories.removeAll { $0 == category.rawValue }
                                    }
                                    setup.tangerineSelectedCategories = categories.isEmpty ? nil : categories
                                    commit()
                                }
                            ))
                        }
                    }
                }
            }
            .navigationTitle("Category Condition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingCategoryConditionSheet = false }
                        .font(.system(size: 16, weight: .bold))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var merchantConditionsSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Specific Merchant Rules")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Configure specific stores and merchants where this card should always be used.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 16)

                Text("PickMe automatically learns your preferred card at merchants as you make purchases.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()
            }
            .padding(16)
            .navigationTitle("Merchant Conditions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingMerchantConditionSheet = false }
                        .font(.system(size: 16, weight: .bold))
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func conditionAnswerSheet(for conditionId: String) -> some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(WalletConditions.prompt(for: conditionId))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .padding(.top, 16)

                if let detail = WalletConditions.detail(for: conditionId) {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let card = activeCard {
                    Picker(WalletConditions.prompt(for: conditionId), selection: Binding(
                        get: { setup.conditionAnswers[card.cardId]?[conditionId].map { $0 ? "yes" : "no" } ?? "unknown" },
                        set: {
                            var answers = setup.conditionAnswers[card.cardId] ?? [:]
                            if $0 == "unknown" {
                                answers.removeValue(forKey: conditionId)
                            } else {
                                answers[conditionId] = ($0 == "yes")
                            }
                            setup.conditionAnswers[card.cardId] = answers.isEmpty ? nil : answers
                            commit()
                        }
                    )) {
                        Text("Yes").tag("yes")
                        Text("No").tag("no")
                        Text("I'm not sure").tag("unknown")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle("Card Condition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { selectedConditionIdForEditing = nil }
                        .font(.system(size: 16, weight: .bold))
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - First Run & Undo Bar

    @ViewBuilder
    private var firstRunCommitBar: some View {
        if isFirstRun {
            Button("Start using PickMe") { Task { await onCommitFirstRun(setup) } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
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
                Button("Undo") {
                    setup = removed.setup
                    selectedCardId = removed.cardId
                    lastRemoved = nil
                    commit()
                }
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

    private func add(_ cardId: String) {
        guard !setup.ownedCardIds.contains(cardId) else { return }
        setup.ownedCardIds.append(cardId)
        selectedCardId = cardId
        normalizeDefault()
        commit()
    }

    private func remove(_ cardId: String) {
        let before = setup
        setup.ownedCardIds.removeAll { $0 == cardId }
        setup.conditionAnswers[cardId] = nil
        normalizeDefault()
        if let next = setup.ownedCardIds.first {
            selectedCardId = next
        }
        withAnimation { lastRemoved = (cardId: cardId, setup: before) }
        commit()
    }

    private func normalizeDefault() {
        if !setup.ownedCardIds.contains(setup.defaultCardId) {
            setup.defaultCardId = setup.ownedCardIds.first ?? ""
        }
    }

    private func commit() {
        guard !isFirstRun else { return }
        onChange(setup)
    }
}
