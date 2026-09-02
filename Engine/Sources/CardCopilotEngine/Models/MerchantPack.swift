import Foundation

/// Brand -> spend-category facts, used to resolve a payment descriptor or an e-receipt sender
/// into a category the engine can score.
///
/// Editorial research, not observed network data: an `mcc` here is what a brand is BELIEVED to
/// code as, and a consumer that scores on one must say so. That is why a pack answer enters the
/// ladder as `.brandPrior` and never outranks an owner confirmation.
public struct MerchantPack: Decodable, Sendable {
    public let packVersion: String
    public let merchants: [PackedMerchant]
}

/// One brand row.
///
/// `matchKeys` is the field the Swift pre-index never had and the reason this contract is loaded
/// rather than exported. A storefront name and a payment descriptor are different strings:
/// MapKit says "Amazon.ca", Apple Pay says "AMZN MKTP CA". Keys are pre-normalized (lowercase,
/// diacritics folded, runs of non-alphanumerics collapsed to one space) and ordered longest-first
/// so the most specific needle wins.
public struct PackedMerchant: Decodable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let category: String
    public let matchKeys: [String]
    public let emailDomains: [String]?
    public let mcc: Int?
    public let merchantBrand: String?
    public let acceptedNetworks: Set<Network>
    public let notes: String?
}
