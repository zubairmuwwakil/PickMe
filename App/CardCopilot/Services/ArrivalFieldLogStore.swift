import CardCopilotStore
import Foundation

/// The dev-only field log: one record per arrival, bounded, on this phone only.
///
/// Deliberately richer than `SuppressionLog` and `AmbientCoverageLog`, which record counts and no
/// identities. This records coordinates and merchant names, which is exactly why it is dev-only —
/// it exists to answer questions about *which* store the app named and whether that mattered, and
/// those questions cannot be asked of a counter.
///
/// Bounded because a field week is the unit of analysis and an unbounded log in `UserDefaults`
/// would eventually be the reason someone turns the instrumented build off. The buffer drops the
/// oldest, never the newest: a week of driving must not leave the app unable to record today.
///
/// A decode failure reads as an empty log rather than propagating. A record shape that changed
/// between builds must not take the arrivals with it, or crash a background wake.
@MainActor
final class ArrivalFieldLogStore {
    private let defaults: UserDefaults
    private let key = "ambientFieldLog.v1"
    private let capacity: Int

    init(defaults: UserDefaults = .standard, capacity: Int = 300) {
        self.defaults = defaults
        self.capacity = capacity
    }

    /// Oldest first, which is the order a week reads in.
    func all() -> [ArrivalFieldRecord] {
        guard let data = defaults.data(forKey: key),
              let records = try? decoder.decode([ArrivalFieldRecord].self, from: data) else {
            return []
        }
        return records
    }

    func record(_ record: ArrivalFieldRecord) {
        var records = all()
        records.append(record)
        if records.count > capacity { records.removeFirst(records.count - capacity) }
        save(records)
    }

    /// Attaches the owner's reaction to the arrival that produced the alert.
    ///
    /// Keyed on the region because that is all a notification action carries, and applied to the
    /// most recent arrival there — an action minutes after an alert belongs to that alert, not to
    /// the same plaza last Tuesday.
    ///
    /// Never overwrites. The owner can tap "used this card" and later mute the same merchant;
    /// the first answer is the one about that alert, and letting the second win would turn a
    /// useful alert into a muted one in the only signal that says which it was.
    func recordEngagement(_ action: ArrivalEngagement, regionId: String) {
        var records = all()
        guard let index = records.lastIndex(where: {
            $0.regionId == regionId && $0.engagement == nil
        }) else { return }
        records[index].engagement = action
        save(records)
    }

    /// Annotates one record with the owner's "not this store" correction.
    ///
    /// Keyed on the record's own id rather than on a region, because the caller knows exactly
    /// which scan produced the subject that was rejected. Engagement has to guess — a notification
    /// action carries nothing but a region — but a correction does not, and guessing here would
    /// attach a label to the wrong plaza.
    ///
    /// Never overwrites: the first correction is the one about the answer that was on screen.
    func recordCorrection(rejected: String, chosen: String, offered: [String], recordId: UUID,
                          at date: Date = .now) {
        var records = all()
        guard let index = records.firstIndex(where: { $0.id == recordId }),
              records[index].correction == nil else { return }
        records[index] = records[index].correcting(rejected: rejected, chosen: chosen,
                                                   offered: offered, at: date)
        save(records)
    }

    /// The second delivery sample, taken the next time the app is opened.
    ///
    /// Applies only to arrivals that actually got a request identifier: an arrival the gate never
    /// spoke on has nothing to resample, and writing an outcome for it would turn a policy
    /// decision into a delivery statistic.
    ///
    /// Once per record. A second opening hours later says nothing about delivery and would
    /// overwrite the answer with the owner's tidying habits.
    func recordForegroundDelivery(deliveredIdentifiers: Set<String>) {
        var records = all()
        var changed = false
        for index in records.indices {
            guard let identifier = records[index].notificationRequestIdentifier,
                  records[index].notificationDeliveryOnForeground == nil else { continue }
            records[index].notificationDeliveryOnForeground = arrivalNotificationDelivery(
                requestIdentifier: identifier, requestFailed: false,
                deliveredIdentifiers: deliveredIdentifiers)
            changed = true
        }
        if changed { save(records) }
    }

    func forgetAll() { defaults.removeObject(forKey: key) }

    /// The whole log, with receipts joined and the metrics derived, as JSON somebody can open.
    ///
    /// Receipts are joined here rather than at capture because a charge posts minutes to hours
    /// after the arrival — long after the record was written — and because the join is a pure
    /// function that should be re-runnable against a better matcher later.
    func exportJSON(receipts: [ArrivalReceipt]) -> Data? {
        let joined = joinReceipts(all(), receipts: receipts)
        let encoder = JSONEncoder()
        // Readable by something other than this app: ISO-8601 rather than reference-date doubles,
        // sorted keys so two exports can be diffed at all.
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(ArrivalFieldExport(exportedAt: .now,
                                                      metrics: arrivalFieldMetrics(joined),
                                                      records: joined))
    }

    private var decoder: JSONDecoder { JSONDecoder() }

    private func save(_ records: [ArrivalFieldRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: key)
    }
}

/// What an export file contains. The metrics ride along with the records rather than being left
/// to be recomputed, so a file handed to somebody is self-describing.
struct ArrivalFieldExport: Codable {
    let exportedAt: Date
    let metrics: ArrivalFieldMetrics
    let records: [ArrivalFieldRecord]
}
