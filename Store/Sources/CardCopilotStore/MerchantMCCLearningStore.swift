import Foundation
import CardCopilotEngine

/// On-device learning ledger for the merchant-MCC graph.
///
/// This intentionally stores only derived MCC evidence. It does not persist purchase amount, card,
/// statement text, or a transaction history. A future shared crowd service can exchange the same
/// evidence shape without changing the posterior math in CardCopilotEngine.
public final class MerchantMCCLearningStore: @unchecked Sendable {
    public static let shared = MerchantMCCLearningStore()

    private let defaults: UserDefaults
    private let storageKey: String
    private let seeds: [MerchantMCCSeedMerchant]
    private let lock = NSLock()
    private var evidence: [MerchantMCCRuntimeEvidence]

    public init(defaults: UserDefaults = UserDefaults(suiteName: "group.ca.inunity.pickme") ?? .standard,
                storageKey: String = "merchant-mcc-learning-evidence-v1",
                seed: MerchantMCCRuntimeSeed = SeedLoader.merchantMCCRuntimeSeed) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.seeds = seed.merchants
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([MerchantMCCRuntimeEvidence].self, from: data) {
            self.evidence = decoded
        } else {
            self.evidence = []
        }
    }

    public func seedMerchant(matching merchantName: String) -> MerchantMCCSeedMerchant? {
        let needle = Self.normalized(merchantName)
        guard !needle.isEmpty else { return nil }

        if let exact = seeds.first(where: { Self.normalized($0.name) == needle || $0.id == needle }) {
            return exact
        }

        // Payment descriptors often append store numbers/cities. Prefer the longest contained
        // merchant name so "Real Canadian Superstore #123" beats a shorter overlapping brand.
        return seeds
            .filter {
                let candidate = Self.normalized($0.name)
                return candidate.count >= 4 && Self.containsWholePhrase(needle, phrase: candidate)
            }
            .max { Self.normalized($0.name).count < Self.normalized($1.name).count }
    }

    public func posterior(merchantName: String,
                          locationKey: String? = nil,
                          network: String? = nil,
                          channel: String? = nil) -> MerchantMCCPosterior? {
        guard let seed = seedMerchant(matching: merchantName) else { return nil }
        lock.lock()
        let snapshot = evidence
        lock.unlock()
        return MerchantMCCPosteriorResolver.posterior(seed: seed, evidence: snapshot,
                                                       locationKey: locationKey,
                                                       network: network, channel: channel)
    }

    /// Advanced feedback path for a user who can see the issuer's literal four-digit MCC.
    @discardableResult
    public func recordExactMCC(merchantName: String,
                               mcc: Int,
                               locationKey: String? = nil,
                               network: String? = nil,
                               channel: String? = nil,
                               sourceFingerprint: String? = nil,
                               observedAt: Date = Date()) -> Bool {
        guard (1...9999).contains(mcc), let seed = seedMerchant(matching: merchantName) else { return false }
        let item = MerchantMCCRuntimeEvidence(merchantId: seed.id, mcc: mcc,
                                             type: .userEnteredExactMcc,
                                             locationKey: locationKey, network: network,
                                             channel: channel,
                                             sourceFingerprint: sourceFingerprint,
                                             observedAt: observedAt)
        return appendIfNew(item)
    }

    /// Low-friction path for "this earned my grocery/dining/etc. bonus". The caller supplies the
    /// MCCs compatible with that issuer reward outcome; the 0.55 inference weight is split across
    /// those possibilities rather than pretending the answer reveals one exact MCC.
    ///
    /// A fingerprint makes the observation replaceable. This matters for UI feedback: if the
    /// owner corrects a selection, the new answer replaces the old vote instead of letting one
    /// purchase count twice in contradictory directions.
    @discardableResult
    public func recordRewardOutcome(merchantName: String,
                                    candidateMCCs: [Int],
                                    locationKey: String? = nil,
                                    network: String? = nil,
                                    channel: String? = nil,
                                    sourceFingerprint: String? = nil,
                                    observedAt: Date = Date()) -> Int {
        guard let seed = seedMerchant(matching: merchantName) else { return 0 }
        let candidates = Array(Set(candidateMCCs.filter { (1...9999).contains($0) })).sorted()
        guard !candidates.isEmpty else { return 0 }
        let perCandidateWeight = MerchantMCCEvidenceType.rewardOutcomeInference.defaultWeight
            / Double(candidates.count)

        if let sourceFingerprint {
            lock.lock(); defer { lock.unlock() }
            evidence.removeAll {
                $0.merchantId == seed.id
                    && $0.type == .rewardOutcomeInference
                    && $0.sourceFingerprint == sourceFingerprint
            }
            for mcc in candidates {
                evidence.append(MerchantMCCRuntimeEvidence(
                    merchantId: seed.id, mcc: mcc,
                    type: .rewardOutcomeInference,
                    weight: perCandidateWeight,
                    locationKey: locationKey, network: network,
                    channel: channel,
                    sourceFingerprint: sourceFingerprint,
                    observedAt: observedAt))
            }
            persistLocked()
            return candidates.count
        }

        var inserted = 0
        for mcc in candidates {
            let item = MerchantMCCRuntimeEvidence(merchantId: seed.id, mcc: mcc,
                                                 type: .rewardOutcomeInference,
                                                 weight: perCandidateWeight,
                                                 locationKey: locationKey, network: network,
                                                 channel: channel,
                                                 observedAt: observedAt)
            if appendIfNew(item) { inserted += 1 }
        }
        return inserted
    }

    /// Whether this exact purchase/source has already contributed reward-outcome evidence.
    /// Used to suppress repeat prompts without exposing the private evidence ledger itself.
    public func hasRewardOutcome(merchantName: String, sourceFingerprint: String) -> Bool {
        guard let seed = seedMerchant(matching: merchantName) else { return false }
        lock.lock(); defer { lock.unlock() }
        return evidence.contains {
            $0.merchantId == seed.id
                && $0.type == .rewardOutcomeInference
                && $0.sourceFingerprint == sourceFingerprint
        }
    }

    /// Reserved for a future provider that genuinely returns a payment-network/processor MCC.
    /// Apple Wallet/Shortcuts must never call this merely because a seed contains the same code.
    @discardableResult
    public func recordNetworkObservedMCC(merchantName: String,
                                         mcc: Int,
                                         locationKey: String? = nil,
                                         network: String? = nil,
                                         channel: String? = nil,
                                         sourceFingerprint: String? = nil,
                                         observedAt: Date = Date()) -> Bool {
        guard (1...9999).contains(mcc), let seed = seedMerchant(matching: merchantName) else { return false }
        return appendIfNew(MerchantMCCRuntimeEvidence(merchantId: seed.id, mcc: mcc,
                                                      type: .networkObserved,
                                                      locationKey: locationKey, network: network,
                                                      channel: channel,
                                                      sourceFingerprint: sourceFingerprint,
                                                      observedAt: observedAt))
    }

    public func evidenceCount(for merchantName: String) -> Int {
        guard let seed = seedMerchant(matching: merchantName) else { return 0 }
        lock.lock(); defer { lock.unlock() }
        return evidence.lazy.filter { $0.merchantId == seed.id }.count
    }

    public static func locationKey(for merchant: NearbyPlace) -> String? {
        if let placeID = merchant.placeID, !placeID.isEmpty { return "mapkit:\(placeID)" }
        guard merchant.hasMonitorableLocation else { return nil }
        // ~11 m latitude granularity; enough to distinguish storefronts without treating tiny GPS
        // drift as a new terminal/location bucket.
        return String(format: "geo:%.4f,%.4f", merchant.latitude, merchant.longitude)
    }

    private func appendIfNew(_ item: MerchantMCCRuntimeEvidence) -> Bool {
        lock.lock(); defer { lock.unlock() }
        let duplicate = evidence.contains {
            $0.merchantId == item.merchantId
                && $0.mcc == item.mcc
                && $0.type == item.type
                && $0.locationKey == item.locationKey
                && $0.network == item.network
                && $0.channel == item.channel
                && item.sourceFingerprint != nil
                && $0.sourceFingerprint == item.sourceFingerprint
        }
        guard !duplicate else { return false }
        evidence.append(item)
        persistLocked()
        return true
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(evidence) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func normalized(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let flattened = folded.unicodeScalars.map {
            CharacterSet.alphanumerics.contains($0) ? String($0) : " "
        }.joined()
        return flattened.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    private static func containsWholePhrase(_ haystack: String, phrase: String) -> Bool {
        haystack == phrase || haystack.hasPrefix(phrase + " ")
            || haystack.hasSuffix(" " + phrase) || haystack.contains(" " + phrase + " ")
    }
}
