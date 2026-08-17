import Foundation
import SwiftData

/// Erases everything the app keeps on this device.
///
/// Deleting a PickMe account removes what the server holds; it says nothing about the local
/// store, which never left the phone in the first place. That makes the local wipe a separate,
/// explicit choice rather than a side effect — the prediction log is the owner's own record of
/// what the app advised and what actually happened, and destroying it silently would destroy the
/// only evidence the experiment has.
///
/// The merchant rows go with the log deliberately: they carry the coordinates of places the owner
/// shopped, so a "wipe" that spared them would leave the most sensitive local data behind.
public struct LocalDataEraser {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func eraseLocalHistory() throws {
        // Observations cascade from their predictions, but orphans are deleted explicitly rather
        // than assumed impossible.
        try context.delete(model: StoredObservation.self)
        try context.delete(model: StoredPrediction.self)
        try context.delete(model: StoredMerchant.self)
        try context.save()
    }
}
