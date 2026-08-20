import Foundation
import CardCopilotEngine

/// Inputs collected by the wallet setup flow. `nil` answers are intentional: the engine treats
/// them as unresolved and does not award the conditional bonus.
public struct WalletSetup: Equatable, Sendable {
    public var ownedCardIds: [String]
    public var defaultCardId: String
    public var rogersEligibleServiceLinked: Bool?
    public var cryptoLevelUpProActive: Bool?
    public var tangerineSelectedCategories: [String]?
    public var switchThreshold: SwitchThreshold
    public var valuationsCad: Valuations

    public init(ownedCardIds: [String], defaultCardId: String,
                rogersEligibleServiceLinked: Bool? = nil,
                cryptoLevelUpProActive: Bool? = nil,
                tangerineSelectedCategories: [String]? = nil,
                switchThreshold: SwitchThreshold,
                valuationsCad: Valuations) {
        self.ownedCardIds = ownedCardIds
        self.defaultCardId = defaultCardId
        self.rogersEligibleServiceLinked = rogersEligibleServiceLinked
        self.cryptoLevelUpProActive = cryptoLevelUpProActive
        self.tangerineSelectedCategories = tangerineSelectedCategories
        self.switchThreshold = switchThreshold
        self.valuationsCad = valuationsCad
    }
}

/// Pure OwnerState construction belongs in Store, at the boundary between setup answers and the
/// engine. This deliberately starts each cap at zero rather than inheriting the bundled owner's
/// cap progress or account details.
public enum OwnerStateBuilder {
    public static let defaultSwitchThreshold = SwitchThreshold(minAdvantagePercentagePoints: 0.5,
                                                               minAdvantageCad: 0.25,
                                                               semantics: "both")

    public static func setup(from ownerState: OwnerState) -> WalletSetup {
        WalletSetup(ownedCardIds: ownerState.ownedCardIds,
                    defaultCardId: ownerState.defaultCardId,
                    rogersEligibleServiceLinked: ownerState.cardStates["rogers-red-we"]?.rogersEligibleServiceLinked,
                    cryptoLevelUpProActive: ownerState.cardStates["cryptocom-royal-indigo"]?.cryptoLevelUpProActive,
                    tangerineSelectedCategories: ownerState.cardStates["tangerine-moneyback-world"]?.selectedCategories,
                    switchThreshold: ownerState.switchThreshold,
                    valuationsCad: ownerState.valuationsCad)
    }

    public static func make(setup: WalletSetup, catalogue: Catalogue, version: String = "wallet-setup-1") -> OwnerState {
        let availableIDs = Set(catalogue.cards.map(\.cardId))
        let owned = Array(NSOrderedSet(array: setup.ownedCardIds))
            .compactMap { $0 as? String }
            .filter { availableIDs.contains($0) }
        let defaultCardId = owned.contains(setup.defaultCardId) ? setup.defaultCardId : (owned.first ?? "")
        var cardStates: [String: CardState] = [:]

        for card in catalogue.cards where owned.contains(card.cardId) {
            var state = CardState()
            let capIDs = card.caps.map(\.capId)
            if !capIDs.isEmpty { state.capProgress = Dictionary(uniqueKeysWithValues: capIDs.map { ($0, 0) }) }
            switch card.cardId {
            case "rogers-red-we": state.rogersEligibleServiceLinked = setup.rogersEligibleServiceLinked
            case "cryptocom-royal-indigo": state.cryptoLevelUpProActive = setup.cryptoLevelUpProActive
            case "tangerine-moneyback-world":
                state.selectedCategories = setup.tangerineSelectedCategories?.isEmpty == false
                    ? setup.tangerineSelectedCategories : nil
            default: break
            }
            cardStates[card.cardId] = state
        }

        return OwnerState(ownerStateVersion: version, ownedCardIds: owned, defaultCardId: defaultCardId,
                          switchThreshold: setup.switchThreshold, carry: Carry(drawerCards: []),
                          cardStates: cardStates, valuationsCad: setup.valuationsCad)
    }
}

/// The device copy is the checkout source of truth while offline. A server copy is updated when
/// the user is signed in, but failed network work never replaces this usable local wallet.
public final class OwnerStateLocalStore: @unchecked Sendable {
    public static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: "group.ca.inunity.pickme") ?? .standard
    }

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = OwnerStateLocalStore.sharedDefaults, key: String = "ca.pickme.owner-state.v1") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> OwnerState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(OwnerState.self, from: data)
    }

    public func save(_ ownerState: OwnerState) throws {
        defaults.set(try JSONEncoder().encode(ownerState), forKey: key)
    }

    public func remove() { defaults.removeObject(forKey: key) }
}

public struct PendingCardRequest: Codable, Equatable, Sendable {
    public let issuer: String
    public let cardName: String
    public let note: String?

    public init(issuer: String, cardName: String, note: String? = nil) {
        self.issuer = issuer
        self.cardName = cardName
        self.note = note
    }
}

public final class CardRequestQueue: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String
    private let accountKey: String

    public init(defaults: UserDefaults = OwnerStateLocalStore.sharedDefaults,
                key: String = "ca.pickme.pending-card-requests.v1",
                accountKey: String = "ca.pickme.pending-card-requests-by-account.v1") {
        self.defaults = defaults
        self.key = key
        self.accountKey = accountKey
    }

    public func enqueue(_ request: PendingCardRequest) {
        var queued = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([PendingCardRequest].self, from: $0) } ?? []
        guard !queued.contains(request) else { return }
        queued.append(request)
        defaults.set(try? JSONEncoder().encode(queued), forKey: key)
    }

    public func pending() -> [PendingCardRequest] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([PendingCardRequest].self, from: $0) } ?? []
    }

    public func remove(_ request: PendingCardRequest) {
        let remaining = pending().filter { $0 != request }
        defaults.set(try? JSONEncoder().encode(remaining), forKey: key)
    }

    public func enqueue(_ request: PendingCardRequest, forUserID userID: String) {
        var values = accountRecords()
        var queued = values[userID] ?? []
        guard !queued.contains(request) else { return }
        queued.append(request)
        values[userID] = queued
        defaults.set(try? JSONEncoder().encode(values), forKey: accountKey)
    }

    public func pending(forUserID userID: String) -> [PendingCardRequest] {
        accountRecords()[userID] ?? []
    }

    public func remove(_ request: PendingCardRequest, forUserID userID: String) {
        var values = accountRecords()
        let remaining = (values[userID] ?? []).filter { $0 != request }
        if remaining.isEmpty {
            values.removeValue(forKey: userID)
        } else {
            values[userID] = remaining
        }
        if values.isEmpty {
            defaults.removeObject(forKey: accountKey)
        } else {
            defaults.set(try? JSONEncoder().encode(values), forKey: accountKey)
        }
    }

    /// Assigns requests made before any account was attached to the first account the owner uses.
    public func claimUnscopedRequests(forUserID userID: String) {
        let unscoped = pending()
        guard !unscoped.isEmpty else { return }
        for request in unscoped { enqueue(request, forUserID: userID) }
        defaults.removeObject(forKey: key)
    }

    public func removeAll(forUserID userID: String) {
        var values = accountRecords()
        values.removeValue(forKey: userID)
        if values.isEmpty {
            defaults.removeObject(forKey: accountKey)
        } else {
            defaults.set(try? JSONEncoder().encode(values), forKey: accountKey)
        }
    }

    private func accountRecords() -> [String: [PendingCardRequest]] {
        guard let data = defaults.data(forKey: accountKey) else { return [:] }
        return (try? JSONDecoder().decode([String: [PendingCardRequest]].self, from: data)) ?? [:]
    }
}
