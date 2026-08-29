import Foundation

/// Canadian Sales Tax Presets and Calculation Helper for PickMe / CardCopilot
public struct CanadianTaxPreset: Identifiable, Hashable, Sendable {
    public let id: String
    public let provinceCode: String
    public let name: String
    public let ratePct: Double
    public let shortLabel: String

    public init(id: String, provinceCode: String, name: String, ratePct: Double, shortLabel: String) {
        self.id = id
        self.provinceCode = provinceCode
        self.name = name
        self.ratePct = ratePct
        self.shortLabel = shortLabel
    }
}

public enum SalesTaxHelper {
    public static let presets: [CanadianTaxPreset] = [
        CanadianTaxPreset(id: "on", provinceCode: "ON", name: "Ontario", ratePct: 13.0, shortLabel: "+13% ON"),
        CanadianTaxPreset(id: "bc", provinceCode: "BC", name: "British Columbia", ratePct: 12.0, shortLabel: "+12% BC"),
        CanadianTaxPreset(id: "ab", provinceCode: "AB", name: "Alberta / GST", ratePct: 5.0, shortLabel: "+5% AB"),
        CanadianTaxPreset(id: "qc", provinceCode: "QC", name: "Quebec", ratePct: 14.975, shortLabel: "+15% QC"),
        CanadianTaxPreset(id: "atl", provinceCode: "ATL", name: "Atlantic", ratePct: 15.0, shortLabel: "+15% ATL"),
    ]

    /// Calculates total amount including sales tax from a pre-tax base amount
    public static func addTax(base: Double, ratePct: Double) -> Double {
        guard base > 0, ratePct > 0 else { return base }
        let total = base * (1.0 + (ratePct / 100.0))
        return (total * 100.0).rounded() / 100.0
    }

    /// Extracts the pre-tax base amount from a tax-inclusive total
    public static func extractBase(total: Double, ratePct: Double) -> Double {
        guard total > 0, ratePct > 0 else { return total }
        let base = total / (1.0 + (ratePct / 100.0))
        return (base * 100.0).rounded() / 100.0
    }
}
