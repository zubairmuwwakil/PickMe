import Foundation
import CardCopilotEngine

/// A pre-indexed lookup record for prominent Canadian retailers and service providers.
public struct PreIndexedMerchant: Identifiable, Equatable, Sendable {
    /// Derived from the display name, NOT from the pack's slug.
    ///
    /// This id is persisted: `MerchantPatronageStore` keys visit history on it and resolves
    /// display names back through it. The pack's slug ("amazon-ca") is a different string from the
    /// historical id ("amazon.ca"), so adopting the slug would silently orphan every owner's
    /// patronage record. Changing it needs a migration, not an edit.
    public var id: String { name.lowercased() }
    public let name: String
    public let category: String
    /// Normalized needles that appear in payment descriptors and MapKit names, ordered
    /// longest-first so the most specific wins. A storefront name and a payment descriptor are
    /// different strings — MapKit says "Amazon.ca", Apple Pay says "AMZN MKTP CA" — and only the
    /// pack carries the second kind.
    public let matchKeys: [String]
    public let mcc: Int?
    public let merchantBrand: String?
    public let acceptedNetworks: Set<Network>
    public let notes: String?

    public init(name: String, category: String, matchKeys: [String] = [], mcc: Int? = nil,
                merchantBrand: String? = nil,
                acceptedNetworks: Set<Network> = [.amex, .visa, .mastercard],
                notes: String? = nil) {
        self.name = name
        self.category = category
        self.matchKeys = matchKeys
        self.mcc = mcc
        self.merchantBrand = merchantBrand
        self.acceptedNetworks = acceptedNetworks
        self.notes = notes
    }
}

/// Instant offline index for the top Canadian merchants.
///
/// A view over `contracts/merchant-pack.json`, which is the source of truth. Until 2026-09-01 the
/// rows lived here as a hand-written Swift array and the pack was generated FROM them as an export
/// for In Unity — so the pack's curated payment-descriptor `matchKeys` had no consumer in this
/// repo, and Wallet captures were matched against storefront names that never appear on a
/// statement. Inverting the arrow is what makes those keys reachable.
public struct CanadianMerchantPreIndex: Sendable {
    public static let all: [PreIndexedMerchant] = SeedLoader.merchantPack.merchants.map {
        PreIndexedMerchant(name: $0.displayName,
                           category: $0.category,
                           matchKeys: $0.matchKeys,
                           mcc: $0.mcc,
                           merchantBrand: $0.merchantBrand,
                           acceptedNetworks: $0.acceptedNetworks,
                           notes: $0.notes)
    }

    /// Searches the pre-index for merchants matching the given query with prefix & fuzzy scoring.
    public static func search(_ query: String, limit: Int = 8) -> [PreIndexedMerchant] {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanQuery.isEmpty else { return [] }

        return all.compactMap { merchant -> (merchant: PreIndexedMerchant, score: Int)? in
            let nameLower = merchant.name.lowercased()
            if nameLower == cleanQuery {
                return (merchant, 100)
            } else if nameLower.hasPrefix(cleanQuery) {
                return (merchant, 80)
            } else if nameLower.contains(" " + cleanQuery) {
                return (merchant, 60)
            } else if nameLower.contains(cleanQuery) {
                return (merchant, 40)
            } else if let brand = merchant.merchantBrand, brand.contains(cleanQuery) {
                return (merchant, 30)
            }
            return nil
        }
        .sorted { $0.score > $1.score }
        .prefix(limit)
        .map(\.merchant)
    }
}
