import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// The till facts the owner is supplying. A plain value so the view never touches the store —
/// the same split `ReconcileEntry` uses.
struct FinishEntry {
    let cardUsedId: String?
    let actualAmountCad: Double?
    /// Per-fact provenance, decided by `CaptureProposal`: `.walletCapture` only when a proposed
    /// figure was saved exactly as offered. Nil when the fact was not supplied at all.
    let cardSource: CaptureSource?
    let amountSource: CaptureSource?
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
    /// What the Apple Wallet Shortcut already captured for these checkouts, keyed by prediction.
    /// Offers only — nothing here is recorded until the owner accepts it.
    let proposals: [UUID: CaptureProposal]
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
                        Text(proposals.isEmpty
                             ? "A purchase needs the card you tapped and what it actually cost before it can be checked against your statement."
                             : "Rows marked Captured were read from your Apple Wallet transaction. Check them and accept, or tap to change anything.")
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
                                proposal: proposals[prediction.id],
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
        let proposal = proposals[prediction.id]
        let settlesEverything = proposal.map { Self.settlesEverything($0, missing: missing) } ?? false

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
                    if let proposal {
                        Label(Self.capturedSummary(proposal), systemImage: "wallet.pass.fill")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12), in: Capsule())
                        if let cardId = proposal.cardUsedId {
                            Text(cards.first { $0.cardId == cardId }?.officialName ?? cardId)
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    // Only the facts the capture did not answer are still chores.
                    ForEach(Self.orderedMissing(missing.subtracting(Self.answered(by: proposal))),
                            id: \.self) { fact in
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
        // Accepting without opening the sheet is the whole point of capture, but only when the
        // capture actually settles the row — a swipe that half-finishes a purchase would leave
        // it in the queue looking untouched.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if settlesEverything, let proposal {
                Button {
                    onFinish(prediction, Self.acceptance(of: proposal))
                } label: {
                    Label("Accept", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
    }

    /// True when accepting the capture leaves nothing outstanding.
    static func settlesEverything(_ proposal: CaptureProposal,
                                  missing: Set<MissingPurchaseFact>) -> Bool {
        !missing.isEmpty && missing.subtracting(answered(by: proposal)).isEmpty
    }

    static func answered(by proposal: CaptureProposal?) -> Set<MissingPurchaseFact> {
        guard let proposal else { return [] }
        var answered: Set<MissingPurchaseFact> = []
        if proposal.amountCad != nil { answered.insert(.amount) }
        if proposal.cardUsedId != nil { answered.insert(.card) }
        return answered
    }

    /// Taking the capture exactly as offered — so both facts are credited to it.
    static func acceptance(of proposal: CaptureProposal) -> FinishEntry {
        FinishEntry(cardUsedId: proposal.cardUsedId,
                    actualAmountCad: proposal.amountCad,
                    cardSource: proposal.cardUsedId == nil ? nil : .walletCapture,
                    amountSource: proposal.amountCad == nil ? nil : .walletCapture)
    }

    /// The charge is the fact worth putting in the chip: it is the number the owner can check
    /// against the receipt in their hand without opening anything.
    static func capturedSummary(_ proposal: CaptureProposal) -> String {
        guard let amount = proposal.amountCad else { return "Captured" }
        return String(format: "Captured $%.2f", amount)
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
    let proposal: CaptureProposal?
    let onFinish: (FinishEntry) -> Void
    let onCancel: () -> Void

    @State private var cardUsedId: String
    @State private var amountText: String

    private let missing: Set<MissingPurchaseFact>

    init(prediction: StoredPrediction, cards: [CardProduct], proposal: CaptureProposal? = nil,
         onFinish: @escaping (FinishEntry) -> Void, onCancel: @escaping () -> Void) {
        self.prediction = prediction
        self.cards = cards
        self.proposal = proposal
        self.onFinish = onFinish
        self.onCancel = onCancel
        self.missing = prediction.purchase?.missingFacts ?? []
        // A capture outranks the recommended card as a starting position, because it is an
        // observation rather than a suggestion. Both are still only starting positions: the
        // fields stay editable, and provenance is decided by what is actually saved.
        _cardUsedId = State(initialValue: prediction.purchase?.cardUsedId
                            ?? proposal?.cardUsedId
                            ?? prediction.winnerCardId)
        _amountText = State(initialValue: (prediction.purchase?.amountCad ?? proposal?.amountCad)
            .map { String(format: "%.2f", $0) } ?? "")
    }

    var body: some View {
        Form {
            Section("Where") {
                LabeledContent("Merchant", value: prediction.merchantName)
                LabeledContent("When", value: prediction.recordedAt.formatted(date: .abbreviated,
                                                                              time: .shortened))
                LabeledContent("Recommended", value: cardName(prediction.winnerCardId))
            }

            if let proposal {
                Section {
                    LabeledContent("Charged", value: proposal.amountCad
                        .map { String(format: "$%.2f", $0) } ?? "not captured")
                    LabeledContent("Card", value: proposal.cardUsedId
                        .map(cardName) ?? "not recognised")
                    LabeledContent("Tapped", value: proposal.capturedAt
                        .formatted(date: .omitted, time: .shortened))
                } header: {
                    Label("From your Apple Wallet", systemImage: "wallet.pass.fill")
                } footer: {
                    Text("Filled in below. Change anything that looks wrong — an edited figure is recorded as your own, not as the capture's.")
                        .font(.caption)
                }
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
                    Text(isAcceptingCaptureUnedited ? "Accept" : "Save")
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
        let card = missing.contains(.card) ? cardUsedId : nil
        let amount = missing.contains(.amount) ? parsedAmount : nil
        return FinishEntry(cardUsedId: card,
                           actualAmountCad: amount,
                           cardSource: card.map { proposal?.cardProvenance(forSaved: $0)
                                                  ?? .recalledLater },
                           amountSource: amount.map { proposal?.amountProvenance(forSaved: $0)
                                                      ?? .recalledLater })
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

    /// Whether every fact about to be saved is still exactly what the capture offered.
    private var isAcceptingCaptureUnedited: Bool {
        guard proposal != nil else { return false }
        let saved = entry
        let cardIsCaptured = saved.cardUsedId == nil || saved.cardSource == .walletCapture
        let amountIsCaptured = saved.actualAmountCad == nil || saved.amountSource == .walletCapture
        return cardIsCaptured && amountIsCaptured
    }

    private func cardName(_ cardId: String) -> String {
        cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }
}
