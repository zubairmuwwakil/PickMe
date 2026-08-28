import Foundation

/// Canonical category of a Canadian recurring obligation or bill payee.
public enum BillCategory: String, CaseIterable, Codable, Sendable {
    case utilitiesWater = "utilities_water"
    case utilitiesHydro = "utilities_hydro"
    case utilitiesGas = "utilities_gas"
    case propertyTax = "property_tax"
    case telecom = "telecom"
    case insurance = "insurance"
    case rent = "rent"
    case tuition = "tuition"
    case householdExpenses = "household_expenses"
    case other = "other"

    public var displayName: String {
        switch self {
        case .utilitiesWater: return "Household Expenses > Utilities (Water)"
        case .utilitiesHydro: return "Household Expenses > Utilities (Hydro / Electric)"
        case .utilitiesGas: return "Household Expenses > Utilities (Gas)"
        case .propertyTax: return "Municipal Taxes > Property Tax"
        case .telecom: return "Telecom > Internet / Mobile"
        case .insurance: return "Financial > Insurance"
        case .rent: return "Housing > Rent"
        case .tuition: return "Education > Tuition"
        case .householdExpenses: return "Household Expenses"
        case .other: return "Other Bill"
        }
    }

    public var iconSymbol: String {
        switch self {
        case .utilitiesWater: return "drop.fill"
        case .utilitiesHydro: return "bolt.fill"
        case .utilitiesGas: return "flame.fill"
        case .propertyTax: return "building.columns.fill"
        case .telecom: return "wifi"
        case .insurance: return "shield.lefthalf.filled"
        case .rent: return "house.fill"
        case .tuition: return "graduationcap.fill"
        case .householdExpenses: return "house.and.flag.fill"
        case .other: return "doc.text.fill"
        }
    }

    /// Automatically suggests a category based on the standardized payee name string.
    public static func detect(from payeeName: String) -> BillCategory {
        let lower = payeeName.lowercased()
        if lower.contains("water") || lower.contains("durham water") || lower.contains("region of durham") {
            return .utilitiesWater
        } else if lower.contains("hydro") || lower.contains("electric") || lower.contains("alectra") || lower.contains("toronto hydro") {
            return .utilitiesHydro
        } else if lower.contains("gas") || lower.contains("enbridge") {
            return .utilitiesGas
        } else if lower.contains("tax") || lower.contains("property") || lower.contains("mun of") || lower.contains("city of") {
            return .propertyTax
        } else if lower.contains("bell") || lower.contains("rogers") || lower.contains("telus") || lower.contains("fido") || lower.contains("koodo") {
            return .telecom
        } else if lower.contains("insurance") || lower.contains("desjardins") || lower.contains("intact") || lower.contains("aviva") {
            return .insurance
        } else if lower.contains("rent") || lower.contains("prop") || lower.contains("realty") {
            return .rent
        } else if lower.contains("univ") || lower.contains("college") || lower.contains("tuition") {
            return .tuition
        }
        return .householdExpenses
    }
}

/// One Canadian bill payee configured by the user.
public struct BillPayee: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let payeeName: String
    public let accountNumber: String
    public let nickname: String?
    public let category: BillCategory
    public let estimatedMonthlyCad: Double?
    public let preferredIntermediaryId: String?

    public init(
        id: String = UUID().uuidString,
        payeeName: String,
        accountNumber: String,
        nickname: String? = nil,
        category: BillCategory? = nil,
        estimatedMonthlyCad: Double? = 150.0,
        preferredIntermediaryId: String? = nil
    ) {
        self.id = id
        self.payeeName = payeeName
        self.accountNumber = accountNumber
        self.nickname = nickname
        self.category = category ?? BillCategory.detect(from: payeeName)
        self.estimatedMonthlyCad = estimatedMonthlyCad
        self.preferredIntermediaryId = preferredIntermediaryId
    }

    public var effectiveLabel: String {
        nickname?.isEmpty == false ? nickname! : payeeName
    }
}
