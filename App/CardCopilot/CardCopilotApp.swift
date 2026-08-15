import SwiftUI
import SwiftData
import CardCopilotStore

@main
struct CardCopilotApp: App {
    var body: some Scene {
        WindowGroup {
            CheckoutFlowView()
        }
        .modelContainer(for: [StoredPrediction.self, StoredObservation.self, StoredMerchant.self])
    }
}
