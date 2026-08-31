import Foundation

/// One canonical purchase category or rule-only category predicate.
public struct PurchaseCategoryDefinition: Codable, Equatable, Sendable {
    public var id: String
    public var displayName: String
    public var aliases: [String]

    public init(id: String, displayName: String, aliases: [String] = []) {
        self.id = id
        self.displayName = displayName
        self.aliases = aliases
    }
}

/// Published category vocabulary from `contracts/purchase-categories.json`.
///
/// `categories` are valid persisted merchant classifications. `ruleSideCategories` are tokens
/// the card catalogue may match, but a purchase or merchant row must never store them as its
/// classification.
public struct PurchaseCategoryRegistry: Codable, Equatable, Sendable {
    public var taxonomyVersion: String
    public var categories: [PurchaseCategoryDefinition]
    public var ruleSideCategories: [PurchaseCategoryDefinition]

    public init(taxonomyVersion: String = "1.0",
                categories: [PurchaseCategoryDefinition] = [],
                ruleSideCategories: [PurchaseCategoryDefinition] = []) {
        self.taxonomyVersion = taxonomyVersion
        self.categories = categories
        self.ruleSideCategories = ruleSideCategories
    }
}
