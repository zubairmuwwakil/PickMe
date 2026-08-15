import Foundation

public struct CategoryPrediction: Equatable, Sendable {
    public let category: String
    public let confidenceSource: ConfidenceSource
    public let candidates: [String]

    public init(category: String, confidenceSource: ConfidenceSource, candidates: [String]) {
        self.category = category
        self.confidenceSource = confidenceSource
        self.candidates = candidates
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

public func predict(poiCategoryRaw: String?, merchantName: String) -> CategoryPrediction {
    let normalizedMerchant = normalizedMerchantName(merchantName)
    if let prior = brandPriors.first(where: { normalizedMerchant.contains($0.normalizedNeedle) }) {
        return CategoryPrediction(category: prior.category,
                                  confidenceSource: .brandPrior,
                                  candidates: [prior.category])
    }

    switch canonicalPoiCategory(poiCategoryRaw) {
    case "foodmarket":
        if isWalmart(normalizedMerchant) {
            return CategoryPrediction(category: "grocery",
                                      confidenceSource: .mapKitCategory,
                                      candidates: ["grocery", "other"])
        }
        return CategoryPrediction(category: "grocery",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["grocery"])
    case "gasstation":
        return CategoryPrediction(category: "gasStation",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["gasStation", "other"])
    case "restaurant", "cafe", "bakery":
        return CategoryPrediction(category: "dining",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["dining"])
    case "pharmacy":
        return CategoryPrediction(category: "drugStore",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["drugStore"])
    case "publictransport":
        return CategoryPrediction(category: "transit",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["transit"])
    case "hotel":
        return CategoryPrediction(category: "lodging",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["lodging"])
    case "movietheater":
        return CategoryPrediction(category: "entertainment",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["entertainment"])
    case "fitnesscenter":
        return CategoryPrediction(category: "fitness",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["fitness"])
    case "store":
        return CategoryPrediction(category: "other",
                                  confidenceSource: .mapKitCategory,
                                  candidates: ["other", "grocery"])
    default:
        return CategoryPrediction(category: "other",
                                  confidenceSource: .fallback,
                                  candidates: ["other"])
    }
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
