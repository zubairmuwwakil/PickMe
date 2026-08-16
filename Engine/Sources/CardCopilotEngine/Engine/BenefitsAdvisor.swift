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

    /// Stable identity for SwiftUI sheets/lists.
    public var id: String { cardId + "/" + kind }

    public init(cardId: String, kind: String, coverage: BenefitCoverage,
                conditions: [String], exclusions: [String],
                verification: BenefitVerification) {
        self.cardId = cardId
        self.kind = kind
        self.coverage = coverage
        self.conditions = conditions
        self.exclusions = exclusions
        self.verification = verification
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
        if purchase.category == "hotel" || purchase.country != "CA" || purchase.currency != "CAD" {
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
                              verification: card.certificate.verificationStatus)
        }
    }

    static func disclosure(_ benefit: Benefit, cardId: String,
                           verification: BenefitVerification) -> BenefitDisclosure {
        BenefitDisclosure(cardId: cardId, kind: benefit.kind, coverage: benefit.coverage,
                          conditions: benefit.conditions, exclusions: benefit.exclusions ?? [],
                          verification: verification)
    }
}
