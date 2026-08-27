import Foundation

public enum SeedLoaderError: Error, Equatable {
    case resourceMissing(String)
    case unsupportedCatalogueVersion(String)
}

public enum SeedLoader {
    /// The only catalogueVersion MAJOR this build understands. Bump alongside a deliberate,
    /// reviewed breaking-shape change — see contracts/CHANGELOG.md. Bumped 1 → 2 for the
    /// 2026-08-26 multi-market shape change (Money-shaped fee/credit values, `market`/
    /// `billingCurrency`, `spendNative` replacing `spendCad`, `calendarQuarter`).
    static let supportedCatalogueMajorVersion = 2

    /// candidate-catalogue.json became a list of cardIds in 2.0 (was full card definitions).
    static let supportedCandidateCatalogueMajorVersion = 2

    public static func loadCatalogue() throws -> Catalogue {
        let catalogue: Catalogue = try load("card-catalogue")
        try validate(catalogueVersion: catalogue.catalogueVersion)
        return catalogue
    }

    /// Which catalogue products are researched acquisition candidates.
    ///
    /// This returns IDS, not card definitions. Until 2026-08-24 the file carried full duplicate
    /// definitions, and they had already drifted from the same cards elsewhere — identical rates
    /// under different ruleIds, and two different ids for Simplii. Rules and ledgers key on those
    /// ids, so the drift was not cosmetic. A card defined in one place cannot disagree with itself.
    ///
    /// Candidates staying unowned is now enforced where it belongs — against `ownedCardIds` in
    /// AcquisitionAnalyzer — rather than by keeping a second copy of the card.
    public static func loadCandidateCatalogue() throws -> CandidateSet {
        let candidates: CandidateSet = try load("candidate-catalogue")
        try validate(candidateCatalogueVersion: candidates.candidateCatalogueVersion)
        return candidates
    }

    public static func loadOwnerState() throws -> OwnerState {
        try load("owner-state")
    }

    public static func loadBenefitsCatalogue() throws -> BenefitsCatalogue {
        try load("benefits-catalogue")
    }

    /// Catalogue-level default valuations. Owner state overrides any entry; a program present
    /// here is scoreable the moment a card declares it, with no owner-state edit.
    ///
    /// Not every catalogue programId appears — see contracts/programs.json's `_gap`. Callers must
    /// treat a missing key as "no valuation", never as zero.
    public static func loadPrograms() throws -> ProgramCatalogue {
        try load("programs")
    }

    /// Which published contract release this build shipped.
    ///
    /// Deliberately does NOT verify that the bundled bytes hash to `digest`. That check belongs
    /// to `scripts/release-catalogue.sh --check` in CI, and at this phase the stamp and the rules
    /// ship in the same signed bundle — if one is corrupt, both are. It becomes worth paying for
    /// at runtime when the catalogue starts arriving over the network.
    public static func loadContractRelease() throws -> ContractRelease {
        try load("RELEASE")
    }

    /// The catalogue's default valuations, decoded once and reused.
    ///
    /// Traps rather than falling back to `[:]`. programs.json is a resource compiled into the
    /// bundle and gated by ContractsSyncTests and SeedLoaderTests, so it cannot be unreadable at
    /// runtime without the build itself being broken — and an empty fallback would silently
    /// unvalue every program the owner has not declared, which is the exact failure this
    /// contract exists to prevent. Matches the house response to misconfigured catalogue data,
    /// `RecommendationEngine`'s `precondition(!scores.isEmpty)`.
    public static let programValuationDefaults: [String: ProgramValuation] = {
        do { return try loadPrograms().defaults }
        catch { preconditionFailure("contracts/programs.json is unreadable: \(error)") }
    }()

    /// catalogueVersion is "MAJOR.MINOR" (contracts/schema/card-catalogue.schema.json). Refuses to
    /// load a MAJOR this build doesn't recognize rather than silently misinterpreting a breaking
    /// shape change.
    static func validate(catalogueVersion: String) throws {
        guard let majorComponent = catalogueVersion.split(separator: ".", maxSplits: 1).first,
              let major = Int(majorComponent),
              major == supportedCatalogueMajorVersion else {
            throw SeedLoaderError.unsupportedCatalogueVersion(catalogueVersion)
        }
    }

    static func validate(candidateCatalogueVersion: String) throws {
        guard let majorComponent = candidateCatalogueVersion.split(separator: ".", maxSplits: 1).first,
              let major = Int(majorComponent),
              major == supportedCandidateCatalogueMajorVersion else {
            throw SeedLoaderError.unsupportedCatalogueVersion(candidateCatalogueVersion)
        }
    }

    private static func load<T: Decodable>(_ name: String) throws -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw SeedLoaderError.resourceMissing(name)
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
