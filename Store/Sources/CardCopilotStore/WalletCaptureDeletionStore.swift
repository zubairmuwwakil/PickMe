import Foundation

/// Durable local record of Wallet captures the owner removed from Activity.
///
/// Wallet feedback is retained by the sync service so another signed-in device can import it.
/// Deleting the corresponding local `StoredPurchase` without retaining its event id therefore
/// made the next sync look like a brand-new capture and recreate it. These ids are deliberately
/// local: deleting Activity on one device must not silently erase the source transaction or hide
/// it on another device.
public final class WalletCaptureDeletionStore {
    private let defaults: UserDefaults
    private let storageKey: String

    public init(defaults: UserDefaults = .standard,
                storageKey: String = "wallet-capture-deleted-event-ids-v1") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func contains(eventID: String) -> Bool {
        eventIDs.contains(eventID)
    }

    public func retainingUndeleted(_ feedback: [WalletFeedback]) -> [WalletFeedback] {
        let deletedIDs = eventIDs
        return feedback.filter { !deletedIDs.contains($0.eventId) }
    }

    public func recordDeletion(eventID: String) {
        guard !eventID.isEmpty else { return }
        var ids = eventIDs
        ids.insert(eventID)
        defaults.set(Array(ids), forKey: storageKey)
    }

    /// A local-history wipe must also remove these suppressions: there is no remaining Activity
    /// record for them to protect, and retaining them would make a later sync omit valid history.
    public func forgetAll() {
        defaults.removeObject(forKey: storageKey)
    }

    private var eventIDs: Set<String> {
        Set(defaults.stringArray(forKey: storageKey) ?? [])
    }
}
