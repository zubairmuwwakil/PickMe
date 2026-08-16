import Foundation

/// The stretch of months one cap accumulates over.
///
/// `PortfolioAnalyzer` deliberately sidesteps this: it asks what a card is worth over *a* year
/// and treats annual and account-year caps as one full year of room. A projection cannot
/// sidestep it — the whole output is a date, and a date computed against the wrong twelve
/// months is worse than no date at all.
///
/// Months, not days. A cap crossing is reported to the month because the inputs are declared
/// billing amounts, and pretending to a day would be precision the data does not carry.
public enum CapWindow {

    public struct Window: Equatable, Sendable {
        /// Inclusive, "YYYY-MM".
        public let startMonth: String
        public let endMonth: String

        public init(startMonth: String, endMonth: String) {
            self.startMonth = startMonth
            self.endMonth = endMonth
        }
    }

    /// The window containing `asOf`, or `nil` when the cap's anchor is unresolved owner state.
    /// Returning `nil` rather than assuming a month is the same rule `RuleMatcher` follows for
    /// unresolved owner conditions: the engine refuses instead of guessing.
    public static func resolve(cap: Cap, cardId: String, ownerState: OwnerState,
                               asOf: String) -> Window? {
        let asOfIndex = monthIndex(asOf)
        switch cap.period {
        case .calendarMonth:
            return Window(startMonth: month(asOfIndex), endMonth: month(asOfIndex))
        case .calendarYear:
            let january = (asOfIndex / 12) * 12
            return Window(startMonth: month(january), endMonth: month(january + 11))
        case .accountYear:
            guard let anchorMonth = anchorMonth(for: cap, cardId: cardId, ownerState: ownerState)
            else { return nil }
            // Before the anchor month, the live account year is the one that opened *last* year.
            let asOfMonth = asOfIndex % 12 + 1
            let startYear = asOfMonth >= anchorMonth ? asOfIndex / 12 : asOfIndex / 12 - 1
            let start = startYear * 12 + anchorMonth - 1
            return Window(startMonth: month(start), endMonth: month(start + 11))
        }
    }

    /// Account-year anchors are stored per card under owner-declared field names, and the
    /// catalogue references them by path. Only paths this engine can actually resolve are
    /// honoured; an unknown one reads as unresolved rather than defaulting to January.
    private static func anchorMonth(for cap: Cap, cardId: String,
                                    ownerState: OwnerState) -> Int? {
        let state = ownerState.cardStates[cardId]
        switch cap.anchor {
        case "ownerState.scotiaAccountYearAnchorMonth": return state?.scotiaAccountYearAnchorMonth
        case "ownerState.rogersAccountAnniversaryMonth": return state?.rogersAccountAnniversaryMonth
        default: return nil
        }
    }

    // MARK: - Month arithmetic

    /// "YYYY-MM" or "YYYY-MM-DD" → months since year 0.
    static func monthIndex(_ isoDate: String) -> Int {
        let parts = isoDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count >= 2 else { return 0 }
        return parts[0] * 12 + parts[1] - 1
    }

    static func month(_ index: Int) -> String {
        String(format: "%04d-%02d", index / 12, index % 12 + 1)
    }
}
