import Foundation

/// Small on-device ledger for reward-outcome MCC inference.
///
/// This stores only derived MerchantMCCEvidence rows. It does not duplicate the canonical seed,
/// transaction history, card, amount, or statement text. The existing Store-side MerchantMCCGraph
/// remains the one resolver used by checkout and Purchase Routes.
public final class MerchantMCCRewardFeedbackStore: @unchecked Sendable {
    public static let shared = MerchantMCCRewardFeedbackStore()

    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()
    private var evidenceRows: [MerchantMCCEvidence]

    public init(defaults: UserDefaults = UserDefaults(suiteName: "group.ca.inunity.pickme") ?? .standard,
                storageKey: String = "merchant-mcc-reward-feedback-v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([MerchantMCCEvidence].self, from: data) {
            self.evidenceRows = decoded.filter { $0.kind == .rewardOutcomeInference }
        } else {
            self.evidenceRows = []
        }
    }

    /// All local reward-inference evidence, ready to compose with seed/community/reconciled evidence.
    public func evidence() -> [MerchantMCCEvidence] {
        lock.lock(); defer { lock.unlock() }
        return evidenceRows
    }

    public func evidence(for merchantName: String) -> [MerchantMCCEvidence] {
        guard let match = MerchantMCCSeedCatalogue.match(merchantName: merchantName) else { return [] }
        let key = MerchantMCCQuery(merchantKey: match.merchant.name).merchantKey
        lock.lock(); defer { lock.unlock() }
        return evidenceRows.filter { $0.merchantKey == key }
    }

    public func hasRewardOutcome(merchantName: String, sourceFingerprint: String) -> Bool {
        guard let match = MerchantMCCSeedCatalogue.match(merchantName: merchantName) else { return false }
        let key = MerchantMCCQuery(merchantKey: match.merchant.name).merchantKey
        lock.lock(); defer { lock.unlock() }
        return evidenceRows.contains {
            $0.merchantKey == key
                && $0.kind == .rewardOutcomeInference
                && $0.sourceReference == sourceFingerprint
        }
    }

    /// Replaces any prior answer from the same purchase, then splits one 0.55-weight inference
    /// evenly across every MCC compatible with the reward category. The graph therefore learns
    /// "grocery" without fabricating "5411" when 5422/5441/etc. remain possible.
    @discardableResult
    public func recordRewardOutcome(merchantName: String,
                                    candidateMCCs: [Int],
                                    latitude: Double? = nil,
                                    longitude: Double? = nil,
                                    channel: MerchantMCCChannel = .unknown,
                                    network: String? = nil,
                                    sourceFingerprint: String,
                                    observedAt: Date = Date()) -> Int {
        guard let match = MerchantMCCSeedCatalogue.match(merchantName: merchantName) else { return 0 }
        let candidates = Array(Set(candidateMCCs.filter { (1...9999).contains($0) })).sorted()
        guard !candidates.isEmpty else { return 0 }

        let key = match.merchant.name
        let perCandidateConfidence = 1.0 / Double(candidates.count)
        let safeLatitude = latitude?.isFinite == true ? latitude : nil
        let safeLongitude = longitude?.isFinite == true ? longitude : nil

        lock.lock(); defer { lock.unlock() }
        let normalizedKey = MerchantMCCQuery(merchantKey: key).merchantKey
        evidenceRows.removeAll {
            $0.merchantKey == normalizedKey
                && $0.kind == .rewardOutcomeInference
                && $0.sourceReference == sourceFingerprint
        }

        for mcc in candidates {
            evidenceRows.append(MerchantMCCEvidence(
                id: "reward:\(sourceFingerprint):\(mcc)",
                merchantKey: key,
                latitude: safeLatitude,
                longitude: safeLongitude,
                channel: channel,
                network: network,
                mcc: mcc,
                kind: .rewardOutcomeInference,
                sourceConfidence: perCandidateConfidence,
                observedAt: observedAt,
                sourceReference: sourceFingerprint))
        }
        persistLocked()
        return candidates.count
    }

    public func forgetAll() {
        lock.lock(); defer { lock.unlock() }
        evidenceRows.removeAll()
        defaults.removeObject(forKey: storageKey)
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(evidenceRows) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
