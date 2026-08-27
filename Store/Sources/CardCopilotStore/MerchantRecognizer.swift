import Foundation

/// Identifies which pre-indexed merchant a place name refers to.
///
/// Distinct from `CanadianMerchantPreIndex.search`, which serves a human typing into a field and
/// may return many loose candidates. Recognition answers a machine's question — "which merchant
/// IS this?" — returns at most one, and returns nothing rather than a guess, because its answer
/// decides whether the app interrupts someone.
public enum MerchantRecognizer {

    /// The pre-indexed merchant this place name refers to, or nil when none is certain.
    ///
    /// Ties break toward the longer match, so "Walmart Supercentre" (grocery, 5411) wins over
    /// the bare "Walmart" row (other, 5310) rather than the other way round.
    public static func recognise(_ displayName: String) -> PreIndexedMerchant? {
        let haystack = tokens(displayName)
        guard !haystack.isEmpty else { return nil }

        var best: (merchant: PreIndexedMerchant, length: Int)?
        for entry in aliasIndex {
            guard matches(entry.alias, in: haystack) else { continue }
            if best == nil || entry.alias.tokens.count > best!.length {
                best = (entry.merchant, entry.alias.tokens.count)
            }
        }
        return best?.merchant
    }

    /// Every alias of every indexed merchant, tokenised once.
    ///
    /// Built once rather than per call because the caller is a geofence wake: `resolve` runs this
    /// for every POI in the arrived-at area, and rebuilding ~250 aliases — each involving a
    /// regular expression — on each of those is exactly the kind of background cost this
    /// subsystem is otherwise careful to avoid.
    private static let aliasIndex: [(alias: Alias, merchant: PreIndexedMerchant)] =
        CanadianMerchantPreIndex.all.flatMap { merchant in
            aliases(for: merchant.name).map { (alias: $0, merchant: merchant) }
        }

    // MARK: - Aliases

    /// One way a merchant's name can appear on a storefront or in a MapKit result.
    struct Alias {
        let tokens: [String]
        /// Whether this form was written by the index author (`false`) or derived by this file
        /// (`true`). Derived forms are held to a stricter matching rule — see `matches`.
        let isDerived: Bool
    }

    /// The index stores one row per merchant, but a row is not always one name:
    /// `"Couche-Tard / Circle K"` is two brands, `"TTC (Toronto Transit Commission)"` is an
    /// acronym plus its expansion, and `"A&W Canada"` is a brand plus a country nobody puts on
    /// a sign. Each of those has to be reachable from what MapKit actually returns.
    static func aliases(for name: String) -> [Alias] {
        var result: [Alias] = []

        for part in name.components(separatedBy: "/") {
            let outside = part.replacingOccurrences(of: "\\([^)]*\\)", with: " ",
                                                    options: .regularExpression)
            let primary = tokens(outside)
            guard !primary.isEmpty else { continue }
            result.append(Alias(tokens: primary, isDerived: name.contains("/")))

            // A trailing country word: "A&W Canada", "Bell Canada", "VIA Rail Canada". Every
            // storefront drops it.
            if primary.count > 1, primary.last == "canada" {
                result.append(Alias(tokens: Array(primary.dropLast()), isDerived: true))
            }

            // A parenthetical is kept ONLY when it is a lone acronym — "(PSN)", "(ETS)". The
            // expansions are not aliases: "STM (Montréal)" and "OC Transpo (Ottawa)" would
            // otherwise register the whole city as a transit merchant.
            if let range = part.range(of: "\\([^)]*\\)", options: .regularExpression) {
                let inside = String(part[range]).trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                let insideTokens = tokens(inside)
                if insideTokens.count == 1,
                   inside == inside.uppercased(),
                   inside.rangeOfCharacter(from: .lowercaseLetters) == nil {
                    result.append(Alias(tokens: insideTokens, isDerived: true))
                }
            }
        }
        return result
    }

    // MARK: - Matching

    /// A name the index author wrote may match anywhere inside the place name, so "Metro" is
    /// found in "Metro Plus Ottawa".
    ///
    /// A *derived* one-word form must match the place name entirely. Without that asymmetry,
    /// dropping the country from "Bell Canada" would leave a bare "bell" that recognises every
    /// Taco Bell in the country as a hydro account. Multi-word derived forms ("circle k",
    /// "reno depot") carry enough signal to be found inside a longer name safely.
    static func matches(_ alias: Alias, in haystack: [String]) -> Bool {
        if alias.isDerived && alias.tokens.count == 1 { return haystack == alias.tokens }
        return contains(haystack, alias.tokens)
    }

    /// Lowercased, diacritic-folded alphanumeric words.
    ///
    /// Tokenising rather than substring-matching is the whole safety margin. The index holds
    /// names as short as "IGA", "Esso" and "Metro"; on raw substrings those match "Rigatoni's",
    /// "Essential Oils" and "Metropolitan Hotel", and recognition stops being evidence of
    /// anything.
    static func tokens(_ value: String) -> [String] {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Whether `needle` appears as a contiguous run inside `haystack`.
    private static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count)
        where Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }
}
