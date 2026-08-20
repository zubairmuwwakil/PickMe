import Foundation
import CardCopilotEngine

/// Keeps a separate device cache for every account that has used this installation while leaving
/// `OwnerStateLocalStore` as the active wallet read by widgets, Watch, and the share extension.
public final class AccountOwnerStateStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let profilesKey: String
    private let activeUserKey: String
    private let activeStore: OwnerStateLocalStore

    public init(defaults: UserDefaults = OwnerStateLocalStore.sharedDefaults,
                profilesKey: String = "ca.pickme.owner-state-profiles.v1",
                activeUserKey: String = "ca.pickme.owner-state-active-user.v1",
                activeStore: OwnerStateLocalStore? = nil) {
        self.defaults = defaults
        self.profilesKey = profilesKey
        self.activeUserKey = activeUserKey
        self.activeStore = activeStore ?? OwnerStateLocalStore(defaults: defaults)
    }

    public var activeUserID: String? {
        defaults.string(forKey: activeUserKey)
    }

    public func state(forUserID userID: String) -> OwnerState? {
        profiles()[userID]
    }

    /// Makes this account's wallet the device-wide active wallet and caches it for later switches.
    public func activate(_ ownerState: OwnerState, forUserID userID: String) throws {
        var values = profiles()
        values[userID] = ownerState
        defaults.set(try JSONEncoder().encode(values), forKey: profilesKey)
        try activeStore.save(ownerState)
        defaults.set(userID, forKey: activeUserKey)
    }

    /// Saves an edit to the active device wallet and, when bound, its account profile too.
    public func updateActive(_ ownerState: OwnerState) throws {
        try activeStore.save(ownerState)
        guard let activeUserID else { return }
        var values = profiles()
        values[activeUserID] = ownerState
        defaults.set(try JSONEncoder().encode(values), forKey: profilesKey)
    }

    /// Removes account-scoped cache and binding while deliberately preserving the device wallet.
    /// Account deletion lets the owner choose separately whether local data is erased.
    public func removeProfile(forUserID userID: String) {
        var values = profiles()
        values.removeValue(forKey: userID)
        if values.isEmpty {
            defaults.removeObject(forKey: profilesKey)
        } else {
            defaults.set(try? JSONEncoder().encode(values), forKey: profilesKey)
        }
        if activeUserID == userID {
            defaults.removeObject(forKey: activeUserKey)
        }
    }

    private func profiles() -> [String: OwnerState] {
        guard let data = defaults.data(forKey: profilesKey) else { return [:] }
        return (try? JSONDecoder().decode([String: OwnerState].self, from: data)) ?? [:]
    }
}

/// A latest-value outbox for wallet edits. Replacing an older pending value is correct because the
/// owner-state endpoint accepts the complete current wallet, not a sequence of patches.
public final class OwnerStateUploadQueue: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = OwnerStateLocalStore.sharedDefaults,
                key: String = "ca.pickme.pending-owner-state-uploads.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func enqueue(_ ownerState: OwnerState, forUserID userID: String) throws {
        var values = records()
        values[userID] = ownerState
        defaults.set(try JSONEncoder().encode(values), forKey: key)
    }

    public func pending(forUserID userID: String) -> OwnerState? {
        records()[userID]
    }

    public func remove(forUserID userID: String) {
        var values = records()
        values.removeValue(forKey: userID)
        if values.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(try? JSONEncoder().encode(values), forKey: key)
        }
    }

    private func records() -> [String: OwnerState] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: OwnerState].self, from: data)) ?? [:]
    }
}
