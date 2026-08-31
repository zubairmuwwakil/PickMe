import Foundation

public enum ApplicationRequirementCoverage: String, Codable, Equatable, Sendable {
    case completePublishedSet, partialPublishedSet
}

public enum FinancialRequirementPublicationStatus: String, Codable, Equatable, Sendable {
    case published, noIssuerPublishedMinimumFound
}

public enum RequirementSemantics: String, Codable, Equatable, Sendable {
    case any, unknown
}

public enum IncomeRequirementType: String, Codable, Equatable, Sendable, CaseIterable {
    case individualAnnualIncome, householdAnnualIncome
}

public enum IncomeRequirementOperator: String, Codable, Equatable, Sendable {
    case atLeast, greaterThan
}

public struct IncomeRequirementOption: Codable, Equatable, Sendable {
    public let type: IncomeRequirementType
    public let `operator`: IncomeRequirementOperator
    public let amount: Money

    public init(type: IncomeRequirementType, operator: IncomeRequirementOperator, amount: Money) {
        self.type = type
        self.operator = `operator`
        self.amount = amount
    }
}

public struct FinancialApplicationRequirements: Codable, Equatable, Sendable {
    public let publicationStatus: FinancialRequirementPublicationStatus
    public let semantics: RequirementSemantics
    public let options: [IncomeRequirementOption]
}

public enum ApplicationRequirementSourceScope: String, Codable, Equatable, Sendable {
    case cardSpecific, cardSpecificApplication
}

public struct ApplicationRequirementSource: Codable, Equatable, Sendable {
    public let url: String
    public let scope: ApplicationRequirementSourceScope
    public let verifiedAt: String
}

public struct CardApplicationRequirements: Codable, Equatable, Sendable {
    public let cardId: String
    public let coverage: ApplicationRequirementCoverage
    public let financialRequirements: FinancialApplicationRequirements
    public let sources: [ApplicationRequirementSource]
}

public struct ApplicationRequirementCatalogue: Codable, Equatable, Sendable {
    public let applicationRequirementsVersion: String
    public let verifiedAt: String
    public let requirements: [CardApplicationRequirements]

    public func requirement(for cardId: String) -> CardApplicationRequirements? {
        requirements.first { $0.cardId == cardId }
    }
}

/// Optional, owner-entered income facts used only for acquisition screening. These values are
/// separate from OwnerState so they can remain local to the app instead of entering wallet sync.
public struct ApplicantIncomeProfile: Codable, Equatable, Sendable {
    public var individualAnnualIncome: Money?
    public var householdAnnualIncome: Money?

    public init(individualAnnualIncome: Money? = nil, householdAnnualIncome: Money? = nil) {
        self.individualAnnualIncome = individualAnnualIncome
        self.householdAnnualIncome = householdAnnualIncome
    }

    public func value(for type: IncomeRequirementType) -> Money? {
        switch type {
        case .individualAnnualIncome: individualAnnualIncome
        case .householdAnnualIncome: householdAnnualIncome
        }
    }
}

public enum IncomeRequirementAssessmentStatus: String, Codable, Equatable, Sendable {
    case meetsPublishedMinimum
    case belowPublishedMinimum
    case needsMoreInformation
    case noIssuerPublishedMinimumFound
    case requirementsUnavailable
}

public enum IncomePathAssessmentStatus: String, Codable, Equatable, Sendable {
    case met, belowMinimum, missingOwnerInput, currencyMismatch
}

public struct IncomePathAssessment: Codable, Equatable, Sendable {
    public let requirement: IncomeRequirementOption
    public let reportedAmount: Money?
    public let status: IncomePathAssessmentStatus
    public let shortfall: Money?
    public let shortfallPercentage: Double?
}

public struct IncomeRequirementAssessment: Codable, Equatable, Sendable {
    public let status: IncomeRequirementAssessmentStatus
    public let coverage: ApplicationRequirementCoverage?
    public let paths: [IncomePathAssessment]
    public let matchedType: IncomeRequirementType?
    public let closestType: IncomeRequirementType?
    public let missingTypes: [IncomeRequirementType]

    public var closestPath: IncomePathAssessment? {
        guard let closestType else { return nil }
        return paths.first { $0.requirement.type == closestType }
    }

    /// Safe for the primary suggestion section. This means only that PickMe found no unmet
    /// published income minimum; it is never an approval prediction.
    public var isIncomeReady: Bool {
        status == .meetsPublishedMinimum || status == .noIssuerPublishedMinimumFound
    }

    public static let unavailable = IncomeRequirementAssessment(
        status: .requirementsUnavailable, coverage: nil, paths: [], matchedType: nil,
        closestType: nil, missingTypes: [])
}

public enum ApplicationRequirementEvaluator {
    public static func assess(requirements: CardApplicationRequirements?,
                              profile: ApplicantIncomeProfile) -> IncomeRequirementAssessment {
        guard let requirements else { return .unavailable }
        let financial = requirements.financialRequirements
        guard financial.publicationStatus == .published else {
            return IncomeRequirementAssessment(
                status: .noIssuerPublishedMinimumFound,
                coverage: requirements.coverage,
                paths: [], matchedType: nil, closestType: nil, missingTypes: [])
        }

        let paths = financial.options.map { option -> IncomePathAssessment in
            guard let reported = profile.value(for: option.type) else {
                return IncomePathAssessment(requirement: option, reportedAmount: nil,
                                            status: .missingOwnerInput, shortfall: nil,
                                            shortfallPercentage: nil)
            }
            guard reported.currency == option.amount.currency else {
                return IncomePathAssessment(requirement: option, reportedAmount: reported,
                                            status: .currencyMismatch, shortfall: nil,
                                            shortfallPercentage: nil)
            }
            let met: Bool
            switch option.operator {
            case .atLeast: met = reported.amount >= option.amount.amount
            case .greaterThan: met = reported.amount > option.amount.amount
            }
            guard !met else {
                return IncomePathAssessment(requirement: option, reportedAmount: reported,
                                            status: .met, shortfall: nil,
                                            shortfallPercentage: nil)
            }

            // The app collects annual income in whole currency units. For a strict `>` boundary,
            // exactly $50,000 therefore needs $1 more; preserving that distinction is the MBNA
            // fixture's purpose.
            let operatorIncrement = option.operator == .greaterThan ? 1.0 : 0.0
            let gap = max(0, option.amount.amount - reported.amount + operatorIncrement)
            return IncomePathAssessment(
                requirement: option,
                reportedAmount: reported,
                status: .belowMinimum,
                shortfall: Money(amount: gap, currency: option.amount.currency),
                shortfallPercentage: option.amount.amount > 0 ? gap / option.amount.amount : nil)
        }

        if let matched = paths.first(where: { $0.status == .met }) {
            return IncomeRequirementAssessment(
                status: .meetsPublishedMinimum,
                coverage: requirements.coverage,
                paths: paths,
                matchedType: matched.requirement.type,
                closestType: nil,
                missingTypes: [])
        }

        let missing = paths.filter {
            $0.status == .missingOwnerInput || $0.status == .currencyMismatch
        }.map(\.requirement.type)
        let closest = paths
            .filter { $0.status == .belowMinimum }
            .min {
                let lhs = $0.shortfallPercentage ?? .infinity
                let rhs = $1.shortfallPercentage ?? .infinity
                if lhs != rhs { return lhs < rhs }
                return $0.requirement.type.rawValue < $1.requirement.type.rawValue
            }

        return IncomeRequirementAssessment(
            status: missing.isEmpty ? .belowPublishedMinimum : .needsMoreInformation,
            coverage: requirements.coverage,
            paths: paths,
            matchedType: nil,
            closestType: closest?.requirement.type,
            missingTypes: missing)
    }
}
