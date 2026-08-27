import Foundation

/// How often a declared bill charges.
public enum Cadence: String, Equatable, Sendable, CaseIterable {
    case weekly, biweekly, monthly, quarterly, semiAnnual, annual

    public var chargesPerYear: Double {
        switch self {
        case .weekly: return 52
        case .biweekly: return 26
        case .monthly: return 12
        case .quarterly: return 4
        case .semiAnnual: return 2
        case .annual: return 1
        }
    }
}

/// Where a declared bill is charged today.
///
/// `offWallet` is the case worth building for: a preauthorized debit from a chequing account
/// earns nothing at all, so the whole reward is recoverable. It is also the only placement the
/// owner can state with certainty without opening an issuer app.
public enum Placement: Equatable, Sendable {
    case card(String)
    /// Chequing, preauthorized debit, or a card outside this wallet. Earns zero.
    case offWallet
    /// The owner didn't say. The engine reports a best card but publishes no gain, because it
    /// has no baseline — it will not substitute the default card for an answer it wasn't given.
    case unknown
}

/// What is known about the *network's* recurring-payment indicator for this bill — which is a
/// different fact from the owner calling it recurring.
///
/// Scotia's 4% rule is driven by the flag the merchant submits, not by billing frequency
/// (research dossier §4: "a merchant's frequency alone does not make it recurring"). The engine
/// has never seen a transaction and cannot read the flag, so it carries the owner's knowledge
/// state instead of asserting the fact.
public enum RecurringFlagStatus: String, Equatable, Sendable {
    /// Declared recurring by the owner; never checked against a statement.
    case assumed
    /// A statement showed the accelerated rate posting — the flag is real.
    case confirmed
    /// A statement showed the base rate — the flag is not being submitted.
    case refuted
}

/// One owner-declared recurring bill. Every field is a declaration; nothing here is observed.
public struct RecurringPayment: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    /// Amount of a single charge, not the annual total. Caps split per transaction.
    public let amountCad: Double
    public let cadence: Cadence
    /// From the frozen earn vocabulary (decision B6) — no new categories for this feature.
    public let category: String
    /// Usually unknown to the owner. `nil` is filled from `representativeMcc` and disclosed;
    /// see `RecurringDisclosure.mccAssumed`.
    public let mcc: Int?
    public let merchantBrand: String?
    public let currency: String
    public let placement: Placement
    /// `nil` means the owner didn't say which networks the biller takes. Amex acceptance among
    /// Canadian billers is genuinely spotty, so a `nil` that produces an Amex winner is
    /// disclosed rather than silently assumed.
    public let declaredAcceptedNetworks: Set<Network>?
    public let flagStatus: RecurringFlagStatus
    /// First charge on or after the audit date, "YYYY-MM". Only meaningful for cadences that
    /// don't charge every month; when absent, the projection places the charge as late as the
    /// window allows, which preserves its "no later than" reading.
    public let nextChargeMonth: String?

    public init(id: String, label: String, amountCad: Double, cadence: Cadence,
                category: String, mcc: Int? = nil, merchantBrand: String? = nil,
                currency: String = "CAD", placement: Placement,
                declaredAcceptedNetworks: Set<Network>? = nil,
                flagStatus: RecurringFlagStatus = .assumed,
                nextChargeMonth: String? = nil) {
        self.id = id
        self.label = label
        self.amountCad = amountCad
        self.cadence = cadence
        self.category = category
        self.mcc = mcc
        self.merchantBrand = merchantBrand
        self.currency = currency
        self.placement = placement
        self.declaredAcceptedNetworks = declaredAcceptedNetworks
        self.flagStatus = flagStatus
        self.nextChargeMonth = nextChargeMonth
    }

    public var annualCad: Double { amountCad * cadence.chargesPerYear }

    /// Networks the biller is assumed to take when the owner didn't say. Visa and Mastercard
    /// acceptance is near-universal for Canadian billers; Amex is the live question, which is
    /// why the assumption is disclosed instead of narrowed here.
    public var effectiveAcceptedNetworks: Set<Network> {
        declaredAcceptedNetworks ?? [.amex, .visa, .mastercard, .discover]
    }
}

/// A declared set of recurring bills, carrying where the numbers came from — the same
/// discipline `SpendDistribution.basis` applies to spend guesses.
public struct RecurringPlan: Equatable, Sendable {
    public let planId: String
    public let basis: String
    public let payments: [RecurringPayment]

    public init(planId: String, basis: String, payments: [RecurringPayment]) {
        self.planId = planId
        self.basis = basis
        self.payments = payments
    }

    public var totalAnnualCad: Double { payments.reduce(0) { $0 + $1.annualCad } }
}

/// Representative MCCs for the categories a recurring bill can plausibly carry.
///
/// This table exists because of a sharp edge in `RuleMatcher.matches`: when a predicate has an
/// `mccInclude` list and the purchase's MCC is `nil`, matching **falls through to true**. An
/// owner who types "Bell" and knows no MCC would otherwise be handed MBNA's 5× unconditionally.
/// Supplying a stated representative MCC — and disclosing that it was supplied — is the same
/// move `SpendDistribution` already makes for its buckets.
public enum RecurringCategoryDefaults {
    public static let representativeMcc: [String: Int] = [
        "streaming": 5968,
        "digitalMedia": 5815,
        "memberships": 7997,
        "householdUtilities": 4814,
        "recurring": 6300,
        "transit": 4121,
        "foodDelivery": 5814,
        "grocery": 5411,
    ]
}

public extension RecurringPlan {

    /// The declared plan as a spend distribution, so `PortfolioAnalyzer` can answer keep/cancel
    /// over it without this component knowing anything about fees.
    ///
    /// Worth naming what this is: every distribution the keep/cancel layer has run on so far is
    /// the placeholder household profile, an explicit guess (decision #19). Declared bills are
    /// the owner's own numbers — declared, not observed, but not invented either. The basis
    /// string carries that distinction forward rather than letting the two blur.
    ///
    /// A refuted flag crosses over as `recurring: false`, or the analyzer would re-earn Scotia's
    /// 4% on a bill a statement already proved doesn't get it.
    func asSpendDistribution(profileId: String? = nil) -> SpendDistribution {
        SpendDistribution(
            profileId: profileId ?? planId,
            basis: "DECLARED recurring bills (the owner's own figures, not a spend estimate): "
                 + basis,
            buckets: payments.map { payment in
                SpendDistribution.Bucket(
                    label: payment.label,
                    annualCad: payment.annualCad,
                    category: payment.category,
                    mcc: payment.mcc
                        ?? RecurringCategoryDefaults.representativeMcc[payment.category],
                    merchantBrand: payment.merchantBrand,
                    currency: payment.currency,
                    channel: "online",
                    recurring: payment.flagStatus != .refuted,
                    acceptedNetworks: payment.effectiveAcceptedNetworks)
            })
    }

    /// ⚠️ ASSUMPTION, NOT DATA. Nobody has listed their actual subscriptions yet. This is a
    /// plausible Canadian household's recurring life, shaped so the report exercises every case
    /// the audit exists to surface: bills that are flag-independent, one that is flag-contingent,
    /// one paid off-wallet, and a lumpy annual charge. Replace it with the wizard's output; it is
    /// scaffolding for the report, never a claim about anyone.
    static let placeholderSubscriptions = RecurringPlan(
        planId: "placeholder-subscriptions-2026",
        basis: "ASSUMPTION (2026-08-16): no subscription list has been captured yet. Amounts are "
             + "a plausible Canadian household's recurring bills, not declared data.",
        payments: [
            .init(id: "netflix", label: "Netflix", amountCad: 16.99, cadence: .monthly,
                  category: "streaming", placement: .card("wealthsimple-vip")),
            .init(id: "icloud", label: "iCloud storage", amountCad: 12.99, cadence: .monthly,
                  category: "digitalMedia", placement: .card("wealthsimple-vip")),
            .init(id: "phone", label: "Phone", amountCad: 85, cadence: .monthly,
                  category: "householdUtilities", mcc: 4814,
                  placement: .card("wealthsimple-vip")),
            .init(id: "internet", label: "Internet", amountCad: 95, cadence: .monthly,
                  category: "householdUtilities", mcc: 4814,
                  placement: .card("scotia-momentum-vi-plus")),
            .init(id: "gym", label: "Gym membership", amountCad: 59, cadence: .monthly,
                  category: "memberships", mcc: 7997, placement: .card("wealthsimple-vip")),
            // The flag-contingent line, and the off-wallet one: nothing in the wallet
            // accelerates insurance except Scotia's 4%, and that needs the network's flag.
            .init(id: "home-auto-insurance", label: "Home & auto insurance", amountCad: 210,
                  cadence: .monthly, category: "recurring", mcc: 6300, placement: .offWallet),
            .init(id: "life-insurance", label: "Term life insurance", amountCad: 45,
                  cadence: .monthly, category: "recurring", mcc: 6300, placement: .offWallet),
            // Lumpy, and Mastercard-only at the till.
            .init(id: "costco-membership", label: "Costco membership", amountCad: 65,
                  cadence: .annual, category: "wholesaleClub", merchantBrand: "costco",
                  placement: .card("rogers-red-we"), declaredAcceptedNetworks: [.mastercard],
                  nextChargeMonth: "2026-11"),
        ])
}
