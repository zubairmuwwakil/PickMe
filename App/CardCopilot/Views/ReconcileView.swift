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

/// The weekly ritual: every prediction still waiting on a statement, one tap each.
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
                ContentUnavailableView("All caught up", systemImage: "checkmark.circle",
                                       description: Text("Every prediction has been matched to a statement."))
            } else {
                List {
                    Section {
                        ForEach(queue) { prediction in
                            Button { editing = prediction } label: { row(prediction) }
                                .buttonStyle(.plain)
                        }
                    } header: {
                        Text(queue.count == 1 ? "1 prediction waiting"
                                              : "\(queue.count) predictions waiting")
                    } footer: {
                        Text("Open your statement, find each transaction, and record what actually posted. Corrections never rewrite what the app said — they sit beside it.")
                    }
                }
            }
        }
        .navigationTitle("Reconcile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
        }
        .sheet(item: $editing) { prediction in
            NavigationStack {
                ReconcileEntryView(prediction: prediction, cards: cards, categories: categories,
                                   onConfirm: { entry in
                                       onConfirm(prediction, entry)
                                       editing = nil
                                   },
                                   onCancel: { editing = nil })
            }
        }
    }

    private func row(_ prediction: StoredPrediction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(prediction.merchantName)
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text("\(categoryDisplayName(prediction.predictedCategory)) · \(cardName(prediction.winnerCardId))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("\(amountText(prediction)) · \(prediction.recordedAt, format: .dateTime.month().day())")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func cardName(_ cardId: String) -> String {
        cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }

    private func amountText(_ prediction: StoredPrediction) -> String {
        prediction.amountCad.map { String(format: "$%.2f", $0) } ?? "amount not captured"
    }
}

/// One row of the ritual: what the app said, then what the statement says.
struct ReconcileEntryView: View {
    let prediction: StoredPrediction
    let cards: [CardProduct]
    let categories: [String]
    let onConfirm: (ReconcileEntry) -> Void
    let onCancel: () -> Void

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
            Section("What the app said") {
                LabeledContent("Merchant", value: prediction.merchantName)
                LabeledContent("Category", value: categoryDisplayName(prediction.predictedCategory))
                LabeledContent("Card", value: cardName(prediction.winnerCardId))
                LabeledContent("Amount", value: prediction.amountCad.map { String(format: "$%.2f", $0) }
                                                 ?? "not captured")
            }

            Section("What the statement says") {
                Picker("Card used", selection: $cardUsed) {
                    ForEach(cards) { card in Text(card.officialName).tag(card.cardId) }
                }
                Picker("Coded as", selection: $observedCategory) {
                    ForEach(categories, id: \.self) { category in
                        Text(categoryDisplayName(category)).tag(category)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField(unitsPlaceholder, text: $unitsText)
                        .keyboardType(.decimalPad)
                    Text("Points/cash posted — from your statement. Leave blank if it doesn't show one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Classification") {
                Picker("What went wrong", selection: $missClass) {
                    Text("Nothing — it was right").tag(MissClass?.none)
                    ForEach(MissClass.allCases, id: \.self) { miss in
                        Text(missLabel(miss)).tag(MissClass?.some(miss))
                    }
                }
                TextField("Note (optional)", text: $note, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section {
                Button("Record it") { onConfirm(entry) }
                    .disabled(!unitsAreValid)
            } footer: {
                Text("This attaches an observation to the prediction. The prediction itself is never edited.")
            }
        }
        .navigationTitle(prediction.merchantName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel) }
        }
        .onChange(of: observedCategory) { _, updated in
            // A different category IS the wrong-category miss — preselect it, but leave the
            // owner free to say the real story was a stale rule or processor weirdness.
            if updated != prediction.predictedCategory {
                if missClass == nil { missClass = .wrongCategory }
            } else if missClass == .wrongCategory {
                missClass = nil
            }
        }
    }

    private var entry: ReconcileEntry {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReconcileEntry(cardUsed: cardUsed,
                              observedCategory: observedCategory,
                              observedRewardUnits: Double(unitsText.trimmingCharacters(in: .whitespaces)),
                              missClass: missClass,
                              note: trimmedNote.isEmpty ? nil : trimmedNote)
    }

    private var unitsAreValid: Bool {
        let trimmed = unitsText.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || Double(trimmed) != nil
    }

    /// The prompt names the unit but never the expected figure: showing "we predicted 500"
    /// beside the entry field would anchor the number being copied off the statement, and the
    /// arithmetic bar only means something while the two are arrived at independently.
    private var unitsPlaceholder: String {
        switch prediction.predictedRewardUnitKind {
        case "point": return "Points posted"
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
