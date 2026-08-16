import Foundation
import CardCopilotEngine

/// Copy rules for every benefits surface (spec B2): facts from the certificate, stated as
/// facts — "per certificate", never "you're covered".
enum BenefitsFormatting {
    static let certificateFooter =
        "Coverage depends on certificate conditions — verify before relying on it."

    static func kindDisplayName(_ kind: String) -> String {
        switch BenefitKind(rawValue: kind) {
        case .purchaseProtection: return "Purchase protection"
        case .extendedWarranty: return "Extended warranty"
        case .mobileDeviceInsurance: return "Mobile device insurance"
        case .flightDelay: return "Flight delay"
        case .baggageDelay: return "Baggage delay"
        case .baggageLoss: return "Lost baggage"
        case .tripCancellation: return "Trip cancellation"
        case .tripInterruption: return "Trip interruption"
        case .rentalCdw: return "Rental car damage/theft"
        case .travelMedical: return "Emergency travel medical"
        case nil: return kind   // unknown kinds render raw, never crash
        }
    }

    /// Short factual fragment for a coverage block, e.g. "90 days · up to $1,000".
    ///
    /// Spec B7 requires the protection lens's "equal or better on every line below" badge to be
    /// checkable against what this renders, so **every field in `BenefitsAdvisor.fieldSpecs` must
    /// appear here**. `maxOriginalWarrantyYears` is shown but deliberately does not vote (it is an
    /// eligibility ceiling, not a magnitude — see the invariants on `fieldSpecs`); displaying more
    /// than is compared is safe, comparing more than is displayed is not.
    static func factsLine(for coverage: BenefitCoverage, kind: String) -> String {
        var parts: [String] = []
        if let hours = coverage.delayHours { parts.append("\(hours) h+ delay") }
        if let days = coverage.windowDays { parts.append("\(days) days") }
        if let years = coverage.extraYears { parts.append("+\(years) yr warranty") }
        if let years = coverage.maxOriginalWarrantyYears { parts.append("originals ≤ \(years) yr") }
        if let max = coverage.maxPerOccurrenceCad { parts.append("up to \(cad(max))") }
        if let max = coverage.maxCad { parts.append("up to \(cad(max))") }
        if let annual = coverage.maxAnnualCad { parts.append("\(cad(annual))/yr") }
        if let perDay = coverage.perDayCad { parts.append("\(cad(perDay))/day") }
        if let deductible = coverage.deductibleCad { parts.append("\(cad(deductible)) deductible") }
        if let days = coverage.maxTripLengthDays { parts.append("trips ≤ \(days) days") }
        if let days = coverage.maxRentalDays { parts.append("rentals ≤ \(days) days") }
        if let value = coverage.maxVehicleValueCad { parts.append("vehicles ≤ \(cad(value))") }
        if let age = coverage.ageLimit { parts.append("under \(age)") }
        return parts.isEmpty ? "see certificate" : parts.joined(separator: " · ")
    }

    /// Which lens context a cross-card nudge should open (kind → closest declared context).
    static func contextKind(forNudgedKind kind: String) -> BenefitContextKind {
        switch BenefitKind(rawValue: kind) {
        case .mobileDeviceInsurance: return .mobileDevice
        case .rentalCdw: return .carRental
        case .flightDelay, .baggageDelay, .baggageLoss,
             .tripCancellation, .tripInterruption, .travelMedical: return .trip
        default: return .electronics
        }
    }

    static func verificationLabel(_ verification: BenefitVerification) -> String {
        switch verification {
        case .stub: return "Unverified draft"
        case .issuerPage: return "Issuer page"
        case .certificateVerified: return "Certificate verified"
        }
    }

    private static func cad(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CAD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return formatter.string(from: value as NSNumber) ?? "$\(Int(value))"
    }
}
