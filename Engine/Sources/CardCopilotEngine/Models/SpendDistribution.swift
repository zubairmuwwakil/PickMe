import Foundation

/// An annual spend picture: how much goes through each rewards category in a year.
///
/// This is the input the keep/cancel question cannot be answered without — a card is only
/// worth what it earns on *this* owner's spend. No real distribution exists yet
/// (`placeholderCanadianHousehold` is an explicit assumption, not data), so the analyzer takes
/// one as a parameter and never assumes one.
public struct SpendDistribution: Equatable, Sendable {

    /// One category's annual spend, plus the representative checkout that category looks like.
    ///
    /// The checkout carries facts the category alone can't: the MCC that decides whether MBNA's
    /// 5× applies, the brand that Scotia excludes, the Mastercard-only door at Costco, the
    /// currency that triggers an FX fee. `context.amountCad` is normalised to `annualCad`; the
    /// analyzer rescales it to each simulated month.
    public struct Bucket: Equatable, Sendable {
        public let label: String
        public let annualCad: Double
        public let context: PurchaseContext

        public init(label: String, annualCad: Double, context: PurchaseContext) {
            self.label = label
            self.annualCad = annualCad
            var normalised = context
            // Keep any USD equivalent proportional to the CAD amount it was quoted against.
            if let usd = context.usdEquivalent, context.amountCad > 0 {
                normalised.usdEquivalent = usd / context.amountCad * annualCad
            }
            normalised.amountCad = annualCad
            self.context = normalised
        }

        public init(label: String, annualCad: Double, category: String, mcc: Int? = nil,
                    merchantBrand: String? = nil, currency: String = "CAD",
                    usdEquivalent: Double? = nil, country: String = "CA",
                    channel: String = "cardPresent", recurring: Bool = false,
                    acceptedNetworks: Set<Network> = [.amex, .visa, .mastercard]) {
            self.init(label: label, annualCad: annualCad,
                      context: PurchaseContext(amountCad: annualCad, currency: currency,
                                               usdEquivalent: usdEquivalent, category: category,
                                               mcc: mcc, merchantBrand: merchantBrand,
                                               country: country, channel: channel,
                                               recurringIndicator: recurring,
                                               acceptedNetworks: acceptedNetworks))
        }
    }

    public let profileId: String
    /// Where these numbers came from. Says "assumption" out loud when they are one.
    public let basis: String
    public let buckets: [Bucket]

    public init(profileId: String, basis: String, buckets: [Bucket]) {
        self.profileId = profileId
        self.basis = basis
        self.buckets = buckets
    }

    public var totalAnnualCad: Double { buckets.reduce(0) { $0 + $1.annualCad } }

    /// Rescale every bucket by a factor — used to test whether a verdict survives a different
    /// spend picture rather than only the one that was guessed.
    public func scaled(_ factor: Double, profileId: String) -> SpendDistribution {
        SpendDistribution(profileId: profileId,
                          basis: basis + " × \(factor)",
                          buckets: buckets.map {
                              Bucket(label: $0.label, annualCad: $0.annualCad * factor,
                                     context: $0.context)
                          })
    }
}
