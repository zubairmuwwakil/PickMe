import Foundation

public enum SeedLoaderError: Error, Equatable {
    case resourceMissing(String)
    case unsupportedCatalogueVersion(String)
}

public enum SeedLoader {
    /// The only catalogueVersion MAJOR this build understands. Bump alongside a deliberate,
    /// reviewed breaking-shape change — see contracts/CHANGELOG.md.
    static let supportedCatalogueMajorVersion = 1

    public static func loadCatalogue() throws -> Catalogue {
        let catalogue: Catalogue = try load("card-catalogue")
        try validate(catalogueVersion: catalogue.catalogueVersion)
        return catalogue
    }

    public static func loadOwnerState() throws -> OwnerState {
        try load("owner-state")
    }

    public static func loadBenefitsCatalogue() throws -> BenefitsCatalogue {
        try load("benefits-catalogue")
    }

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

    private static func load<T: Decodable>(_ name: String) throws -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw SeedLoaderError.resourceMissing(name)
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
