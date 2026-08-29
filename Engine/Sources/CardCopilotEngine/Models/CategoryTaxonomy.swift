import Foundation

/// The canonical vocabulary shared by purchase contexts, catalogue predicates, and UI entry
/// points. Display labels are allowed to be friendly; values sent to the engine are not.
///
/// This is intentionally a small boundary normalizer rather than a permissive fuzzy matcher.
/// Known aliases are collapsed to the catalogue's exact ids, while unknown values are preserved
/// so a new catalogue category is not silently misclassified.
public enum CategoryTaxonomy {

    /// Converts a display/input alias to the catalogue's canonical category id.
    public static func canonicalID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        switch compactKey(trimmed) {
        case "dining", "restaurant", "restaurants": return "dining"
        case "fooddelivery": return "foodDelivery"
        case "grocery", "groceries": return "grocery"
        case "gas", "gasstation", "fuel", "fuelstation": return "gasStation"
        case "drugstore", "drugstores", "pharmacy": return "drugStore"
        case "transit", "publictransport": return "transit"
        case "travel", "flight", "flights", "airline", "airlines": return "travel"
        case "lodging", "hotel", "hotels": return "lodging"
        case "carrental", "rentalcar": return "carRental"
        case "streaming": return "streaming"
        case "digitalmedia": return "digitalMedia"
        case "entertainment": return "entertainment"
        case "evcharging", "evcharger", "evchargers": return "evCharging"
        case "householdutilities", "utilities": return "householdUtilities"
        case "memberships", "membership": return "memberships"
        case "recurring", "recurringbills", "bills": return "recurring"
        case "ctfamily": return "ctFamily"
        case "wholesaleclub": return "wholesaleClub"
        case "marriottdirect": return "marriottDirect"
        case "other", "general", "generalmerchandise": return "other"
        case "fitness", "gym": return "fitness"
        default: return trimmed
        }
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
