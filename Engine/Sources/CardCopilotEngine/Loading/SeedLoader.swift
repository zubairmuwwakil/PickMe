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

    /// First standalone application-requirements contract. Kept independent because issuer
    /// qualification facts change on a different cadence from reward arithmetic.
    static let supportedApplicationRequirementsMajorVersion = 1

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

    public static func loadApplicationRequirements() throws -> ApplicationRequirementCatalogue {
        let requirements: ApplicationRequirementCatalogue = try load("application-requirements")
        try validate(applicationRequirementsVersion: requirements.applicationRequirementsVersion)
        return requirements
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

    /// The owner-condition registry: every `ownerConditions` id the catalogue may reference, how
    /// it is answered, and the English source prompt to ask it with.
    ///
    /// Adding a condition to the catalogue without an entry here leaves a rate the owner can never
    /// unlock — `CatalogueIntegrityTests` and the CI gate refuse it.
    public static func loadOwnerConditions() throws -> OwnerConditionRegistry {
        try load("owner-conditions")
    }

    /// Canonical purchase categories, aliases, labels, and predicate-only exclusions.
    public static func loadPurchaseCategories() throws -> PurchaseCategoryRegistry {
        try load("purchase-categories")
    }

    /// Decoded once and reused by every category boundary. An unreadable registry is a broken
    /// build, not a reason to fall back to a second handwritten vocabulary.
    public static let purchaseCategories: PurchaseCategoryRegistry = {
        do { return try loadPurchaseCategories() }
        catch { preconditionFailure("contracts/purchase-categories.json is unreadable: \(error)") }
    }()

    /// Decoded once and reused. Traps rather than falling back to `[:]`, for the same reason
    /// `programValuationDefaults` does: an empty fallback would make every condition unanswerable
    /// and every conditional rate silently unreachable, which is the exact failure this registry
    /// exists to prevent.
    public static let ownerConditions: [String: OwnerCondition] = {
        do { return try loadOwnerConditions().conditions }
        catch { preconditionFailure("contracts/owner-conditions.json is unreadable: \(error)") }
    }()

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

    static func validate(applicationRequirementsVersion: String) throws {
        guard let majorComponent = applicationRequirementsVersion.split(separator: ".", maxSplits: 1).first,
              let major = Int(majorComponent),
              major == supportedApplicationRequirementsMajorVersion else {
            throw SeedLoaderError.unsupportedCatalogueVersion(applicationRequirementsVersion)
        }
    }

    private static func load<T: Decodable>(_ name: String) throws -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw SeedLoaderError.resourceMissing(name)
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
