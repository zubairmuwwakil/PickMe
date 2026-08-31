import Foundation

/// The canonical vocabulary shared by purchase contexts, catalogue predicates, and UI entry
/// points. Display labels are allowed to be friendly; values sent to the engine are not.
///
/// This is intentionally a small boundary normalizer rather than a permissive fuzzy matcher.
/// Known aliases are collapsed to the catalogue's exact ids, while unknown values are preserved
/// so a new catalogue category is not silently misclassified.
public enum CategoryTaxonomy {

    /// Real purchase/merchant categories. Predicate-only dimensions such as `recurring` and
    /// `ownerSelectedCategory` are deliberately excluded: no database row should claim that a
    /// merchant *is* one of those conditions.
    public static let purchaseCategoryIDs = Set(registry.categories.map(\.id))

    /// Tokens understood by catalogue matching that are not valid merchant classifications.
    public static let ruleSideCategoryIDs = Set(registry.ruleSideCategories.map(\.id))

    private static let registry = SeedLoader.purchaseCategories

    private static let definitionsByID: [String: PurchaseCategoryDefinition] = {
        let definitions = registry.categories + registry.ruleSideCategories
        let pairs = definitions.map { ($0.id, $0) }
        let result = Dictionary(pairs, uniquingKeysWith: { first, duplicate in
            preconditionFailure("Duplicate category id in purchase-categories.json: \(duplicate.id)")
        })
        precondition(result.count == definitions.count,
                     "purchase-categories.json contains duplicate ids")
        return result
    }()

    private static let canonicalIDByCompactKey: [String: String] = {
        var result: [String: String] = [:]
        for definition in registry.categories + registry.ruleSideCategories {
            for raw in [definition.id] + definition.aliases {
                let key = compactKey(raw)
                if let existing = result[key] {
                    precondition(existing == definition.id,
                                 "Category alias '\(raw)' is ambiguous: \(existing), \(definition.id)")
                }
                result[key] = definition.id
            }
        }
        return result
    }()

    /// Converts a display/input alias to the catalogue's canonical category id.
    public static func canonicalID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        return canonicalIDByCompactKey[compactKey(trimmed)] ?? trimmed
    }

    /// Canonicalizes and validates a value intended for a persisted purchase/merchant field.
    public static func canonicalPurchaseID(_ raw: String) -> String? {
        let canonical = canonicalID(raw)
        return purchaseCategoryIDs.contains(canonical) ? canonical : nil
    }

    /// Shared human-readable fallback for every non-visual surface.
    public static func displayName(for raw: String) -> String {
        let category = canonicalID(raw)
        if let displayName = definitionsByID[category]?.displayName { return displayName }
        guard !category.isEmpty else { return category }
        var spaced = ""
        for character in category {
            if character.isUppercase, !spaced.isEmpty { spaced.append(" ") }
            spaced.append(character)
        }
        return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
    }

    private static func compactKey(_ raw: String) -> String {
        raw.folding(options: [.diacriticInsensitive, .caseInsensitive],
                    locale: Locale(identifier: "en_CA"))
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init)
            .joined()
            .lowercased()
    }
}
