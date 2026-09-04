import Foundation

/// One local observation that a Wallet/processor descriptor refers to a canonical merchant in the
/// 500-row MCC seed. The raw transaction, amount and card are deliberately not duplicated here;
/// only the normalized alias and a source fingerprint are needed to learn identity.
public struct MerchantMCCIdentityObservation: Codable, Equatable, Sendable {
    public let aliasKey: String
    public let merchantID: String
    public let sourceFingerprint: String
    public let observedAt: Date

    public init(aliasKey: String, merchantID: String, sourceFingerprint: String,
                observedAt: Date) {
        self.aliasKey = aliasKey
        self.merchantID = merchantID
        self.sourceFingerprint = sourceFingerprint
        self.observedAt = observedAt
    }
}

/// Small on-device identity ledger for aliases learned from real purchase joins.
///
/// This intentionally does not make fuzzy guesses. A learned alias is an exact normalized token
/// sequence and becomes actionable only after two independent source fingerprints agree on one
/// canonical merchant. If the same alias has ever been anchored to multiple merchants, resolution
/// fails closed until the evidence is corrected rather than choosing a majority winner.
public final class MerchantMCCIdentityLearningStore: @unchecked Sendable {
    public static let shared = MerchantMCCIdentityLearningStore()

    public static let minimumIndependentObservations = 2
    private static let maximumStoredObservations = 5_000

    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()
    private var observations: [MerchantMCCIdentityObservation]

    public init(defaults: UserDefaults = UserDefaults(suiteName: "group.ca.inunity.pickme") ?? .standard,
                storageKey: String = "merchant-mcc-identity-learning-v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([MerchantMCCIdentityObservation].self,
                                                    from: data) {
            self.observations = decoded
        } else {
            self.observations = []
        }
    }

    /// Records one independently identifiable observation. Returns true only when a new row was
    /// persisted. Replaying the same wallet event is idempotent.
    ///
    /// The canonical merchant must already exist in the seed. This store therefore learns aliases;
    /// it never invents new merchant identities or turns an unknown descriptor into a guessed brand.
    @discardableResult
    public func record(alias: String, merchantID: String, sourceFingerprint: String,
                       observedAt: Date = Date()) -> Bool {
        let aliasKey = Self.normalizedAlias(alias)
        let fingerprint = sourceFingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !aliasKey.isEmpty, !fingerprint.isEmpty,
              MerchantMCCSeedCatalogue.match(merchantID: merchantID) != nil else { return false }

        // Do not shadow deterministic curated/seed evidence. The learned layer exists only for
        // descriptors the canonical resolver cannot already settle.
        guard MerchantMCCSeedCatalogue.canonicalMatch(merchantName: alias) == nil else {
            return false
        }

        lock.lock(); defer { lock.unlock() }
        if observations.contains(where: {
            $0.aliasKey == aliasKey && $0.sourceFingerprint == fingerprint
        }) {
            return false
        }

        observations.append(MerchantMCCIdentityObservation(aliasKey: aliasKey,
                                                           merchantID: merchantID,
                                                           sourceFingerprint: fingerprint,
                                                           observedAt: observedAt))
        if observations.count > Self.maximumStoredObservations {
            observations.sort { $0.observedAt > $1.observedAt }
            observations.removeLast(observations.count - Self.maximumStoredObservations)
        }
        persistLocked()
        return true
    }

    /// Exact learned-alias lookup. Two independent observations must agree, and any merchant
    /// conflict disables the alias rather than being settled by a vote.
    public func match(merchantName: String) -> MerchantMCCSeedMatch? {
        let aliasKey = Self.normalizedAlias(merchantName)
        guard !aliasKey.isEmpty else { return nil }

        lock.lock()
        let matching = observations.filter { $0.aliasKey == aliasKey }
        lock.unlock()

        let merchantIDs = Set(matching.map(\.merchantID))
        guard merchantIDs.count == 1,
              let merchantID = merchantIDs.first,
              Set(matching.map(\.sourceFingerprint)).count >= Self.minimumIndependentObservations
        else { return nil }
        return MerchantMCCSeedCatalogue.match(merchantID: merchantID)
    }

    /// Exposed for diagnostics/tests without exposing transaction data, because none is stored.
    public func evidenceCount(for merchantName: String) -> Int {
        let aliasKey = Self.normalizedAlias(merchantName)
        lock.lock(); defer { lock.unlock() }
        return Set(observations.filter { $0.aliasKey == aliasKey }.map(\.sourceFingerprint)).count
    }

    public static func normalizedAlias(_ value: String) -> String {
        MerchantRecognizer.tokens(value).joined(separator: " ")
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(observations) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
