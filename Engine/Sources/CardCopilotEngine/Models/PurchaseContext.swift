import Foundation

/// One checkout's facts. Everything the engine knows about the purchase in front of the user.
public struct PurchaseContext: Codable, Equatable, Sendable {
    public var amountCad: Double
    public var currency: String
    public var usdEquivalent: Double?
    public var category: String
    public var mcc: Int?
    public var merchantBrand: String?
    public var country: String
    public var channel: String
    public var recurringIndicator: Bool
    public var acceptedNetworks: Set<Network>

    public init(amountCad: Double, currency: String = "CAD", usdEquivalent: Double? = nil,
                category: String, mcc: Int? = nil, merchantBrand: String? = nil,
                country: String = "CA", channel: String = "cardPresent",
                recurringIndicator: Bool = false,
                acceptedNetworks: Set<Network> = [.amex, .visa, .mastercard]) {
        self.amountCad = amountCad
        self.currency = currency
        self.usdEquivalent = usdEquivalent
        self.category = category
        self.mcc = mcc
        self.merchantBrand = merchantBrand
        self.country = country
        self.channel = channel
        self.recurringIndicator = recurringIndicator
        self.acceptedNetworks = acceptedNetworks
    }

    private enum CodingKeys: String, CodingKey {
        case amountCad, currency, usdEquivalent, category, mcc, merchantBrand,
             country, channel, recurringIndicator, acceptedNetworks
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amountCad = try c.decode(Double.self, forKey: .amountCad)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "CAD"
        usdEquivalent = try c.decodeIfPresent(Double.self, forKey: .usdEquivalent)
        category = try c.decode(String.self, forKey: .category)
        mcc = try c.decodeIfPresent(Int.self, forKey: .mcc)
        merchantBrand = try c.decodeIfPresent(String.self, forKey: .merchantBrand)
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? "CA"
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? "cardPresent"
        recurringIndicator = try c.decodeIfPresent(Bool.self, forKey: .recurringIndicator) ?? false
        acceptedNetworks = Set(try c.decodeIfPresent([Network].self, forKey: .acceptedNetworks)
                               ?? [.amex, .visa, .mastercard])
    }
}
