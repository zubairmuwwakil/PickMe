import Foundation

/// Identifies which pre-indexed merchant a place name or payment descriptor refers to.
///
/// Distinct from `CanadianMerchantPreIndex.search`, which serves a human typing into a field and
/// may return many loose candidates. Recognition answers a machine's question — "which merchant
/// IS this?" — returns at most one, and returns nothing rather than a guess, because its answer
/// decides whether the app interrupts someone.
public enum MerchantRecognizer {

    /// The pre-indexed merchant this string refers to, or nil when none is certain.
    ///
    /// Ties break toward the longer match, so "Walmart Supercentre" (grocery, 5411) wins over
    /// the bare "Walmart" row (other, 5310) rather than the other way round.
    public static func recognise(_ displayName: String) -> PreIndexedMerchant? {
        let haystack = tokens(displayName)
        guard !haystack.isEmpty else { return nil }

        var best: (merchant: PreIndexedMerchant, length: Int)?
        for entry in aliasIndex {
            guard contains(haystack, entry.needle) else { continue }
            if best == nil || entry.needle.count > best!.length {
                best = (entry.merchant, entry.needle.count)
            }
        }
        return best?.merchant
    }

    /// Every match key of every indexed merchant, tokenised once.
    ///
    /// The needles come from `contracts/merchant-pack.json`, which is the only place that knows
    /// what a brand looks like on a *statement*. Until 2026-09-01 this file derived its own
    /// aliases from the display name with a regex — splitting on "/", dropping a trailing
    /// "canada", keeping lone parenthetical acronyms — which could reach "Circle K" from
    /// "Couche-Tard / Circle K" but could never reach "AMZN MKTP CA" from "Amazon.ca". No amount
    /// of derivation gets from a storefront name to an acquirer's billing string; only a curator
    /// can write that down, and the pack is where they already had.
    ///
    /// Built once rather than per call because the caller is a geofence wake: `resolve` runs this
    /// for every POI in the arrived-at area, and rebuilding ~250 needles on each of those is
    /// exactly the kind of background cost this subsystem is otherwise careful to avoid.
    private static let aliasIndex: [(needle: [String], merchant: PreIndexedMerchant)] =
        CanadianMerchantPreIndex.all.flatMap { merchant in
            merchant.matchKeys.map { (needle: tokens($0), merchant: merchant) }
        }
        .filter { !$0.needle.isEmpty }

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
