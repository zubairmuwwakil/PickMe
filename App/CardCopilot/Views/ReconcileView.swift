import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// What the owner recorded off a statement. A separate type so the view never touches the
/// store: corrections travel out as data and become an observation elsewhere.
struct ReconcileEntry {
    let cardUsed: String
    let observedCategory: String
    let observedRewardUnits: Double?
    let missClass: MissClass?
    let note: String?
}

/// The weekly ritual: every prediction still waiting on a statement.
struct ReconcileView: View {
    let queue: [StoredPrediction]
    let cards: [CardProduct]
    let categories: [String]
    let onConfirm: (StoredPrediction, ReconcileEntry) -> Void
    let onDone: () -> Void

    @State private var editing: StoredPrediction?

    var body: some View {
        Group {
            if queue.isEmpty {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                    }
                    Text("All Caught Up!")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Every recorded checkout prediction has been matched to a statement observation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
                List {
                    Section {
                        ForEach(queue) { prediction in
                            reconcileRow(prediction)
                        }
                    } header: {
                        Text(queue.count == 1 ? "1 prediction waiting" : "\(queue.count) predictions waiting")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    } footer: {
                        Text("Confirm predictions that matched your statement in one tap, or tap the row to record discrepancies.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Reconcile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
                    .font(.headline)
            }
        }
        .sheet(item: $editing) { prediction in
            NavigationStack {
                ReconcileEntryView(
                    prediction: prediction,
                    cards: cards,
                    categories: categories,
                    onConfirm: { entry in
                        onConfirm(prediction, entry)
                        editing = nil
                    },
                    onCancel: { editing = nil }
                )
            }
        }
    }

    private func reconcileRow(_ prediction: StoredPrediction) -> some View {
        let meta = CategoryVisuals.meta(for: prediction.predictedCategory)

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(meta.color.opacity(0.14))
                    .frame(width: 42, height: 42)
                Image(systemName: meta.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(meta.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(prediction.merchantName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("\(meta.displayName) · \(cardName(prediction.winnerCardId))")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("\(amountText(prediction)) · \(prediction.recordedAt.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Quick Confirm Button
            Button {
                quickConfirm(prediction)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text("Match")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)

            // Edit / Detail Button
            Button {
                editing = prediction
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .leading) {
            Button {
                quickConfirm(prediction)
            } label: {
                Label("Matched", systemImage: "checkmark.circle.fill")
            }
            .tint(.green)
        }
    }

    private func quickConfirm(_ prediction: StoredPrediction) {
        let entry = ReconcileEntry(
            cardUsed: prediction.winnerCardId,
            observedCategory: prediction.predictedCategory,
            observedRewardUnits: prediction.predictedRewardUnits,
            missClass: nil,
            note: nil
        )
        onConfirm(prediction, entry)
    }

    private func cardName(_ cardId: String) -> String {
        cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }

    private func amountText(_ prediction: StoredPrediction) -> String {
        prediction.amountCad.map { String(format: "$%.2f", $0) } ?? "amount not captured"
    }
}

/// One row of the ritual: review prediction and record statement observation.
struct ReconcileEntryView: View {
    let prediction: StoredPrediction
    let cards: [CardProduct]
    let categories: [String]
    let onConfirm: (ReconcileEntry) -> Void
    let onCancel: () -> Void

    enum ReviewMode: String, CaseIterable {
        case matched = "Matched Advice"
        case discrepancy = "Discrepancy / Miss"
    }

    @State private var mode: ReviewMode = .matched
    @State private var cardUsed: String
    @State private var observedCategory: String
    @State private var unitsText: String = ""
    @State private var missClass: MissClass?
    @State private var note: String = ""

    init(prediction: StoredPrediction, cards: [CardProduct], categories: [String],
         onConfirm: @escaping (ReconcileEntry) -> Void, onCancel: @escaping () -> Void) {
        self.prediction = prediction
        self.cards = cards
        self.categories = categories
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _cardUsed = State(initialValue: prediction.winnerCardId)
        _observedCategory = State(initialValue: prediction.predictedCategory)
    }

    var body: some View {
        Form {
            Section {
                Picker("Review Mode", selection: $mode) {
                    ForEach(ReviewMode.allCases, id: \.self) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("What the app recommended") {
                LabeledContent("Merchant", value: prediction.merchantName)
                LabeledContent("Predicted Category", value: CategoryVisuals.meta(for: prediction.predictedCategory).displayName)
                LabeledContent("Recommended Card", value: cardName(prediction.winnerCardId))
                LabeledContent("Purchase Amount", value: prediction.amountCad.map { String(format: "$%.2f", $0) } ?? "not captured")
            }

            if mode == .matched {
                Section("Statement observation") {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(unitsPlaceholder, text: $unitsText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 16))
                        Text("Optional: Enter points or cash back posted on your statement to verify arithmetic accuracy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section("What actually posted") {
                    Picker("Card Used", selection: $cardUsed) {
                        ForEach(cards) { card in
                            Text(card.officialName).tag(card.cardId)
                        }
                    }

                    Picker("Coded As", selection: $observedCategory) {
                        ForEach(categories, id: \.self) { category in
                            Text(CategoryVisuals.meta(for: category).displayName).tag(category)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        TextField(unitsPlaceholder, text: $unitsText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 16))
                        Text("Optional: Points or cash back posted on statement.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Miss Taxonomy") {
                    Picker("Classification", selection: $missClass) {
                        Text("None — Correct").tag(MissClass?.none)
                        ForEach(MissClass.allCases, id: \.self) { miss in
                            Text(missLabel(miss)).tag(MissClass?.some(miss))
                        }
                    }

                    TextField("Notes (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                }
            }

            Section {
                Button {
                    onConfirm(entry)
                } label: {
                    Text("Save Statement Observation")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.blue)
                }
                .disabled(!unitsAreValid)
            } footer: {
                Text("This permanently logs your statement observation and trains the local Merchant Truth Graph for next time.")
            }
        }
        .navigationTitle(prediction.merchantName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
        .onChange(of: observedCategory) { _, updated in
            if updated != prediction.predictedCategory {
                if missClass == nil { missClass = .wrongCategory }
            } else if missClass == .wrongCategory {
                missClass = nil
            }
        }
    }

    private var entry: ReconcileEntry {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .matched {
            return ReconcileEntry(
                cardUsed: prediction.winnerCardId,
                observedCategory: prediction.predictedCategory,
                observedRewardUnits: Double(unitsText.trimmingCharacters(in: .whitespaces)),
                missClass: nil,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )
        } else {
            return ReconcileEntry(
                cardUsed: cardUsed,
                observedCategory: observedCategory,
                observedRewardUnits: Double(unitsText.trimmingCharacters(in: .whitespaces)),
                missClass: missClass,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )
        }
    }

    private var unitsAreValid: Bool {
        let trimmed = unitsText.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || Double(trimmed) != nil
    }

    private var unitsPlaceholder: String {
        switch prediction.predictedRewardUnitKind {
        case "point": return "Points posted (e.g. 700)"
        case "cad": return "Cash back posted ($)"
        case "ctDollar": return "CT Money posted ($)"
        case "cro": return "CRO posted"
        default: return "Rewards posted"
        }
    }

    private func cardName(_ cardId: String) -> String {
        cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }

    private func missLabel(_ miss: MissClass) -> String {
        switch miss {
        case .wrongCategory: return "Wrong category"
        case .capExceeded: return "Cap exceeded"
        case .staleRule: return "Catalogue rule wrong or stale"
        case .processorWeirdness: return "Processor weirdness"
        case .networkNotAccepted: return "Network not accepted"
        }
    }
}
