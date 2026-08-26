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
        .modelContainer(Self.sharedModelContainer)
    }

    /// Built from `CardCopilotSchemaV1` rather than from a literal list of model types.
    ///
    /// The literal list was a second copy of `CardCopilotSchemaV1.models` that nothing kept in
    /// step: adding an eighth model and forgetting this line would compile, pass every test that
    /// builds its own container, and then have no table for the new type on a real device.
    ///
    /// Naming a migration plan is the substantive change. Without one, SwiftData attempts an
    /// implicit lightweight migration and refuses to open the store when the shape has moved
    /// beyond what that covers — which is every rename and retype. With one, each future version
    /// arrives with a declared `MigrationStage` describing how owners are carried across.
    ///
    /// Trapping on failure preserves the existing behaviour: `.modelContainer(for:)` already
    /// fatalError'd internally if the container could not be opened. The alternative — falling
    /// back to a fresh store — would silently discard the prediction log, which is the append-only
    /// record the accuracy claim is measured against and cannot be recomputed from anything else.
    private static let sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(
                for: Schema(versionedSchema: CardCopilotSchemaV1.self),
                migrationPlan: CardCopilotMigrationPlan.self)
        } catch {
            fatalError("Could not open the CardCopilot store at schema V1: \(error)")
        }
    }()
}
