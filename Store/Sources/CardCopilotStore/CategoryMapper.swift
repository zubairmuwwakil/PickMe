import Foundation
import CardCopilotEngine

public struct CategoryPrediction: Equatable, Sendable {
    public let category: String
    public let confidenceSource: ConfidenceSource
    public let confidenceScore: Double
    public let candidates: [String]
    public let rawCategory: String?
    public let merchantCategoryCode: Int?
    public let merchantGroupID: String?
    public let taxonomyVersion: String

    public init(category: String, confidenceSource: ConfidenceSource, candidates: [String],
                confidenceScore: Double? = nil, rawCategory: String? = nil,
                merchantCategoryCode: Int? = nil, merchantGroupID: String? = nil,
                taxonomyVersion: String = CategoryTaxonomy.taxonomyVersion) {
        self.category = CategoryTaxonomy.canonicalID(category)
        self.confidenceSource = confidenceSource
        self.confidenceScore = min(1, max(0, confidenceScore ?? confidenceSource.defaultScore))
        self.candidates = candidates.map(CategoryTaxonomy.canonicalID)
        self.rawCategory = rawCategory
        self.merchantCategoryCode = merchantCategoryCode
        self.merchantGroupID = merchantGroupID ?? CategoryTaxonomy.merchantGroupID(for: category)
        self.taxonomyVersion = taxonomyVersion
    }
}

private struct BrandPrior: Sendable {
    let normalizedNeedle: String
    let category: String
}

// High-confidence seed priors only, sourced from the 2026-08-15 design dossier §6.
// Do not grow this into a speculative chain table: Walmart, gas kiosks, and mixed venues
// stay ambiguous until owner-observed terminal evidence exists.
private let brandPriors: [BrandPrior] = [
    .init(normalizedNeedle: normalizedMerchantName("canadian tire"), category: "ctFamily"),
    .init(normalizedNeedle: normalizedMerchantName("sport chek"), category: "ctFamily"),
    .init(normalizedNeedle: normalizedMerchantName("mark's"), category: "ctFamily"),
    .init(normalizedNeedle: normalizedMerchantName("atmosphere"), category: "ctFamily"),
    .init(normalizedNeedle: normalizedMerchantName("party city"), category: "ctFamily"),
    .init(normalizedNeedle: normalizedMerchantName("pro hockey life"), category: "ctFamily"),
    .init(normalizedNeedle: normalizedMerchantName("sports experts"), category: "ctFamily"),
    .init(normalizedNeedle: normalizedMerchantName("costco"), category: "wholesaleClub"),
    .init(normalizedNeedle: normalizedMerchantName("marriott"), category: "marriottDirect"),
]

public func predict(poiCategoryRaw: String?, merchantName: String,
                    merchantCategoryCode: Int? = nil) -> CategoryPrediction {
    if let merchantCategoryCode,
       let category = observedMCCCategory(merchantCategoryCode) {
        return CategoryPrediction(category: category, confidenceSource: .observedMcc,
                                  candidates: [category], rawCategory: poiCategoryRaw,
                                  merchantCategoryCode: merchantCategoryCode)
    }
    let normalizedMerchant = normalizedMerchantName(merchantName)
    if let prior = brandPriors.first(where: { normalizedMerchant.contains($0.normalizedNeedle) }) {
        return CategoryPrediction(category: prior.category,
                                  confidenceSource: .brandPrior,
                                  candidates: [prior.category], rawCategory: poiCategoryRaw)
    }

    switch canonicalPoiCategory(poiCategoryRaw) {
    case "foodmarket":
        if isWalmart(normalizedMerchant) {
            return CategoryPrediction(category: "grocery",
                                      confidenceSource: .mapKitCategory,
                                      candidates: ["grocery", "other"], rawCategory: poiCategoryRaw)
        }
        return CategoryPrediction(category: "grocery",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["grocery"], rawCategory: poiCategoryRaw)
    case "gasstation":
        return CategoryPrediction(category: "gasStation",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["gasStation", "other"], rawCategory: poiCategoryRaw)
    case "restaurant", "cafe", "bakery":
        return CategoryPrediction(category: "dining",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["dining"], rawCategory: poiCategoryRaw)
    case "pharmacy":
        return CategoryPrediction(category: "drugStore",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["drugStore"], rawCategory: poiCategoryRaw)
    case "publictransport":
        return CategoryPrediction(category: "transit",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["transit"], rawCategory: poiCategoryRaw)
    case "hotel":
        return CategoryPrediction(category: "lodging",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["lodging"], rawCategory: poiCategoryRaw)
    case "movietheater":
        return CategoryPrediction(category: "entertainment",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["entertainment"], rawCategory: poiCategoryRaw)
    case "fitnesscenter":
        return CategoryPrediction(category: "fitness",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["fitness"], rawCategory: poiCategoryRaw)
    case "store":
        return CategoryPrediction(category: "other",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["other", "grocery"], rawCategory: poiCategoryRaw)
    default:
        return CategoryPrediction(category: "other",
                                  confidenceSource: .fallback,
                                  candidates: ["other"], rawCategory: poiCategoryRaw)
    }
}

/// Only MCCs with a stable, single meaning enter this table. Ambiguous department stores and
/// marketplaces deliberately stay absent and flow to merchant/owner evidence instead.
public func observedMCCCategory(_ mcc: Int) -> String? {
    switch mcc {
    case 4111, 4121: return "transit"
    case 5411: return "grocery"
    case 5541, 5542: return "gasStation"
    case 5812, 5814: return "dining"
    case 5912: return "drugStore"
    case 7011: return "lodging"
    case 7512: return "carRental"
    default: return nil
    }
}

/// Resolves a learned terminal through the truth graph before falling back to the ordinary
/// category mapper. The confidence source is intentionally preserved so an ambient caller can
/// apply its silence-first gate without duplicating the graph's promotion rules.
public func predictionForKnownMerchant(_ merchant: StoredMerchant) -> CategoryPrediction {
    if let category = merchant.confirmedCategory {
        return CategoryPrediction(
            category: category,
            confidenceSource: merchant.confirmationCount >= 2 ? .repeatedTerminal
                                                              : .ownerConfirmedTerminal,
            candidates: [category],
            confidenceScore: merchant.categoryConfidenceScore,
            rawCategory: merchant.rawCategory,
            merchantCategoryCode: merchant.merchantCategoryCode,
            merchantGroupID: merchant.merchantGroupID,
            taxonomyVersion: merchant.categoryTaxonomyVersion ?? CategoryTaxonomy.taxonomyVersion)
    }
    return predict(poiCategoryRaw: merchant.poiCategoryRaw, merchantName: merchant.name,
                   merchantCategoryCode: merchant.merchantCategoryCode)
}

private func isWalmart(_ normalizedMerchant: String) -> Bool {
    normalizedMerchant.contains("walmart")
}

private func canonicalPoiCategory(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let folded = raw.folding(options: [.diacriticInsensitive, .caseInsensitive],
                             locale: Locale(identifier: "en_CA"))
    let compact = folded.unicodeScalars
        .filter { CharacterSet.alphanumerics.contains($0) }
        .map(String.init)
        .joined()
        .lowercased()

    if compact.hasPrefix("mkpoicategory") {
        return String(compact.dropFirst("mkpoicategory".count))
    }
    return compact.isEmpty ? nil : compact
}

private func normalizedMerchantName(_ merchantName: String) -> String {
    let folded = merchantName.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                      locale: Locale(identifier: "en_CA"))
    var scalars: [String] = []
    var lastWasSpace = true
    for scalar in folded.unicodeScalars {
        if CharacterSet.alphanumerics.contains(scalar) {
            scalars.append(String(scalar).lowercased())
            lastWasSpace = false
        } else if !lastWasSpace {
            scalars.append(" ")
            lastWasSpace = true
        }
    }
    return scalars.joined().trimmingCharacters(in: .whitespaces)
}

/// Categories the mapper can predict that no catalogue rule names — they score at each card's
/// base rate, but the owner can still stand in one of them and must be able to say so.
private let unscoredPredictableCategories = [
    "other", "wholesaleClub", "drugStore", "entertainment", "fitness",
]

/// Rule-side markers that are not merchant categories. `ownerSelectedTangerineCategory` stands
/// in for whichever categories the owner picked on Tangerine (`ownerSelectedCategory` is the
/// same marker, generalized 2026-08-26 for non-Tangerine selectable-category cards); no
/// statement ever shows either, so offering them in the reconcile picker would invite a
/// meaningless answer.
private let ruleSideMarkers = CategoryTaxonomy.ruleSideCategoryIDs

/// Every category the reconcile picker may offer: what the catalogue can score, plus what the
/// mapper can predict. Derived from the catalogue rather than hand-listed, because the failure
/// mode is silent — a category the app can predict but the owner cannot select when correcting
/// it pushes real misses into whichever neighbouring option happened to be on screen.
public func observableCategories(in catalogue: Catalogue) -> [String] {
    let fromRules = catalogue.cards
        .flatMap(\.earnRules)
        .compactMap(\.predicate.categories)
        .flatMap { $0 }
    return Set(fromRules + unscoredPredictableCategories)
        .subtracting(ruleSideMarkers)
        .sorted()
}

/// Human-readable form of an engine category token, for pickers and summaries.
public func categoryDisplayName(_ category: String) -> String {
    CategoryTaxonomy.displayName(for: category)
}
