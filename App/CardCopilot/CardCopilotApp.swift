import SwiftUI
import SwiftData
import CardCopilotStore
import ClerkKit

@main
struct CardCopilotApp: App {
    @UIApplicationDelegateAdaptor(CardCopilotAppDelegate.self) private var appDelegate
    init() {
        if let publishableKey = MoneyTalksConfiguration.clerkPublishableKey,
           publishableKey.hasPrefix("pk_") {
            Clerk.configure(publishableKey: publishableKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            if MoneyTalksConfiguration.isConfigured {
                CheckoutFlowView()
                    .environment(Clerk.shared)
            } else {
                CheckoutFlowView()
            }
        }
        .modelContainer(for: [StoredPrediction.self, StoredPurchase.self, StoredObservation.self, StoredMerchant.self,
               ExploredCell.self, ShoppingArea.self, AreaMember.self])
    }
}
