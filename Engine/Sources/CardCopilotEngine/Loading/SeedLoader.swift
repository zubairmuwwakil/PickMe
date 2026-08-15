import Foundation

public enum SeedLoaderError: Error { case resourceMissing(String) }

public enum SeedLoader {
    public static func loadCatalogue() throws -> Catalogue {
        try load("card-catalogue")
    }

    public static func loadOwnerState() throws -> OwnerState {
        try load("owner-state")
    }

    private static func load<T: Decodable>(_ name: String) throws -> T {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            throw SeedLoaderError.resourceMissing(name)
        }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
}
