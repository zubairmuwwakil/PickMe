import Foundation

/// When a merchant counts as one the owner actually shops at.
///
/// Kept as free functions with no storage and no clock of their own, for the reason
/// `DiscoveryPolicy` is: the decision is the part worth testing, and it stops being testable the
/// moment it is entangled with where the counts happen to live.

/// How far back a visit still counts.
///
/// Ninety days rather than thirty because the cadence that matters most is monthly. A big-shop
/// grocery run happens once every few weeks, so a thirty-day window can never reach three visits
/// there — and that is precisely the store whose card advice is worth the most. Ninety days
/// catches weekly coffee and monthly big-shop with one rule.
public let patronageWindowDays: Int = 90

/// How many separate days inside the window earn the standing.
///
/// Days, never captures. Three taps in one morning is one visit; counting captures would rank a
/// store by how many small things get bought there rather than by how often the owner goes.
public let patronageVisitDaysRequired: Int = 3

/// The calendar day a capture belongs to, as a zero-padded ISO day.
///
/// The format is load-bearing rather than cosmetic: the window filter compares these as strings,
/// which is only correct because zero-padded ISO days sort lexicographically in chronological
/// order. Days are local, so an 11pm purchase and a 1am one are two visits, which is what a
/// person means by "I went twice". A traveller crossing zones gets a slightly fuzzy boundary;
/// that is a better error than pretending everyone lives in UTC.
public func patronageDayKey(for date: Date, calendar: Calendar = .current) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
}

/// The oldest day key still inside the window. Anything strictly less than this has aged out.
public func patronageWindowStartKey(asOf date: Date, calendar: Calendar = .current) -> String {
    let start = calendar.date(byAdding: .day, value: -patronageWindowDays, to: date) ?? date
    return patronageDayKey(for: start, calendar: calendar)
}

/// The subset of `visitDayKeys` still inside the window.
///
/// Separate from `isFrequented` because the store prunes with it on every write: standing is a
/// question, but bounded retention is a promise, and the promise must not depend on anyone
/// remembering to ask the question.
public func patronageDaysWithinWindow(_ visitDayKeys: Set<String>, asOf date: Date,
                                      calendar: Calendar = .current) -> Set<String> {
    let cutoff = patronageWindowStartKey(asOf: date, calendar: calendar)
    return visitDayKeys.filter { $0 >= cutoff }
}

/// Whether these visits earn the `.frequented` tier as of `date`.
///
/// Standing lapses on its own. A store the owner stopped visiting falls below the bar as its
/// visits age out, without anything having to notice or clean up.
public func isFrequented(visitDayKeys: Set<String>, asOf date: Date,
                         calendar: Calendar = .current) -> Bool {
    patronageDaysWithinWindow(visitDayKeys, asOf: date, calendar: calendar).count
        >= patronageVisitDaysRequired
}

/// The patronage key a Wallet capture earns, or nil when the captured text names no merchant
/// this device can recognise.
///
/// Returning nil rather than a normalised form of the raw string is the whole point. Standing
/// decides whether the app interrupts someone, and a key invented from "PAYPAL *XJ4T2" would
/// accrue standing under an identity that nothing can ever match on arrival — a counter that
/// grows and never fires.
///
/// `merchantRaw` is tried first because it is the cleaner of the two fields when the automation
/// supplies it; `transactionName` is the fallback, not a second opinion.
public func patronageKey(forCapturedMerchant merchantRaw: String?,
                         transactionName: String?) -> String? {
    for candidate in [merchantRaw, transactionName] {
        guard let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { continue }
        if let indexed = MerchantRecognizer.recognise(text) { return indexed.id }
    }
    return nil
}
