import Foundation

public struct SyncStatusIssue: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case warning
        case error
    }

    public let kind: Kind
    public let message: String
    public let occurredAt: Date

    public init(kind: Kind, message: String, occurredAt: Date = Date()) {
        self.kind = kind
        self.message = message
        self.occurredAt = occurredAt
    }
}

/// Persists device-local sync metadata separately for each signed-in account.
///
/// Owner state has its own offline store. This store is only for presentation metadata such as
/// the last successful sync time, so relaunching the app does not make a completed sync appear to
/// have never happened.
public final class SyncMetadataStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let issueKey: String

    public init(defaults: UserDefaults = OwnerStateLocalStore.sharedDefaults,
                key: String = "ca.pickme.sync-metadata.v1",
                issueKey: String = "ca.pickme.sync-issues.v1") {
        self.defaults = defaults
        self.key = key
        self.issueKey = issueKey
    }

    public func lastSyncedAt(forUserID userID: String) -> Date? {
        records()[userID]
    }

    public func save(lastSyncedAt: Date, forUserID userID: String) {
        var values = records()
        values[userID] = lastSyncedAt
        defaults.set(try? JSONEncoder().encode(values), forKey: key)
    }

    public func remove(forUserID userID: String) {
        var values = records()
        values.removeValue(forKey: userID)
        if values.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(try? JSONEncoder().encode(values), forKey: key)
        }
        clearIssue(forUserID: userID)
    }

    public func issue(forUserID userID: String) -> SyncStatusIssue? {
        issues()[userID]
    }

    public func save(issue: SyncStatusIssue, forUserID userID: String) {
        var values = issues()
        values[userID] = issue
        defaults.set(try? JSONEncoder().encode(values), forKey: issueKey)
    }

    public func clearIssue(forUserID userID: String) {
        var values = issues()
        values.removeValue(forKey: userID)
        if values.isEmpty {
            defaults.removeObject(forKey: issueKey)
        } else {
            defaults.set(try? JSONEncoder().encode(values), forKey: issueKey)
        }
    }

    private func records() -> [String: Date] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: Date].self, from: data)) ?? [:]
    }

    private func issues() -> [String: SyncStatusIssue] {
        guard let data = defaults.data(forKey: issueKey) else { return [:] }
        return (try? JSONDecoder().decode([String: SyncStatusIssue].self, from: data)) ?? [:]
    }
}
