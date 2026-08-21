import CardCopilotEngine
import Foundation

public enum WalletSetupPersistenceOutcome: Equatable, Sendable {
    case savedLocally
    case savedLocallyAwaitingAccountBinding(userID: String)
    case savedAndQueued(userID: String)
    case accountMismatch(activeUserID: String, signedInUserID: String)
}

/// Applies wallet setup without letting an unavailable account-binding request block the
/// device's offline-first wallet. Account-scoped writes still require an established binding.
public struct WalletSetupPersistence: Sendable {
    private let accountStore: AccountOwnerStateStore
    private let uploadQueue: OwnerStateUploadQueue
    private let cardRequestQueue: CardRequestQueue

    public init(accountStore: AccountOwnerStateStore, uploadQueue: OwnerStateUploadQueue,
                cardRequestQueue: CardRequestQueue) {
        self.accountStore = accountStore
        self.uploadQueue = uploadQueue
        self.cardRequestQueue = cardRequestQueue
    }

    public func save(_ ownerState: OwnerState, signedInUserID: String?,
                     preparedSetupUserID: String?) throws -> WalletSetupPersistenceOutcome {
        if let signedInUserID, accountStore.activeUserID == nil {
            guard preparedSetupUserID == signedInUserID else {
                try accountStore.updateActive(ownerState)
                return .savedLocallyAwaitingAccountBinding(userID: signedInUserID)
            }

            try accountStore.activate(ownerState, forUserID: signedInUserID)
            try uploadQueue.enqueue(ownerState, forUserID: signedInUserID)
            cardRequestQueue.claimUnscopedRequests(forUserID: signedInUserID)
            return .savedAndQueued(userID: signedInUserID)
        }

        if let activeUserID = accountStore.activeUserID {
            if let signedInUserID, signedInUserID != activeUserID {
                return .accountMismatch(activeUserID: activeUserID, signedInUserID: signedInUserID)
            }

            try accountStore.updateActive(ownerState)
            try uploadQueue.enqueue(ownerState, forUserID: activeUserID)
            return .savedAndQueued(userID: activeUserID)
        }

        try accountStore.updateActive(ownerState)
        return .savedLocally
    }
}
