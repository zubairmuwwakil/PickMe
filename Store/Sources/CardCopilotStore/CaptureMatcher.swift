import Foundation

/// One Wallet capture joined to one checkout, with only the facts that checkout is still missing.
///
/// A proposal is an offer, never a record. Nothing here reaches `PredictionLog` until the owner
/// accepts it, which is what keeps captured evidence distinguishable from attested evidence.
public struct CaptureProposal: Equatable, Sendable, Identifiable {
    public let eventId: String
    public let predictionId: UUID
    /// nil when the charge is already known, unavailable, or in a currency this app cannot convert.
    public let amountCad: Double?
    /// nil when the card is already known or the server's alias table could not resolve it.
    public let cardUsedId: String?
    public let capturedAt: Date
    /// What to show the owner as evidence: the best merchant string the capture carried.
    public let merchantLabel: String?

    public var id: String { eventId }

    public init(eventId: String, predictionId: UUID, amountCad: Double?, cardUsedId: String?,
                capturedAt: Date, merchantLabel: String?) {
        self.eventId = eventId
        self.predictionId = predictionId
        self.amountCad = amountCad
        self.cardUsedId = cardUsedId
        self.capturedAt = capturedAt
        self.merchantLabel = merchantLabel
    }
}

/// Joins Apple Wallet captures to the checkouts they paid for (design §8, Path B).
///
/// The Shortcut is a dumb transport by design: it uploads an observation with no knowledge of
/// which prediction it answers. The join is therefore inferred, from merchant agreement and a
/// time window, and every rule below is written to fail closed. A missed match costs the owner
/// one manual entry they were doing anyway; a wrong match writes a fabricated charge into the
/// log the accuracy experiment is measured from, which is not recoverable by asking again.
public enum CaptureMatcher {
    /// How long after asking "which card?" a tap can still belong to that question. Long enough
    /// for a queue, short enough that the next errand is a different checkout.
    static let forwardWindow: TimeInterval = 30 * 60
    /// Clock skew between the Shortcut's device time and the app's, not a real ordering.
    static let backwardGrace: TimeInterval = 2 * 60

    public static func proposals(for predictions: [StoredPrediction],
                                 from feedback: [WalletFeedback]) -> [CaptureProposal] {
        // Only checkouts that are still missing something can be answered by a capture.
        let open = predictions.filter { ($0.purchase?.isComplete ?? true) == false }

        // Candidate pairs first, then a strict one-to-one filter. Building the whole grid before
        // deciding anything is what lets ambiguity be detected from both sides at once — a
        // greedy first-match walk would happily assign the earlier coffee to the later tap.
        var pairs: [(event: WalletFeedback, prediction: StoredPrediction)] = []
        for event in feedback {
            for prediction in open where isPlausible(event, for: prediction) {
                pairs.append((event, prediction))
            }
        }

        var eventCounts: [String: Int] = [:]
        var predictionCounts: [UUID: Int] = [:]
        for pair in pairs {
            eventCounts[pair.event.eventId, default: 0] += 1
            predictionCounts[pair.prediction.id, default: 0] += 1
        }

        return pairs.compactMap { pair in
            guard eventCounts[pair.event.eventId] == 1,
                  predictionCounts[pair.prediction.id] == 1 else { return nil }
            return proposal(joining: pair.event, to: pair.prediction)
        }
    }

    /// One wallet-tap that matches no open checkout at all — not even ambiguously.
    ///
    /// Unlike `CaptureProposal`, this carries no `predictionId`: there is no prediction to join it
    /// to, because the owner never asked "which card here?" for it. `AutoCaptureLog` writes it
    /// straight into the purchase log with no confirmation gate, which is safe for exactly the
    /// reason it is NOT safe for `CaptureProposal` — see that type's doc comment. A purchase with
    /// no prediction carries no accuracy claim, so there is nothing here for a wrong guess to
    /// corrupt; the worst a bad merchant/amount read can do is a purchase row worth correcting,
    /// not a fabricated data point in the Experiment Scoreboard.
    public struct UnclaimedCapture: Equatable, Sendable, Identifiable {
        public let eventId: String
        public let capturedAt: Date
        public let merchant: String
        /// nil when the charge is unavailable or in a currency this app cannot convert — see
        /// `amountCad(from:)`.
        public let amountCad: Double?
        /// nil when the server's alias table could not resolve the card.
        public let cardUsedId: String?

        public var id: String { eventId }
    }

    /// Every synced wallet-tap that does not plausibly belong to any still-open checkout.
    ///
    /// Reuses `isPlausible` — the exact test `proposals(for:from:)` uses — so the two functions can
    /// never disagree about which events belong to a live checkout. An event that plausibly matches
    /// an open prediction is excluded here even when it is too AMBIGUOUS to produce a
    /// `CaptureProposal` (matches more than one open prediction, or an open prediction matches more
    /// than one event): auto-logging it as a second, standalone purchase would risk a duplicate the
    /// moment the owner finishes the checkout it actually belonged to. Deferring entirely to Finish
    /// Purchases for anything that MIGHT be a live checkout's answer is the fail-closed choice.
    public static func unclaimedCaptures(from feedback: [WalletFeedback],
                                         openPredictions: [StoredPrediction]) -> [UnclaimedCapture] {
        let open = openPredictions.filter { ($0.purchase?.isComplete ?? true) == false }
        return feedback
            .filter { event in !open.contains { isPlausible(event, for: $0) } }
            .map { event in
                UnclaimedCapture(eventId: event.eventId,
                                 capturedAt: event.capturedAt,
                                 merchant: event.merchantNormalized ?? event.merchantRaw ?? "Unknown merchant",
                                 amountCad: amountCad(from: event),
                                 cardUsedId: event.resolvedCardId)
            }
    }

    // MARK: - Pairing

    private static func isPlausible(_ event: WalletFeedback, for prediction: StoredPrediction) -> Bool {
        let offset = event.capturedAt.timeIntervalSince(prediction.recordedAt)
        guard offset >= -backwardGrace, offset <= forwardWindow else { return false }
        return merchantsAgree(event.merchantNormalized ?? event.merchantRaw,
                              prediction.merchantName)
    }

    /// Builds the offer, or nothing when every fact is either already known or unavailable.
    private static func proposal(joining event: WalletFeedback,
                                 to prediction: StoredPrediction) -> CaptureProposal? {
        let missing = prediction.purchase?.missingFacts ?? []
        let amount = missing.contains(.amount) ? amountCad(from: event) : nil
        let card = missing.contains(.card) ? event.resolvedCardId : nil
        guard amount != nil || card != nil else { return nil }
        return CaptureProposal(eventId: event.eventId, predictionId: prediction.id,
                               amountCad: amount, cardUsedId: card,
                               capturedAt: event.capturedAt,
                               merchantLabel: event.merchantNormalized ?? event.merchantRaw)
    }

    /// A foreign charge yields no amount. The engine's FX handling is about *predicting* a fee,
    /// not about converting a settled charge — inventing a rate here would put a made-up figure
    /// into the value-recovered total.
    private static func amountCad(from event: WalletFeedback) -> Double? {
        guard let minor = event.amountMinor else { return nil }
        let currency = event.currency?.uppercased()
        guard currency == nil || currency == "CAD" else { return nil }
        return Double(minor) / 100
    }

    // MARK: - Merchant agreement

    /// Apple's transaction string and MapKit's place name are written by different systems for
    /// different purposes: "SQ *STARBUCKS #1234" and "Starbucks" are the same shop. Reduce both
    /// to their letters and accept containment either way.
    ///
    /// The four-character floor is the whole safety margin. Without it a two-letter remnant
    /// matches most of the catalogue, and containment stops being evidence of anything.
    static func merchantsAgree(_ captured: String?, _ predicted: String) -> Bool {
        guard let left = simplify(captured), let right = simplify(predicted) else { return false }
        let shorter = left.count <= right.count ? left : right
        let longer = left.count <= right.count ? right : left
        guard shorter.count >= 4 else { return false }
        return longer.contains(shorter)
    }

    private static func simplify(_ value: String?) -> String? {
        guard let value else { return nil }
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
        let letters = folded.unicodeScalars
            .filter { CharacterSet.letters.contains($0) }
            .map(String.init)
            .joined()
        return letters.isEmpty ? nil : letters
    }
}

extension CaptureProposal {
    /// Who to credit a saved fact to.
    ///
    /// The capture is credited only when the figure it offered is the figure that was saved. The
    /// moment the owner changes it, the fact is a recollection with a capture next to it — and
    /// filing that as machine evidence would quietly inflate how much of the log was measured
    /// rather than remembered.
    public func amountProvenance(forSaved amount: Double?) -> CaptureSource {
        guard let amount, let proposed = amountCad,
              // The field round-trips through a formatted string, so equality is to the cent.
              (amount * 100).rounded() == (proposed * 100).rounded() else { return .recalledLater }
        return .walletCapture
    }

    public func cardProvenance(forSaved cardId: String?) -> CaptureSource {
        guard let cardId, let proposed = cardUsedId, cardId == proposed else { return .recalledLater }
        return .walletCapture
    }
}
