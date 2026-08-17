import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// The till facts the owner is supplying. A plain value so the view never touches the store —
/// the same split `ReconcileEntry` uses.
struct FinishEntry {
    let cardUsedId: String?
    let actualAmountCad: Double?
}

/// The "finish these" queue (design §8).
///
/// Separate from Reconcile because the two rituals answer different questions from different
/// sources. Finishing needs nothing but memory — which card came out of the wallet, what the
/// receipt said — and can be done in the car park. Reconciling needs a statement that will not
/// exist for days. Collapsing them would gate the fast half behind the slow one.
struct FinishPurchaseView: View {
    let queue: [StoredPrediction]
    let cards: [CardProduct]
    let onFinish: (StoredPrediction, FinishEntry) -> Void
    let onDone: () -> Void

    @State private var editing: StoredPrediction?

    var body: some View {
        Group {
            if queue.isEmpty {
                emptyState
            } else {
                List {
                    Section {
                        ForEach(queue) { prediction in
                            row(prediction)
                        }
                    } header: {
                        Text(queue.count == 1 ? "1 purchase to finish" : "\(queue.count) purchases to finish")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    } footer: {
                        Text("A purchase needs the card you tapped and what it actually cost before it can be checked against your statement.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Finish")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone).font(.headline)
            }
        }
        .sheet(item: $editing) { prediction in
            NavigationStack {
                FinishEntryView(prediction: prediction,
                                cards: cards,
                                onFinish: { entry in
                                    onFinish(prediction, entry)
                                    editing = nil
                                },
                                onCancel: { editing = nil })
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color.blue.opacity(0.12)).frame(width: 80, height: 80)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)
            }
            Text("Nothing to Finish")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Every purchase has the card you used and what it cost.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func row(_ prediction: StoredPrediction) -> some View {
        let meta = CategoryVisuals.meta(for: prediction.predictedCategory)
        let missing = prediction.purchase?.missingFacts ?? []

        return Button {
            editing = prediction
        } label: {
            HStack(spacing: 12) {
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
                    Text(prediction.recordedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Naming what is outstanding, rather than a generic chevron. The whole promise of
                // this screen is that each row is one or two fields, and the row should say so.
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(Self.orderedMissing(missing), id: \.self) { fact in
                        Text(Self.label(for: fact))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Card before amount: the card is the fact the owner is most likely to forget, and putting
    /// it first matches the order the entry sheet asks for them.
    static func orderedMissing(_ missing: Set<MissingPurchaseFact>) -> [MissingPurchaseFact] {
        MissingPurchaseFact.allCases.filter { missing.contains($0) }
    }

    static func label(for fact: MissingPurchaseFact) -> String {
        switch fact {
        case .card: return "Needs card"
        case .amount: return "Needs amount"
        }
    }
}

/// One row's worth of filling in. Only the missing fields are shown — a screen that re-asks for
/// something already recorded invites the owner to overwrite a fresh till fact with a stale
/// recollection.
struct FinishEntryView: View {
    let prediction: StoredPrediction
    let cards: [CardProduct]
    let onFinish: (FinishEntry) -> Void
    let onCancel: () -> Void

    @State private var cardUsedId: String
    @State private var amountText: String

    private let missing: Set<MissingPurchaseFact>

    init(prediction: StoredPrediction, cards: [CardProduct],
         onFinish: @escaping (FinishEntry) -> Void, onCancel: @escaping () -> Void) {
        self.prediction = prediction
        self.cards = cards
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.missing = prediction.purchase?.missingFacts ?? []
        // Seeded with the recommended card as a starting position, not as an answer — the picker
        // still has to be looked at, and `onFinish` only sends the card when it was missing.
        _cardUsedId = State(initialValue: prediction.purchase?.cardUsedId ?? prediction.winnerCardId)
        _amountText = State(initialValue: prediction.purchase?.amountCad.map {
            String(format: "%.2f", $0)
        } ?? "")
    }

    var body: some View {
        Form {
            Section("Where") {
                LabeledContent("Merchant", value: prediction.merchantName)
                LabeledContent("When", value: prediction.recordedAt.formatted(date: .abbreviated,
                                                                              time: .shortened))
                LabeledContent("Recommended", value: cardName(prediction.winnerCardId))
            }

            if missing.contains(.card) {
                Section {
                    Picker("Card you used", selection: $cardUsedId) {
                        ForEach(cards) { card in
                            Text(card.officialName).tag(card.cardId)
                        }
                    }
                } header: {
                    Text("Which card did you tap?")
                } footer: {
                    Text("If you didn't use the recommended card, say so — the value-recovered figure only counts purchases where you actually took the advice.")
                        .font(.caption)
                }
            }

            if missing.contains(.amount) {
                Section {
                    HStack {
                        Text("$").foregroundStyle(.secondary)
                        TextField("Amount charged", text: $amountText)
                            .keyboardType(.decimalPad)
                    }
                } header: {
                    Text("What did it come to?")
                } footer: {
                    Text("The total on the receipt, not what you entered before paying.")
                        .font(.caption)
                }
            }

            Section {
                Button {
                    onFinish(entry)
                } label: {
                    Text("Save")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.blue)
                }
                .disabled(!isValid)
            } footer: {
                Text("Once both are recorded, this moves to Reconcile to be checked against your statement.")
            }
        }
        .navigationTitle("Finish Purchase")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }

    private var entry: FinishEntry {
        FinishEntry(cardUsedId: missing.contains(.card) ? cardUsedId : nil,
                    actualAmountCad: missing.contains(.amount) ? parsedAmount : nil)
    }

    /// Nil rather than zero when blank or unparseable. A zero would complete the purchase while
    /// contributing nothing to the scoreboard — worse than leaving it outstanding, because the
    /// row would silently leave this queue with the fact still unknown.
    private var parsedAmount: Double? {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard let value = Double(trimmed), value > 0 else { return nil }
        return value
    }

    /// The amount must be usable when it is the thing being asked for; otherwise Save would
    /// appear to work and change nothing.
    private var isValid: Bool {
        missing.contains(.amount) ? parsedAmount != nil : true
    }

    private func cardName(_ cardId: String) -> String {
        cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }
}
