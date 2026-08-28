import Foundation
import CardCopilotEngine

/// The editable projection of an owner's wallet: what a person *answers*, never what the system
/// *observes*. Cap progress, carry and account anchors are observations and live only in
/// `OwnerState` — which is exactly why `apply` folds this into an existing state rather than
/// constructing a new one from it.
///
/// `nil` answers are intentional: the engine treats them as unresolved and does not award the
/// conditional bonus.
public struct WalletSetup: Equatable, Sendable {
    public var ownedCardIds: [String]
    public var defaultCardId: String
    /// Boolean owner-condition answers, keyed cardId → conditionId. An absent key is UNANSWERED,
    /// which `RuleMatcher` fails closed on. Never default a missing answer to `false`: "no" and
    /// "not asked" buy the owner different rates and must stay distinguishable.
    public var conditionAnswers: [String: [String: Bool]]
    public var tangerineSelectedCategories: [String]?
    public var switchThreshold: SwitchThreshold
    public var valuationsCad: Valuations
    /// The owner's residency. Nil means unresolved; `OwnerState.resolvedMarket` defaults to `.ca`.
    /// Present here so an edit round-trips it — the previous builder dropped it, silently
    /// resetting every owner to Canada on save.
    public var market: Market?

    public init(ownedCardIds: [String], defaultCardId: String,
                conditionAnswers: [String: [String: Bool]] = [:],
                tangerineSelectedCategories: [String]? = nil,
                switchThreshold: SwitchThreshold,
                valuationsCad: Valuations,
                market: Market? = nil) {
        self.ownedCardIds = ownedCardIds
        self.defaultCardId = defaultCardId
        self.conditionAnswers = conditionAnswers
        self.tangerineSelectedCategories = tangerineSelectedCategories
        self.switchThreshold = switchThreshold
        self.valuationsCad = valuationsCad
        self.market = market
    }
}

/// Pure OwnerState construction belongs in Store, at the boundary between setup answers and the
/// engine.
///
/// The two entry points below exist because the single previous one (`make`) could not tell a
/// first run from an edit. It was a *constructor* — a pure function from setup answers to a brand
/// new `OwnerState` — so everything `WalletSetup` cannot express was structurally guaranteed to be
/// lost on every save: cap progress, carry, market. That is not a missing line, it is the shape of
/// the function, which is why the fix is two functions rather than a patch to one.
public enum OwnerStateBuilder {
    public static let defaultSwitchThreshold = SwitchThreshold(minAdvantagePercentagePoints: 0.5,
                                                               minAdvantageCad: 0.25,
                                                               semantics: "both")

    public static func setup(from ownerState: OwnerState) -> WalletSetup {
        var answers: [String: [String: Bool]] = [:]
        for (cardId, state) in ownerState.cardStates {
            let flags = state.resolvedFlags
            if !flags.isEmpty { answers[cardId] = flags }
        }
        return WalletSetup(
            ownedCardIds: ownerState.ownedCardIds,
            defaultCardId: ownerState.defaultCardId,
            conditionAnswers: answers,
            tangerineSelectedCategories:
                ownerState.cardStates["tangerine-moneyback-world"]?.selectedCategories,
            switchThreshold: ownerState.switchThreshold,
            valuationsCad: ownerState.valuationsCad,
            market: ownerState.market.flatMap(Market.init(rawValue:)))
    }

    /// A wallet built from nothing. Caps start at zero and carry is empty because there is no
    /// history yet — the documented intent of the old `make`, now stated in its name so it can
    /// never be reached from an edit by accident.
    public static func firstRun(setup: WalletSetup, catalogue: Catalogue,
                                version: String = "wallet-setup-1") -> OwnerState {
        apply(setup, to: nil, catalogue: catalogue, version: version)
    }

    /// Fold setup answers INTO an existing wallet. Everything `WalletSetup` cannot express — cap
    /// progress, carry, account anchors, market — is carried across untouched.
    ///
    /// `existing == nil` is first run and reproduces the old `make` exactly.
    public static func apply(_ setup: WalletSetup, to existing: OwnerState?,
                             catalogue: Catalogue,
                             version: String = "wallet-setup-1") -> OwnerState {
        let availableIDs = Set(catalogue.cards.map(\.cardId))
        let owned = Array(NSOrderedSet(array: setup.ownedCardIds))
            .compactMap { $0 as? String }
            .filter { availableIDs.contains($0) }
        let defaultCardId = owned.contains(setup.defaultCardId) ? setup.defaultCardId : (owned.first ?? "")
        var cardStates: [String: CardState] = [:]

        for card in catalogue.cards where owned.contains(card.cardId) {
            // Start from what is already known about this card. A card the owner already held
            // keeps its observations; a newly added one starts clean, which is correct.
            var state = existing?.cardStates[card.cardId] ?? CardState()

            let capIDs = card.caps.map(\.capId)
            if !capIDs.isEmpty {
                var progress = state.capProgress ?? [:]
                // Fill only caps with no figure yet. A cap added to the catalogue since the last
                // save appears at zero; one already tracked keeps its number.
                for capID in capIDs where progress[capID] == nil { progress[capID] = 0 }
                state.capProgress = progress
            }

            let answers = setup.conditionAnswers[card.cardId] ?? [:]
            state.flags = answers.isEmpty ? nil : answers

            if card.cardId == "tangerine-moneyback-world" {
                state.selectedCategories = setup.tangerineSelectedCategories?.isEmpty == false
                    ? setup.tangerineSelectedCategories : nil
            }

            cardStates[card.cardId] = mirroringLegacyFlags(state)
        }

        return OwnerState(ownerStateVersion: existing?.ownerStateVersion ?? version,
                          ownedCardIds: owned,
                          defaultCardId: defaultCardId,
                          switchThreshold: setup.switchThreshold,
                          carry: existing?.carry ?? Carry(drawerCards: []),
                          cardStates: cardStates,
                          valuationsCad: setup.valuationsCad,
                          market: setup.market?.rawValue ?? existing?.market)
    }

    /// Copies the two legacy named booleans back out of `flags`, so an owner state written by
    /// this build stays fully readable by a consumer that predates `flags`. MoneyTalks stores
    /// owner state and has not been audited for which keys it reads. Delete this — and the two
    /// `CardState` properties it writes — once that audit is done.
    static func mirroringLegacyFlags(_ state: CardState) -> CardState {
        var mirrored = state
        mirrored.rogersEligibleServiceLinked = state.flags?["rogersEligibleServiceLinked"]
        mirrored.cryptoLevelUpProActive = state.flags?["cryptoLevelUpProActive"]
        return mirrored
    }
}

// The Phase 0 shim that stood in for `CardState.flags` / `resolvedFlags` is gone: both are real
// stored/computed members of `CardState` as of card-contracts@2.8.

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
