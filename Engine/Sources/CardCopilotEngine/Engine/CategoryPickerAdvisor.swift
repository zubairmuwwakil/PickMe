import Foundation

/// Powers the "which card do I use for X?" screen: a runtime-derived set of category pills,
/// each answered with amount bands rather than a single hardcoded verdict.
///
/// Nothing here is a fixed list. The card catalogue keeps growing — every accelerator category,
/// every cap value, every card name is read from the loaded `Catalogue`/`OwnerState` at call
/// time. A category the catalogue's accelerators name but nobody accounted for is caught by
/// the drift test in `CategoryPickerAdvisorTests`, not discovered by a user seeing a raw
/// identifier or a missing pill.
public enum CategoryPickerAdvisor {

    /// One entry in a hand-maintained set, paired with why it's there. Keeping the reason next
    /// to the entry is the point: these lists must stay short enough to eyeball, and every
    /// addition has to justify itself in writing.
    public struct CuratedEntry: Equatable, Sendable {
        public let category: String
        public let reason: String
    }

    /// Pills that exist for a reason other than an accelerator predicate naming them.
    public static let curatedCategories: [CuratedEntry] = [
        CuratedEntry(category: "other",
                     reason: "The catch-all for unaccelerated spend — every wallet needs an "
                            + "answer for 'nothing special applies here,' even though no "
                            + "earnRule predicate names it."),
        CuratedEntry(category: "wholesaleClub",
                     reason: "Costco's winner is decided by its Mastercard-only acceptance "
                            + "gate, not an accelerator — no earnRule predicate lists this "
                            + "category."),
    ]

    /// Predicate-side vocabulary that names a rule condition, not a real spending category.
    /// Never a pill: no receipt or statement is ever coded this way.
    public static let excludedCategories: [CuratedEntry] = [
        CuratedEntry(category: "ownerSelectedTangerineCategory",
                     reason: "Placeholder for whichever categories the owner picked on "
                            + "Tangerine — a rule condition RuleMatcher resolves against the "
                            + "owner's selections, not a category any statement shows."),
    ]

    /// Every canonical category id named by an accelerator predicate in the loaded catalogue —
    /// the normalized vocabulary the drift test checks pill coverage against.
    public static func acceleratedVocabulary(catalogue: Catalogue) -> Set<String> {
        Set(catalogue.cards.flatMap(\.earnRules)
            .compactMap(\.predicate.categories)
            .flatMap { $0 }
            .map(CategoryTaxonomy.canonicalID))
    }

    /// Every category pill the picker screen renders: the catalogue's accelerator vocabulary,
    /// plus the curated set, minus the exclusion set. Recomputed from the catalogue every call
    /// — nothing about this list survives across a catalogue reload.
    public static func derivedCategories(catalogue: Catalogue) -> [String] {
        let curated = Set(curatedCategories.map(\.category))
        let excluded = Set(excludedCategories.map(\.category))
        return acceleratedVocabulary(catalogue: catalogue).union(curated).subtracting(excluded).sorted()
    }

    // MARK: - Labels

    /// Overrides for categories whose catalogue id would otherwise read as a raw-ish token even
    /// after the generic humanizer runs (an acronym like "evCharging" camel-splits to "Ev
    /// charging"), or that need a name distinct from any single bucket's label. Kept short and
    /// reasoned — the bucket path below (`enrichedTemplate`) is the first line of defense
    /// against raw identifiers, and most categories never reach this table at all.
    static let curatedLabels: [String: String] = [
        "ctFamily": "Canadian Tire family",
        "marriottDirect": "Marriott direct",
        "other": "General merchandise",
        "evCharging": "EV charging",
    ]

    /// Human label for a category id. A `SpendDistribution` bucket's label wins when one
    /// exists — it's hand-written and specific ("Restaurants & coffee" beats "Dining"); the
    /// curated table above covers ids with no bucket that wouldn't camel-split cleanly;
    /// anything left over falls through to `humanize`, so a brand-new catalogue category still
    /// reads as words instead of a token like `householdUtilities`.
    public static func label(for category: String,
                             distribution: SpendDistribution = .placeholderCanadianHousehold) -> String {
        let canonicalCategory = CategoryTaxonomy.canonicalID(category)
        if let bucket = matchingBucket(for: canonicalCategory, distribution: distribution) {
            return bucket.label
        }
        if let curated = curatedLabels[canonicalCategory] { return curated }
        return humanize(canonicalCategory)
    }

    /// camelCase -> "Camel case". The fallback of last resort: never returns its input
    /// unchanged for anything but an already-lowercase single word, so a category neither
    /// bucketed nor curated still reads as a sentence rather than a raw identifier.
    static func humanize(_ category: String) -> String {
        guard !category.isEmpty else { return category }
        var spaced = ""
        for character in category {
            if character.isUppercase, !spaced.isEmpty { spaced.append(" ") }
            spaced.append(character)
        }
        return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
    }

    // MARK: - Enrichment (SpendDistribution as a lookup table, not a source of truth)

    /// The `PurchaseContext` template a category's bands should be swept over (only
    /// `amountCad` varies band to band). A bucket's context carries facts a bare category
    /// can't: the MCC that decides MBNA's 5x, Costco's Mastercard-only door, the currency that
    /// triggers an FX fee. A category with no bucket gets a minimal context built from nothing
    /// but the category itself.
    ///
    /// `other` deliberately never matches a bucket even though two buckets carry that category
    /// ("Foreign currency (USD online)" and "Everything else") — picking either one would
    /// misrepresent the catch-all pill as one narrow case of itself, so it gets the same
    /// minimal, category-only context as a category with no bucket at all.
    public static func enrichedTemplate(for category: String,
                                        distribution: SpendDistribution = .placeholderCanadianHousehold)
    -> PurchaseContext {
        let canonicalCategory = CategoryTaxonomy.canonicalID(category)
        if let bucket = matchingBucket(for: canonicalCategory, distribution: distribution) {
            return bucket.context
        }
        return PurchaseContext(amountCad: 1, category: canonicalCategory)
    }

    private static func matchingBucket(for category: String,
                                       distribution: SpendDistribution) -> SpendDistribution.Bucket? {
        guard category != "other" else { return nil }
        return distribution.buckets.first { $0.context.category == category }
    }

    // MARK: - Amount bands

    /// One amount range's answer. `upperBoundCad == nil` means open-ended ("over $X"). Bands
    /// are contiguous and non-overlapping: band *n*'s `upperBoundCad` equals band *n+1*'s
    /// `lowerBoundCad`.
    public struct AmountBand: Equatable, Sendable {
        public let lowerBoundCad: Double
        public let upperBoundCad: Double?
        public let cardId: String
        public let recommendation: Recommendation
    }

    /// Selects the band that contains a concrete purchase amount. At an exact boundary the
    /// following band wins, matching the half-open ranges rendered by CategoryBandListView.
    public static func band(containing amountCad: Double,
                            in bands: [AmountBand]) -> AmountBand? {
        let amount = max(0, amountCad)
        return bands.first { band in
            amount >= band.lowerBoundCad
                && (band.upperBoundCad == nil || amount < band.upperBoundCad!)
        } ?? bands.last
    }

    /// Every amount band for one category: the amount ranges across which the engine's answer
    /// — `recommend(_:asOf:).winner`, never `allCandidates.first` — stays on the same card.
    /// `winner` is deliberate: it already applies the owner's switch threshold against their
    /// default card, which is exactly the "what do I pull out of my wallet" question this
    /// screen answers.
    ///
    /// A category whose answer never changes with amount returns exactly one band spanning
    /// `0...nil` — the caller renders that with no band framing at all.
    public static func bands(for category: String, catalogue: Catalogue, ownerState: OwnerState,
                             distribution: SpendDistribution = .placeholderCanadianHousehold,
                             asOf: String) -> [AmountBand] {
        let engine = RecommendationEngine(catalogue: catalogue, ownerState: ownerState)
        let canonicalCategory = CategoryTaxonomy.canonicalID(category)
        let template = enrichedTemplate(for: canonicalCategory, distribution: distribution)

        func recommendation(atCents cents: Int) -> Recommendation? {
            var context = template
            context.amountCad = Double(cents) / 100
            return engine.recommendOrNil(context, asOf: asOf)
        }

        let sweepMaxCad = sweepCeilingCad(catalogue: catalogue)
        let boundaryCents = detectBoundaryCents(recommendation: recommendation, sweepMaxCad: sweepMaxCad)

        guard !boundaryCents.isEmpty else {
            // Constant across the whole sweep — any point proves it. $1 keeps the evaluated
            // context sane without implying a "typical" amount that isn't real.
            guard let rec = recommendation(atCents: 100) else { return [] }
            return [AmountBand(lowerBoundCad: 0, upperBoundCad: nil,
                               cardId: rec.winner.cardId, recommendation: rec)]
        }

        var result: [AmountBand] = []
        var lowerCents = 0
        for boundaryCentsValue in boundaryCents {
            let representativeCents = lowerCents + max(1, (boundaryCentsValue - lowerCents) / 2)
            guard let rec = recommendation(atCents: representativeCents) else { continue }
            result.append(AmountBand(lowerBoundCad: Double(lowerCents) / 100,
                                     upperBoundCad: Double(boundaryCentsValue) / 100,
                                     cardId: rec.winner.cardId, recommendation: rec))
            lowerCents = boundaryCentsValue
        }
        // The sweep ran all the way to sweepMaxCad without finding another flip, so any point
        // at or past the last boundary — sweepMaxCad itself is convenient — represents the
        // final, open-ended band.
        let finalCents = max(lowerCents + 1, Int((sweepMaxCad * 100).rounded()))
        guard let finalRec = recommendation(atCents: finalCents) else { return result }
        result.append(AmountBand(lowerBoundCad: Double(lowerCents) / 100, upperBoundCad: nil,
                                 cardId: finalRec.winner.cardId, recommendation: finalRec))
        return result
    }

    /// Coarse-to-fine boundary search. A geometric scan — spanning comfortably from a single
    /// cent to the largest cap in the catalogue in a few hundred steps — finds every bracket
    /// where the winning card genuinely changes; each bracket is then bisected down to the
    /// cent, since a real purchase amount has no finer resolution than that.
    static func detectBoundaryCents(recommendation: (Int) -> Recommendation?, sweepMaxCad: Double) -> [Int] {
        let sweepMaxCents = max(Int((sweepMaxCad * 100).rounded()), 100)
        let minCents = 1
        let sampleCount = 600
        let ratio = Double(sweepMaxCents) / Double(minCents)

        var samples: [(cents: Int, cardId: String)] = []
        samples.reserveCapacity(sampleCount + 1)
        for i in 0...sampleCount {
            let t = Double(i) / Double(sampleCount)
            let cents = max(minCents, Int((Double(minCents) * pow(ratio, t)).rounded()))
            guard let cardId = recommendation(cents)?.winner.cardId else { continue }
            samples.append((cents, cardId))
        }

        guard !samples.isEmpty else { return [] }

        var boundaries: [Int] = []
        for i in 1..<samples.count
        where !isSameRegime(cardId: samples[i - 1].cardId, atCents: samples[i].cents,
                            recommendation: recommendation) {
            let boundary = binarySearchBoundaryCents(lowCents: samples[i - 1].cents,
                                                      lowCardId: samples[i - 1].cardId,
                                                      highCents: samples[i].cents,
                                                      recommendation: recommendation)
            boundaries.append(boundary)
        }
        // The coarse scan's overlapping brackets can rediscover the same crossing twice;
        // collapse adjacent duplicates once sorted.
        return boundaries.sorted().reduce(into: [Int]()) { acc, next in
            if acc.last != next { acc.append(next) }
        }
    }

    /// Smallest cent amount in `(lowCents, highCents]` where the winner genuinely differs from
    /// `lowCardId`, found by bisection. The winner is a step function of amount, so this
    /// converges on the exact cent a real purchase would cross.
    static func binarySearchBoundaryCents(lowCents: Int, lowCardId: String, highCents: Int,
                                          recommendation: (Int) -> Recommendation?) -> Int {
        var lo = lowCents
        var hi = highCents
        while hi - lo > 1 {
            let mid = lo + (hi - lo) / 2
            if isSameRegime(cardId: lowCardId, atCents: mid, recommendation: recommendation) {
                lo = mid
            } else {
                hi = mid
            }
        }
        return hi
    }

    /// Floating-point noise tolerance, not a financial one. Two cards that earn the same rate
    /// through different formulas (points-per-dollar times cents-per-point vs. a flat cashback
    /// rate) don't always reduce to bit-identical `Double`s — Scorer's ranking can flip which
    /// one it calls ahead by a single unit in the last place as the amount moves by a cent,
    /// even though the two are economically tied to well beyond any real precision. Chasing
    /// that with a naive cardId-equality check turns one genuine tie into dozens of meaningless
    /// micro-bands. `1e-6` CAD is many orders of magnitude below both that noise floor (~1e-16)
    /// and the smallest real difference any sane rate spread produces at any real amount, so it
    /// only ever swallows noise, never a real crossing.
    static let regimeToleranceCad = 0.000_001

    /// Whether `cardId` is still economically indistinguishable from the actual winner at
    /// `cents` — either it *is* the winner, or its own score there sits within
    /// `regimeToleranceCad` of the winner's, meaning the "change" is a coincidental exact-tie
    /// artifact rather than one card genuinely earning more than the other.
    static func isSameRegime(cardId: String, atCents cents: Int,
                             recommendation: (Int) -> Recommendation?) -> Bool {
        guard let rec = recommendation(cents) else { return false }
        if rec.winner.cardId == cardId { return true }
        guard let candidate = rec.allCandidates.first(where: { $0.cardId == cardId }),
              !candidate.excluded else { return false }
        return abs(candidate.netValueCad - rec.winner.netValueCad) < regimeToleranceCad
    }

    /// How far past the catalogue's own numbers a sweep needs to run to be confident it has
    /// seen every regime change. Never a fixed dollar figure: the largest cap or spend
    /// threshold actually present in the loaded catalogue sets the scale, with margin, so a
    /// future catalogue with bigger caps sweeps further automatically.
    static func sweepCeilingCad(catalogue: Catalogue) -> Double {
        let largestCapLimit = catalogue.cards.flatMap(\.caps).map(\.limit).max() ?? 0
        return max(largestCapLimit, 1_000) * 1.5
    }
}
