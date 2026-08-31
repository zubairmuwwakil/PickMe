import Foundation

public enum CreditOpportunityStatus: String, Codable, Equatable, Sendable {
    case available, used, needsEnrollment, notYetEligible, scheduleUnresolved
}

public struct CreditWindow: Codable, Equatable, Sendable {
    public let id: String
    public let startsOn: String?
    /// Inclusive final purchase date for calendar/anniversary windows.
    public let expiresOn: String?
    public let nextEligibleOn: String?

    public init(id: String, startsOn: String? = nil, expiresOn: String? = nil,
                nextEligibleOn: String? = nil) {
        self.id = id
        self.startsOn = startsOn
        self.expiresOn = expiresOn
        self.nextEligibleOn = nextEligibleOn
    }
}

public struct CreditOpportunity: Codable, Equatable, Identifiable, Sendable {
    public let cardId: String
    public let creditId: String
    public let label: String
    public let value: Money
    public let window: CreditWindow
    public let consumedAmount: Double
    public let realizedAmount: Double
    public let remainingAmount: Double
    public let enrollmentStatus: CreditEnrollmentStatus
    public let status: CreditOpportunityStatus
    public let daysRemaining: Int?

    public var id: String { "\(cardId):\(creditId):\(window.id)" }
}

/// Converts issuer credit rules plus aggregate owner state into the handful of actions PickMe can
/// defend: enroll, use, confirm, or wait. It does not infer transactions and does not price a
/// benefit for keep/cancel; those require reconciled financial facts from the purchase spine.
public enum CreditAdvisor {
    private static let isoFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public static func opportunities(catalogue: Catalogue, ownerState: OwnerState,
                                     asOf: String) -> [CreditOpportunity] {
        let owned = Set(ownerState.ownedCardIds)
        return catalogue.cards
            .filter { owned.contains($0.cardId) && $0.isPublished && $0.isScoreable(asOf: asOf) }
            .flatMap { card -> [CreditOpportunity] in
                let state = ownerState.cardStates[card.cardId] ?? CardState()
                return (card.credits ?? []).compactMap {
                    opportunity(cardId: card.cardId, credit: $0, cardState: state, asOf: asOf)
                }
            }
            .sorted { lhs, rhs in
                switch (lhs.daysRemaining, rhs.daysRemaining) {
                case let (l?, r?) where l != r: return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                }
            }
    }

    public static func opportunity(cardId: String, credit: CardCredit, cardState: CardState,
                                   asOf: String) -> CreditOpportunity? {
        guard isLive(credit, asOf: asOf),
              let window = currentWindow(for: credit, cardState: cardState, asOf: asOf) else {
            return nil
        }

        let creditState = cardState.creditStates?[credit.creditId] ?? CreditState()
        let usage = creditState.windows[window.id]
        let consumed = max(0, usage?.consumedAmount ?? 0)
        let realized = max(0, usage?.realizedAmount ?? 0)
        let enrollmentStatus: CreditEnrollmentStatus = {
            guard credit.enrollment?.required == true else { return .notRequired }
            return creditState.enrollmentStatus
        }()
        let notYetEligible = window.nextEligibleOn.map { asOf < $0 } ?? false
        let remaining = notYetEligible ? 0 : max(0, credit.value.amount - consumed)
        let status: CreditOpportunityStatus
        if notYetEligible {
            status = .notYetEligible
        } else if credit.effectiveSchedule?.basis == .accountAnniversary && window.expiresOn == nil {
            status = .scheduleUnresolved
        } else if credit.enrollment?.required == true && enrollmentStatus != .enrolled {
            status = .needsEnrollment
        } else if remaining <= 0.000_001 {
            status = .used
        } else {
            status = .available
        }

        return CreditOpportunity(
            cardId: cardId,
            creditId: credit.creditId,
            label: credit.label,
            value: credit.value,
            window: window,
            consumedAmount: consumed,
            realizedAmount: realized,
            remainingAmount: remaining,
            enrollmentStatus: enrollmentStatus,
            status: status,
            daysRemaining: window.expiresOn.flatMap { days(from: asOf, through: $0) })
    }

    public static func currentWindow(for credit: CardCredit, cardState: CardState,
                                     asOf: String) -> CreditWindow? {
        guard let schedule = credit.effectiveSchedule, let asOfDate = parse(asOf) else { return nil }
        switch schedule.basis {
        case .calendar:
            guard let unit = schedule.unit else { return nil }
            let calendar: Calendar = {
                var calendar = Calendar(identifier: .gregorian)
                calendar.locale = Locale(identifier: "en_US_POSIX")
                calendar.timeZone = schedule.resetTimeZone.flatMap(TimeZone.init(identifier:))
                    ?? TimeZone(secondsFromGMT: 0)!
                return calendar
            }()
            let components = calendar.dateComponents([.year, .month], from: asOfDate)
            guard let year = components.year, let month = components.month else { return nil }
            let startMonth: Int
            let spanMonths: Int
            switch unit {
            case .month:
                startMonth = month
                spanMonths = max(1, schedule.interval ?? 1)
            case .quarter:
                startMonth = ((month - 1) / 3) * 3 + 1
                spanMonths = 3 * max(1, schedule.interval ?? 1)
            case .halfYear:
                startMonth = month <= 6 ? 1 : 7
                spanMonths = 6 * max(1, schedule.interval ?? 1)
            case .year:
                startMonth = 1
                spanMonths = 12 * max(1, schedule.interval ?? 1)
            }
            guard let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)),
                  let endExclusive = calendar.date(byAdding: .month, value: spanMonths, to: start),
                  let end = calendar.date(byAdding: .day, value: -1, to: endExclusive) else { return nil }
            let startOn = format(start, calendar: calendar)
            let expiresOn = format(end, calendar: calendar)
            return CreditWindow(id: "\(startOn)/\(expiresOn)", startsOn: startOn, expiresOn: expiresOn)

        case .accountAnniversary:
            guard let opened = cardState.accountOpenedAt.flatMap(parse),
                  let intervalMonths = schedule.intervalMonths, intervalMonths > 0 else {
                return CreditWindow(id: "account-anniversary:unknown")
            }
            let calendar = utcCalendar
            var start = opened
            while let next = calendar.date(byAdding: .month, value: intervalMonths, to: start), next <= asOfDate {
                start = next
            }
            guard let endExclusive = calendar.date(byAdding: .month, value: intervalMonths, to: start),
                  let end = calendar.date(byAdding: .day, value: -1, to: endExclusive) else { return nil }
            let startOn = format(start, calendar: calendar)
            let expiresOn = format(end, calendar: calendar)
            return CreditWindow(id: "\(startOn)/\(expiresOn)", startsOn: startOn, expiresOn: expiresOn)

        case .rolling:
            let creditState = cardState.creditStates?[credit.creditId] ?? CreditState()
            guard let last = creditState.lastRedemptionAt.flatMap(parse),
                  let intervalMonths = schedule.intervalMonths, intervalMonths > 0 else {
                return CreditWindow(id: "rolling:never-used")
            }
            let next = utcCalendar.date(byAdding: .month, value: intervalMonths, to: last)
            let nextOn = next.map { format($0, calendar: utcCalendar) }
            return CreditWindow(id: "rolling:\(format(last, calendar: utcCalendar))",
                                startsOn: nextOn, nextEligibleOn: nextOn)
        }
    }

    private static func isLive(_ credit: CardCredit, asOf: String) -> Bool {
        if let from = credit.effectiveFrom, asOf < from { return false }
        if let to = credit.effectiveTo, asOf > to { return false }
        return true
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func parse(_ value: String) -> Date? { isoFormatter.date(from: value) }

    private static func format(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0,
                      components.month ?? 0, components.day ?? 0)
    }

    private static func days(from start: String, through end: String) -> Int? {
        guard let startDate = parse(start), let endDate = parse(end) else { return nil }
        return max(0, utcCalendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0)
    }
}
