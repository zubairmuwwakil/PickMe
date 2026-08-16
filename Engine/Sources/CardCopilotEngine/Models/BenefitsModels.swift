import Foundation

/// Benefits are card metadata verified only by reading certificates of insurance —
/// a different truth procedure from earn rules (statement reconciliation) — so they live
/// in their own catalogue with their own provenance ladder (spec B5).
public enum BenefitVerification: String, Codable, Sendable {
    case stub               // Claude-drafted scaffolding; never trusted display
    case issuerPage         // matches the public marketing page
    case certificateVerified // checked against the owner's actual cardholder document
}

/// Known families. `Benefit.family` stays an open string (same idiom as
/// `PurchaseContext.category`); this enum is the namespace for known values.
public enum BenefitFamily: String, CaseIterable, Sendable {
    case shopping, travelDisruption, rentalCdw, travelMedical
}

/// The ten known benefit kinds (spec §4). `Benefit.kind` is an open string;
/// unknown kinds decode fine and are ignored by advisor logic.
public enum BenefitKind: String, CaseIterable, Sendable {
    case purchaseProtection, extendedWarranty, mobileDeviceInsurance
    case flightDelay, baggageDelay, baggageLoss, tripCancellation, tripInterruption
    case rentalCdw, travelMedical
}

/// Typed fields exist ONLY for what the comparison table sorts and displays (spec §4).
/// Everything conditional stays verbatim in `conditions`/`exclusions`.
public struct BenefitCoverage: Codable, Equatable, Sendable {
    public var windowDays: Int?
    public var maxPerOccurrenceCad: Double?
    public var maxAnnualCad: Double?
    public var extraYears: Int?
    public var maxOriginalWarrantyYears: Int?
    public var maxCad: Double?
    public var deductibleCad: Double?
    public var delayHours: Int?
    public var perDayCad: Double?
    public var maxTripLengthDays: Int?
    public var maxRentalDays: Int?
    public var maxVehicleValueCad: Double?
    public var ageLimit: Int?

    public init() {}
}

public struct Benefit: Codable, Equatable, Sendable {
    public var benefitId: String
    public var family: String
    public var kind: String
    public var coverage: BenefitCoverage
    public var conditions: [String]
    public var exclusions: [String]?
    public var certificateQuote: String?
    public var notes: String?

    public var knownKind: BenefitKind? { BenefitKind(rawValue: kind) }
    public var knownFamily: BenefitFamily? { BenefitFamily(rawValue: family) }
}

public struct CertificateProvenance: Codable, Equatable, Sendable {
    public var underwriter: String?
    public var sourceUrl: String?
    public var certificateDate: String?
    public var lastVerifiedAt: String?
    public var verificationStatus: BenefitVerification
}

public struct CardBenefits: Codable, Equatable, Identifiable, Sendable {
    public var cardId: String
    public var certificate: CertificateProvenance
    public var benefits: [Benefit]

    public var id: String { cardId }
}

/// Ambient-trigger tuning lives in data, not code (spec §5).
public struct BenefitsTriggers: Codable, Equatable, Sendable {
    public var bigTicketThresholdCad: Double
    public var consumableCategories: [String]
}

public struct BenefitsCatalogue: Codable, Equatable, Sendable {
    public var benefitsCatalogueVersion: String
    public var triggers: BenefitsTriggers
    public var cards: [CardBenefits]

    public func card(_ cardId: String) -> CardBenefits? {
        cards.first { $0.cardId == cardId }
    }
}
