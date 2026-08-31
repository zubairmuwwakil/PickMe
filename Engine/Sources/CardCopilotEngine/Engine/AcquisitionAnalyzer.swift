import Foundation

/// The earn-only answer to “which card should I add?”
///
/// This deliberately measures steady-state value, not an issuer's acquisition promotion:
///
///     marginal earn = optimal rewards(wallet + candidate) - optimal rewards(wallet)
///     net annual value = marginal earn - stated recurring annual fee
///
/// Existing wallet fees cancel out of the comparison. Welcome bonuses, first-year fee rebates,
/// credit-score effects, approval odds and non-earn benefits are not guessed.
public enum AcquisitionVerdict: String, Codable, Equatable, Sendable {
    /// Recurring marginal earn exceeds the candidate's recurring fee.
    case worthAdding
    /// It improves earn, but benefits the engine does not price must cover the remaining fee.
    case benefitsRequired
    /// It adds no earn value to this wallet on this spend distribution.
    case noEarnAdvantage
}

/// One category where adding a candidate changes the optimized wallet result.
public struct AcquisitionBucketGain: Equatable, Sendable {
    public let label: String
    public let annualSpendCad: Double
    public let valueBeforeCad: Double
    public let valueAfterCad: Double
    public let displacedCardIds: [String]

    public var marginalValueCad: Double { valueAfterCad - valueBeforeCad }
}

public struct AcquisitionCandidate: Equatable, Sendable {
    public let cardId: String
    /// Rewards the candidate earns on purchases it wins. This is not the decision number.
    public let grossRewardValueCad: Double
    /// What the whole wallet gains after every purchase is re-optimized.
    public let marginalRewardValueCad: Double
    public let annualFeeCad: Double
    /// `marginalRewardValueCad - annualFeeCad`; the ranking key.
    public let netAnnualValueCad: Double
    public let verdict: AcquisitionVerdict
    /// Non-earn value required to break even when earn alone does not cover the fee.
    public let requiredBenefitValueCad: Double
    public let feeWaiverUnresolved: Bool
    public let neverScorable: Bool
    public let bucketGains: [AcquisitionBucketGain]
    /// Whether a resident of `OwnerState.resolvedMarket` can hold this card at all —
    /// `card.eligibility?.residency ?? [card.market]`. Does NOT remove the candidate from
    /// `candidates` (never silently discard a fact the caller might want, e.g. an explicit
    /// "show other markets" override) — it only gates `recommended`, so a US card never surfaces
    /// as a default suggestion to a Canadian resident while still being comparable on request.
    public let eligibleForResident: Bool
    /// Assessment against issuer-published income paths only. It never predicts approval.
    public let incomeAssessment: IncomeRequirementAssessment
}

public struct AcquisitionAnalysis: Equatable, Sendable {
    public let profileId: String
    public let asOf: String
    public let walletCardIds: [String]
    public let baselinePortfolioValueCad: Double
    /// Ranked by recurring net annual value, best first. A negative first result honestly means
    /// no researched candidate earns its fee against this wallet and spend profile.
    public let candidates: [AcquisitionCandidate]

    public var recommended: [AcquisitionCandidate] {
        candidates.filter {
            $0.verdict == .worthAdding && $0.eligibleForResident
                && ($0.incomeAssessment.isIncomeReady
                    || $0.incomeAssessment.status == .requirementsUnavailable)
        }
    }

    public var incomeReadyCandidates: [AcquisitionCandidate] {
        candidates.filter { $0.incomeAssessment.isIncomeReady }
    }

    public var incomeInformationNeeded: [AcquisitionCandidate] {
        candidates.filter { $0.incomeAssessment.status == .needsMoreInformation }
    }

    public var incomeCloseMatches: [AcquisitionCandidate] {
        candidates.filter { $0.incomeAssessment.status == .belowPublishedMinimum }
    }

    public var incomeUnassessedCandidates: [AcquisitionCandidate] {
        candidates.filter { $0.incomeAssessment.status == .requirementsUnavailable }
    }

    public func candidate(_ cardId: String) -> AcquisitionCandidate? {
        candidates.first { $0.cardId == cardId }
    }
}

public struct AcquisitionAnalyzer {
    let catalogue: Catalogue
    /// References into `catalogue`, not definitions — see CandidateSet.
    let candidateCardIds: [String]
    let ownerState: OwnerState
    let applicationRequirements: ApplicationRequirementCatalogue?
    let applicantIncomeProfile: ApplicantIncomeProfile

    public init(catalogue: Catalogue, candidateCardIds: [String], ownerState: OwnerState,
                applicationRequirements: ApplicationRequirementCatalogue? = nil,
                applicantIncomeProfile: ApplicantIncomeProfile = .init()) {
        self.catalogue = catalogue
        self.candidateCardIds = candidateCardIds
        self.ownerState = ownerState
        self.applicationRequirements = applicationRequirements
        self.applicantIncomeProfile = applicantIncomeProfile
    }

    public func analyze(_ distribution: SpendDistribution, asOf: String) -> AcquisitionAnalysis {
        let owned = Set(ownerState.ownedCardIds)
        // One corpus: wallet products and researched candidates are the same cards, so there is
        // nothing to merge and nothing that can disagree. What still must hold is that a candidate
        // never becomes a checkout option, and that is enforced below against ownedCardIds — the
        // only thing that ever decided it. Note RecommendationEngine independently filters the
        // catalogue by ownedCardIds, so a wider corpus cannot leak into a checkout pick.
        let knownCatalogue = catalogue
        let productsById = Dictionary(catalogue.cards.map { ($0.cardId, $0) },
                                      uniquingKeysWith: { first, _ in first })
        let walletIds = owned.intersection(knownCatalogue.cards.map(\.cardId))
        let baselineAnalyzer = PortfolioAnalyzer(catalogue: knownCatalogue,
                                                 ownerState: ownerState,
                                                 cardIds: walletIds)
        let baseline = baselineAnalyzer.run(distribution, excluding: [], asOf: asOf)
        let annualSpendByLabel = Dictionary(uniqueKeysWithValues:
            distribution.buckets.map { ($0.label, $0.annualCad) })

        var results: [AcquisitionCandidate] = []
        // An id naming no product is skipped rather than fatal: a candidate list that outruns the
        // corpus should cost that one candidate, not every recommendation on the page.
        for cardId in candidateCardIds where !owned.contains(cardId) {
            guard let card = productsById[cardId] else { continue }
            let combinedIds = walletIds.union([card.cardId])
            let combined = PortfolioAnalyzer(catalogue: knownCatalogue,
                                             ownerState: ownerState,
                                             cardIds: combinedIds)
                .run(distribution, excluding: [], asOf: asOf)

            let marginal = combined.totalValueCad - baseline.totalValueCad
            let fee: Double
            if let annual = card.fee.annual {
                fee = ReportingCurrency.toReporting(annual)
            } else if let monthly = card.fee.monthly {
                fee = ReportingCurrency.toReporting(monthly) * 12
            } else {
                fee = 0
            }
            let net = marginal - fee
            let eligibleMarkets = card.eligibility?.residency ?? [card.market]
            let eligibleForResident = eligibleMarkets.contains(ownerState.resolvedMarket)
            let incomeAssessment = ApplicationRequirementEvaluator.assess(
                requirements: applicationRequirements?.requirement(for: card.cardId),
                profile: applicantIncomeProfile)
            let gains = combined.winnersByBucket.keys.compactMap { label -> AcquisitionBucketGain? in
                guard combined.winnersByBucket[label]?.contains(card.cardId) == true else {
                    return nil
                }
                let before = baseline.valueByBucket[label] ?? 0
                let after = combined.valueByBucket[label] ?? 0
                guard after > before + 0.005 else { return nil }
                return AcquisitionBucketGain(
                    label: label,
                    annualSpendCad: annualSpendByLabel[label] ?? 0,
                    valueBeforeCad: before,
                    valueAfterCad: after,
                    displacedCardIds: Array(baseline.winnersByBucket[label] ?? []).sorted())
            }.sorted {
                $0.marginalValueCad != $1.marginalValueCad
                    ? $0.marginalValueCad > $1.marginalValueCad
                    : $0.label < $1.label
            }
            let scorable = combined.scorableCards.contains(card.cardId)
            let verdict: AcquisitionVerdict
            if net > 0.01 {
                verdict = .worthAdding
            } else if marginal > 0.01 {
                verdict = .benefitsRequired
            } else {
                verdict = .noEarnAdvantage
            }

            results.append(AcquisitionCandidate(
                cardId: card.cardId,
                grossRewardValueCad: combined.valueByCard[card.cardId] ?? 0,
                marginalRewardValueCad: marginal,
                annualFeeCad: fee,
                netAnnualValueCad: net,
                verdict: verdict,
                requiredBenefitValueCad: max(0, fee - marginal),
                feeWaiverUnresolved: card.fee.waiver != nil
                    && ownerState.cardStates[card.cardId]?.feeWaiverActive == nil,
                neverScorable: !scorable,
                bucketGains: gains,
                eligibleForResident: eligibleForResident,
                incomeAssessment: incomeAssessment))
        }
        results.sort {
            $0.netAnnualValueCad != $1.netAnnualValueCad
                ? $0.netAnnualValueCad > $1.netAnnualValueCad
                : $0.cardId < $1.cardId
        }

        return AcquisitionAnalysis(profileId: distribution.profileId,
                                   asOf: asOf,
                                   walletCardIds: walletIds.sorted(),
                                   baselinePortfolioValueCad: baseline.totalValueCad,
                                   candidates: results)
    }
}
