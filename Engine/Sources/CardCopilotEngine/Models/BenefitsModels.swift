import Foundation

/// Benefits are card metadata verified only by reading certificates of insurance —
/// a different truth procedure from earn rules (statement reconciliation) — so they live
/// in their own catalogue with their own provenance ladder (spec B5).
public enum BenefitVerification: String, Codable, Equatable, Sendable {
    case stub               // Claude-drafted scaffolding; never trusted display
    case issuerPage         // matches the public marketing page
    case certificateVerified // checked against the owner's actual cardholder document
}

/// Known families. `Benefit.family` stays an open string (same idiom as
/// `PurchaseContext.category`); this enum is the namespace for known values.
public enum BenefitFamily: String, CaseIterable, Hashable, Sendable {
    case shopping, travelDisruption, rentalCdw, travelMedical
}

/// The ten known benefit kinds (spec §4). `Benefit.kind` is an open string;
/// unknown kinds decode fine and are ignored by advisor logic.
public enum BenefitKind: String, CaseIterable, Hashable, Sendable {
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
    public var jurisdiction: String?
    public var verificationStatus: BenefitVerification

    public init(underwriter: String?, sourceUrl: String?, certificateDate: String?,
                lastVerifiedAt: String?, verificationStatus: BenefitVerification,
                jurisdiction: String? = nil) {
        self.underwriter = underwriter
        self.sourceUrl = sourceUrl
        self.certificateDate = certificateDate
        self.lastVerifiedAt = lastVerifiedAt
        self.jurisdiction = jurisdiction
        self.verificationStatus = verificationStatus
    }
}

/// Additional card documentation is intentionally an open vocabulary. Issuers use different
/// names for similar documents, and adding a new document kind must not make an older reader
/// reject the whole catalogue.
public enum CardDocumentKind: String, CaseIterable, Sendable {
    case certificateOfInsurance
    case cardholderAgreement
    case welcomeGuide
    case feeSchedule
    case claimsInstructions
    case loungeTerms
    case productPage
    case other
}

public struct CardDocument: Codable, Equatable, Identifiable, Sendable {
    public var documentId: String
    public var kind: String
    public var title: String
    public var url: String
    public var effectiveDate: String?
    public var jurisdiction: String?
    public var verificationStatus: BenefitVerification
    public var lastVerifiedAt: String?
    public var notes: String?

    public var id: String { documentId }

    public init(documentId: String, kind: String, title: String, url: String,
                effectiveDate: String? = nil, jurisdiction: String? = nil,
                verificationStatus: BenefitVerification,
                lastVerifiedAt: String? = nil, notes: String? = nil) {
        self.documentId = documentId
        self.kind = kind
        self.title = title
        self.url = url
        self.effectiveDate = effectiveDate
        self.jurisdiction = jurisdiction
        self.verificationStatus = verificationStatus
        self.lastVerifiedAt = lastVerifiedAt
        self.notes = notes
    }
}

public struct CardBenefits: Codable, Equatable, Identifiable, Sendable {
    public var cardId: String
    public var certificate: CertificateProvenance
    public var benefits: [Benefit]
    /// Optional in the wire format for backwards compatibility with catalogue 1.1.
    public var documents: [CardDocument]

    public var id: String { cardId }

    public init(cardId: String, certificate: CertificateProvenance, benefits: [Benefit],
                documents: [CardDocument] = []) {
        self.cardId = cardId
        self.certificate = certificate
        self.benefits = benefits
        self.documents = documents
    }

    private enum CodingKeys: String, CodingKey {
        case cardId, certificate, benefits, documents
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cardId = try container.decode(String.self, forKey: .cardId)
        certificate = try container.decode(CertificateProvenance.self, forKey: .certificate)
        benefits = try container.decode([Benefit].self, forKey: .benefits)
        documents = try container.decodeIfPresent([CardDocument].self, forKey: .documents) ?? []
    }
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
