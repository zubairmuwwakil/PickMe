import Foundation

/// Pure benefits logic — the disclosure half of spec §5. Deliberately has no path into the
/// scoring pipeline and is never called by it (spec B1): earn advice and protection facts
/// meet only in the UI, side by side. Nothing here is a value judgement; every output is a
/// fact from a certificate, carried with its verification status.
public struct BenefitDisclosure: Equatable, Sendable, Identifiable {
    public let cardId: String
    public let kind: String
    public let coverage: BenefitCoverage
    public let conditions: [String]
    public let exclusions: [String]
    public let verification: BenefitVerification
    /// Certificate provenance travels with a disclosure so every comparison row can open
    /// the same source and verification context as the reference library.
    public let underwriter: String?
    public let sourceURL: String?
    public let certificateDate: String?
    public let lastVerifiedAt: String?
    public let jurisdiction: String?

    /// Stable identity for SwiftUI sheets/lists.
    public var id: String { cardId + "/" + kind }

    public init(cardId: String, kind: String, coverage: BenefitCoverage,
                conditions: [String], exclusions: [String],
                verification: BenefitVerification,
                underwriter: String? = nil, sourceURL: String? = nil,
                certificateDate: String? = nil, lastVerifiedAt: String? = nil,
                jurisdiction: String? = nil) {
        self.cardId = cardId
        self.kind = kind
        self.coverage = coverage
        self.conditions = conditions
        self.exclusions = exclusions
        self.verification = verification
        self.underwriter = underwriter
        self.sourceURL = sourceURL
        self.certificateDate = certificateDate
        self.lastVerifiedAt = lastVerifiedAt
        self.jurisdiction = jurisdiction
    }
}

/// "Another wallet card has coverage the recommended card lacks entirely." Never re-ranks —
/// the UI renders it as a compare link into the protection lens (spec §6).
public struct CrossCardNudge: Equatable, Sendable {
    public let cardId: String
    public let kind: String

    public init(cardId: String, kind: String) {
        self.cardId = cardId
        self.kind = kind
    }
}

public struct DisclosureResult: Equatable, Sendable {
    public let recommended: [BenefitDisclosure]
    public let nudges: [CrossCardNudge]
}

public enum BenefitsAdvisor {

    /// Path 1 — ambient disclosure at checkout. Conservative triggers over the checkout's
    /// existing facts (spec §5): big-ticket non-consumable spend surfaces the shopping
    /// family; hotel category or foreign country/currency surfaces the travel families.
    public static func disclosures(purchase: PurchaseContext,
                                   recommendedCardId: String,
                                   wallet: [String],
                                   catalogue: BenefitsCatalogue) -> DisclosureResult {
        let families = triggeredFamilies(purchase: purchase, triggers: catalogue.triggers)
        guard !families.isEmpty else { return DisclosureResult(recommended: [], nudges: []) }

        let recommended = relevantBenefits(of: recommendedCardId, families: families,
                                           catalogue: catalogue)
        let recommendedKinds = Set(recommended.map(\.kind))

        var nudges: [CrossCardNudge] = []
        var nudgedKinds: Set<String> = []
        for cardId in wallet where cardId != recommendedCardId {
            for disclosure in relevantBenefits(of: cardId, families: families, catalogue: catalogue)
            where !recommendedKinds.contains(disclosure.kind) && !nudgedKinds.contains(disclosure.kind) {
                nudges.append(CrossCardNudge(cardId: cardId, kind: disclosure.kind))
                nudgedKinds.insert(disclosure.kind)
            }
        }
        return DisclosureResult(recommended: recommended, nudges: nudges)
    }

    // MARK: - Shared internals (the comparison path reuses these)

    static func triggeredFamilies(purchase: PurchaseContext,
                                  triggers: BenefitsTriggers) -> Set<BenefitFamily> {
        var families: Set<BenefitFamily> = []
        if purchase.amountCad >= triggers.bigTicketThresholdCad
            && !triggers.consumableCategories.contains(purchase.category) {
            families.insert(.shopping)
        }
        // PurchaseContext canonicalizes both "hotel" and "hotels" to "lodging".
        if purchase.category == "lodging" || purchase.country != "CA" || purchase.currency != "CAD" {
            families.insert(.travelDisruption)
            families.insert(.travelMedical)
        }
        return families
    }

    static func relevantBenefits(of cardId: String, families: Set<BenefitFamily>,
                                 catalogue: BenefitsCatalogue) -> [BenefitDisclosure] {
        guard let card = catalogue.card(cardId) else { return [] }
        return card.benefits.compactMap { benefit in
            guard benefit.knownKind != nil,
                  let family = benefit.knownFamily, families.contains(family) else { return nil }
            return disclosure(benefit, cardId: cardId,
                              certificate: card.certificate)
        }
    }

    static func disclosure(_ benefit: Benefit, cardId: String,
                           certificate: CertificateProvenance) -> BenefitDisclosure {
        BenefitDisclosure(cardId: cardId, kind: benefit.kind, coverage: benefit.coverage,
                          conditions: benefit.conditions, exclusions: benefit.exclusions ?? [],
                          verification: certificate.verificationStatus,
                          underwriter: certificate.underwriter,
                          sourceURL: certificate.sourceUrl,
                          certificateDate: certificate.certificateDate,
                          lastVerifiedAt: certificate.lastVerifiedAt,
                          jurisdiction: certificate.jurisdiction)
    }
}

/// The purchase kinds a user can declare for protection/final-decision context. Deliberately NOT
/// merchant categories (spec B6): earn categories describe the merchant and are statement-
/// verifiable; these describe the item/intent and only the buyer knows them. `other` means the
/// buyer explicitly says none of the modelled protection-sensitive contexts apply; it is not
/// equivalent to missing context.
public enum BenefitContextKind: String, CaseIterable, Sendable {
    case flight, trip, carRental, electronics, mobileDevice, applianceFurniture, other
}

/// `Hashable` because the App target routes to the protection lens through a SwiftUI
/// NavigationPath, which stores type-erased Hashable values. Additive: it touches no JSON and
/// no fixture, so it is not a catalogue contract change.
public struct BenefitContext: Hashable, Sendable {
    public var kind: BenefitContextKind
    public var abroad: Bool

    public init(kind: BenefitContextKind, abroad: Bool = false) {
        self.kind = kind
        self.abroad = abroad
    }

    /// Spec §5 declared-context → relevant-kinds table.
    public var relevantKinds: [BenefitKind] {
        let base: [BenefitKind]
        switch kind {
        case .flight, .trip:
            base = [.flightDelay, .baggageDelay, .baggageLoss, .tripCancellation, .tripInterruption]
        case .carRental:
            base = [.rentalCdw]
        case .electronics, .applianceFurniture:
            return [.purchaseProtection, .extendedWarranty]
        case .mobileDevice:
            return [.purchaseProtection, .extendedWarranty, .mobileDeviceInsurance]
        case .other:
            return []
        }
        return abroad ? base + [.travelMedical] : base
    }
}

public struct ProtectionComparison: Equatable, Sendable {
    public struct Column: Equatable, Sendable {
        public let cardId: String
        public let verification: BenefitVerification
        /// Keyed by `BenefitKind.rawValue`; only relevant kinds appear.
        public let byKind: [String: BenefitDisclosure]
    }

    /// A wallet card with no relevant coverage. Absence semantics depend on verification
    /// (spec B8): stub = "unknown", certificateVerified = "no coverage". UI renders the difference.
    public struct AbsentCard: Equatable, Sendable {
        public let cardId: String
        public let verification: BenefitVerification
    }

    public let relevantKinds: [BenefitKind]
    public let columns: [Column]
    public let absent: [AbsentCard]
    /// Spec B7: set iff exactly one card is Pareto-maximal over every displayed coverage row.
    /// nil = genuine trade-off (or nothing to compare); UI shows "trade-off — your call".
    public let dominantCardId: String?
}

extension BenefitsAdvisor {

    /// Path 2 — the protection lens (spec §5). Facts per card for a declared purchase kind,
    /// plus a dominance verdict that only ever claims what the table beneath it shows.
    public static func comparison(context: BenefitContext,
                                  wallet: [String],
                                  catalogue: BenefitsCatalogue) -> ProtectionComparison {
        let kinds = context.relevantKinds
        let kindKeys = Set(kinds.map(\.rawValue))

        var columns: [ProtectionComparison.Column] = []
        var absent: [ProtectionComparison.AbsentCard] = []
        for cardId in wallet {
            guard let card = catalogue.card(cardId) else { continue }
            let relevant = card.benefits.filter {
                $0.knownKind != nil && kindKeys.contains($0.kind)
            }
            if relevant.isEmpty {
                absent.append(.init(cardId: cardId,
                                    verification: card.certificate.verificationStatus))
            } else {
                let byKind = Dictionary(relevant.map {
                    ($0.kind, disclosure($0, cardId: cardId,
                                         certificate: card.certificate))
                }, uniquingKeysWith: { first, _ in first })
                columns.append(.init(cardId: cardId,
                                     verification: card.certificate.verificationStatus,
                                     byKind: byKind))
            }
        }

        return ProtectionComparison(relevantKinds: kinds, columns: columns, absent: absent,
                                    dominantCardId: dominant(columns: columns, kinds: kinds))
    }

    // MARK: - Dominance internals

    /// Comparable coverage fields and their direction. Higher is better except where a
    /// lower number pays out sooner or costs less.
    ///
    /// TWO INVARIANTS, both load-bearing for spec B7 — the badge may only claim what the user
    /// can check on the rows beneath it:
    ///
    /// 1. Every field listed here MUST be rendered by `BenefitsFormatting.factsLine`. A field
    ///    that votes without appearing makes the "equal or better on every line below" claim
    ///    unfalsifiable. (The reverse is fine: a displayed field need not vote.)
    /// 2. Only *magnitudes* belong here — quantities where more is plainly better coverage, so
    ///    that a missing value can honestly score worst. `maxOriginalWarrantyYears` is
    ///    deliberately absent: it is an eligibility ceiling ("originals of five years or less
    ///    qualify"), and a certificate stating no ceiling plausibly means *no restriction* —
    ///    the best case, not the worst. Scoring its absence as -infinity ranked cards backwards.
    ///    Eligibility gates belong in `conditions`, and on screen, not in this table.
    private struct FieldSpec {
        let name: String
        let lowerIsBetter: Bool
        let value: (BenefitCoverage) -> Double?
    }

    private static let fieldSpecs: [FieldSpec] = [
        .init(name: "windowDays", lowerIsBetter: false) { $0.windowDays.map(Double.init) },
        .init(name: "maxPerOccurrenceCad", lowerIsBetter: false) { $0.maxPerOccurrenceCad },
        .init(name: "maxAnnualCad", lowerIsBetter: false) { $0.maxAnnualCad },
        .init(name: "extraYears", lowerIsBetter: false) { $0.extraYears.map(Double.init) },
        .init(name: "maxCad", lowerIsBetter: false) { $0.maxCad },
        .init(name: "deductibleCad", lowerIsBetter: true) { $0.deductibleCad },
        .init(name: "delayHours", lowerIsBetter: true) { $0.delayHours.map(Double.init) },
        .init(name: "perDayCad", lowerIsBetter: false) { $0.perDayCad },
        .init(name: "maxTripLengthDays", lowerIsBetter: false) { $0.maxTripLengthDays.map(Double.init) },
        .init(name: "maxRentalDays", lowerIsBetter: false) { $0.maxRentalDays.map(Double.init) },
        .init(name: "maxVehicleValueCad", lowerIsBetter: false) { $0.maxVehicleValueCad },
        .init(name: "ageLimit", lowerIsBetter: false) { $0.ageLimit.map(Double.init) },
    ]

    /// Spec B7. Rows = every (relevant kind, coverage field) pair that any column has a
    /// value for. Scores are normalized so higher always means better; a card missing the
    /// kind or the field scores worst (-infinity). Badge iff exactly one maximal column.
    private static func dominant(columns: [ProtectionComparison.Column],
                                 kinds: [BenefitKind]) -> String? {
        guard !columns.isEmpty else { return nil }

        var rows: [[Double]] = []   // rows[r][columnIndex] = normalized score
        for kind in kinds {
            for spec in fieldSpecs {
                let raw = columns.map { column -> Double? in
                    column.byKind[kind.rawValue].flatMap { spec.value($0.coverage) }
                }
                guard raw.contains(where: { $0 != nil }) else { continue }
                rows.append(raw.map { value in
                    guard let value else { return -Double.infinity }
                    return spec.lowerIsBetter ? -value : value
                })
            }
        }
        // Presence itself is a row: covering a kind at all beats not covering it, even when
        // the certificate states no comparable number for it.
        for kind in kinds {
            let presence = columns.map { $0.byKind[kind.rawValue] != nil ? 1.0 : -Double.infinity }
            if presence.contains(1.0) { rows.append(presence) }
        }
        guard !rows.isEmpty else { return nil }

        func dominates(_ a: Int, _ b: Int) -> Bool {
            var strictlyBetterSomewhere = false
            for row in rows {
                if row[a] < row[b] { return false }
                if row[a] > row[b] { strictlyBetterSomewhere = true }
            }
            return strictlyBetterSomewhere
        }

        let maximal = columns.indices.filter { candidate in
            !columns.indices.contains { other in
                other != candidate && dominates(other, candidate)
            }
        }
        // A tie (identical rows) leaves every tied column maximal → no badge, exactly as
        // spec B7 requires "exactly one maximal card".
        guard maximal.count == 1 else { return nil }
        return columns[maximal[0]].cardId
    }
}
