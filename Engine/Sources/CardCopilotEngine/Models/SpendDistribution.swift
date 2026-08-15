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

public extension SpendDistribution {

    /// ⚠️ ASSUMPTION, NOT DATA. No real spend history has been captured yet, so this profile is a
    /// documented guess at a Canadian single-household year (~$40,200) shaped to exercise every
    /// category this wallet accelerates. It exists so the keep/cancel layer has something to run
    /// against — never so the analyzer can assume a distribution. Replace it the moment statement
    /// imports (v1.5) produce real category totals, and re-read every verdict when you do.
    ///
    /// Sensitivity matters more than accuracy here: a verdict that survives a ±50% reshuffle of
    /// these numbers is a real verdict, and one that doesn't is a question about the owner's
    /// spending, not about the card.
    static let placeholderCanadianHousehold = SpendDistribution(
        profileId: "placeholder-canadian-household-2026",
        basis: "ASSUMPTION (2026-08-15): no spend history exists yet. Category totals are a "
             + "documented guess at a ~$40,200 single-household year, not measured data.",
        buckets: [
            .init(label: "Groceries", annualCad: 9_000, category: "grocery", mcc: 5411,
                  merchantBrand: "loblaws"),
            .init(label: "Restaurants & coffee", annualCad: 4_200, category: "dining", mcc: 5812),
            .init(label: "Food delivery", annualCad: 900, category: "foodDelivery", mcc: 5814,
                  channel: "online"),
            .init(label: "Streaming", annualCad: 600, category: "streaming", mcc: 5968,
                  channel: "online", recurring: true),
            .init(label: "Digital media & apps", annualCad: 300, category: "digitalMedia",
                  mcc: 5815, channel: "online"),
            .init(label: "Memberships & dues", annualCad: 600, category: "memberships", mcc: 7997,
                  recurring: true),
            .init(label: "Phone & internet", annualCad: 1_800, category: "householdUtilities",
                  mcc: 4814, recurring: true),
            .init(label: "Insurance premiums", annualCad: 2_400, category: "recurring", mcc: 6300,
                  recurring: true),
            .init(label: "Gas", annualCad: 2_400, category: "gasStation", mcc: 5541),
            .init(label: "Transit & rideshare", annualCad: 1_200, category: "transit", mcc: 4121),
            .init(label: "Flights", annualCad: 1_800, category: "travel", mcc: 3000,
                  channel: "online"),
            .init(label: "Hotels (non-Marriott)", annualCad: 1_200, category: "lodging", mcc: 3501,
                  channel: "online"),
            .init(label: "Marriott stays", annualCad: 1_200, category: "marriottDirect", mcc: 3509,
                  merchantBrand: "marriott"),
            // Costco takes Mastercard only — the acceptance gate, not the earn rate, decides here.
            .init(label: "Costco", annualCad: 2_600, category: "wholesaleClub", mcc: 5300,
                  merchantBrand: "costco", acceptedNetworks: [.mastercard]),
            .init(label: "Canadian Tire family", annualCad: 1_200, category: "ctFamily", mcc: 5200,
                  merchantBrand: "canadian-tire"),
            .init(label: "Foreign currency (USD online)", annualCad: 2_000, category: "other",
                  currency: "USD", channel: "online"),
            .init(label: "Everything else", annualCad: 6_800, category: "other"),
        ])
}
