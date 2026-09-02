import Foundation
import CardCopilotEngine

/// How the arrival gate guesses an amount when there is no purchase to read.
///
/// On arrival nothing has been bought, so `ambientPurchaseContext` substitutes an estimate. That
/// estimate is not decoration: the threshold's CAD floor is divided by it, which silently makes
/// the effective percentage bar depend on the category. `.fixed` exists so that dependence can be
/// switched off and measured against, rather than argued about.
public enum AmbientAmountEstimate: Equatable, Sendable, Codable {
    /// Today's behaviour: `categoryAmountEstimates`, falling back to `fallbackAmountEstimate`.
    case perCategory
    /// One amount for every category.
    case fixed(amountCad: Double)
}

/// The dials the debug screen exposes, and the only thing that stands between the shipped policy
/// and what a field build actually evaluated.
///
/// Carried as a value and recorded on every field-log record, so an export is self-describing: a
/// record that fired says which policy made it fire. Reconstructing that from the build number
/// afterwards is exactly the kind of thing nobody manages to do.
public struct AmbientAlertPolicy: Equatable, Sendable, Codable {
    /// `nil` means the owner's own threshold, untouched. An override replaces it wholesale rather
    /// than nudging it, because the two floors and the semantics only mean anything together.
    public var switchThresholdOverride: SwitchThreshold?
    public var unverifiedAdvantageMultiplier: Double
    public var frequentedAdvantageMultiplier: Double
    public var categoryAdvantageMultiplier: Double
    public var amountEstimate: AmbientAmountEstimate

    public init(switchThresholdOverride: SwitchThreshold? = nil,
                unverifiedAdvantageMultiplier: Double = AmbientGate.unverifiedAdvantageMultiplier,
                frequentedAdvantageMultiplier: Double = AmbientGate.frequentedAdvantageMultiplier,
                categoryAdvantageMultiplier: Double = AmbientGate.categoryAdvantageMultiplier,
                amountEstimate: AmbientAmountEstimate = .perCategory) {
        self.switchThresholdOverride = switchThresholdOverride
        self.unverifiedAdvantageMultiplier = unverifiedAdvantageMultiplier
        self.frequentedAdvantageMultiplier = frequentedAdvantageMultiplier
        self.categoryAdvantageMultiplier = categoryAdvantageMultiplier
        self.amountEstimate = amountEstimate
    }

    /// What the app does when nobody has touched anything.
    public static let shipped = AmbientAlertPolicy()

    public func threshold(ownerThreshold: SwitchThreshold) -> SwitchThreshold {
        switchThresholdOverride ?? ownerThreshold
    }

    /// `.verified` is deliberately absent from the dials: it is measured against the owner's own
    /// floor, unscaled, and that is the one bar on this screen that was actually earned. `.unknown`
    /// never reaches the advantage conjunct at all, so its answer is a formality.
    public func multiplier(for confidence: AmbientMerchantConfidence) -> Double {
        switch confidence {
        case .verified, .unknown: return 1
        case .brandMatched: return unverifiedAdvantageMultiplier
        case .frequented: return frequentedAdvantageMultiplier
        case .categoryMatched: return categoryAdvantageMultiplier
        }
    }
}

/// The amount an arrival is scored against, given the policy in force.
public func ambientEstimatedAmountCad(category: String,
                                      estimate: AmbientAmountEstimate) -> Double {
    switch estimate {
    case .perCategory: return categoryAmountEstimates[category] ?? fallbackAmountEstimate
    case .fixed(let amountCad): return amountCad
    }
}

/// What an arrival in one category actually has to clear, once the CAD floor has been divided by
/// a guessed basket.
///
/// The gap between `scaledMinAdvantagePercentagePoints` and `effectivePercentagePoints` is the
/// number nobody chose. It is reported rather than computed on a napkin because the whole reason
/// the shipped bar for drugstores was 2.0pp instead of 1.0pp is that no screen ever showed it.
public struct EffectiveAlertBar: Equatable, Sendable, Codable {
    public let category: String
    public let estimatedAmountCad: Double
    public let scaledMinAdvantageCad: Double
    public let scaledMinAdvantagePercentagePoints: Double
    /// What the CAD floor costs in percentage points on a basket this size. Zero when there is no
    /// basket to divide by — a screen reporting `inf` teaches nothing.
    public let cadFloorAsPercentagePoints: Double
    /// The bar the gate actually applies: the harder of the two floors under `both` semantics,
    /// the easier under `either`.
    public let effectivePercentagePoints: Double
}

public func effectiveAlertBar(category: String, ownerThreshold: SwitchThreshold,
                              policy: AmbientAlertPolicy,
                              confidence: AmbientMerchantConfidence) -> EffectiveAlertBar {
    let scaled = AmbientGate.scaled(policy.threshold(ownerThreshold: ownerThreshold),
                                    by: policy.multiplier(for: confidence))
    let amount = ambientEstimatedAmountCad(category: category, estimate: policy.amountEstimate)
    let cadAsPercentagePoints = amount > 0 ? scaled.minAdvantageCad / amount * 100 : 0
    let effective = scaled.semantics == "either"
        ? min(scaled.minAdvantagePercentagePoints, cadAsPercentagePoints)
        : max(scaled.minAdvantagePercentagePoints, cadAsPercentagePoints)
    return EffectiveAlertBar(category: category,
                             estimatedAmountCad: amount,
                             scaledMinAdvantageCad: scaled.minAdvantageCad,
                             scaledMinAdvantagePercentagePoints: scaled.minAdvantagePercentagePoints,
                             cadFloorAsPercentagePoints: cadAsPercentagePoints,
                             effectivePercentagePoints: effective)
}

/// Every category carrying an estimate, plus the fallback, ordered by basket size descending —
/// the reading order in which "smaller basket, higher bar" is a visible relationship rather than
/// a claim.
public func effectiveAlertBars(ownerThreshold: SwitchThreshold, policy: AmbientAlertPolicy,
                               confidence: AmbientMerchantConfidence) -> [EffectiveAlertBar] {
    let categories = Set(categoryAmountEstimates.keys).union(["other"])
    return categories
        .map { effectiveAlertBar(category: $0, ownerThreshold: ownerThreshold, policy: policy,
                                 confidence: confidence) }
        .sorted { ($0.estimatedAmountCad, $1.category) > ($1.estimatedAmountCad, $0.category) }
}
