import SwiftUI
import SwiftData
import CardCopilotStore
import ClerkKit

@main
struct CardCopilotApp: App {
    @UIApplicationDelegateAdaptor(CardCopilotAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var sync = SyncCoordinator()
    @State private var session = CopilotSession()
    @State private var router = CheckoutRouter()

    init() {
        if MoneyTalksConfiguration.isConfigured,
           let publishableKey = MoneyTalksConfiguration.clerkPublishableKey,
           publishableKey.hasPrefix("pk_") {
            Clerk.configure(publishableKey: publishableKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if MoneyTalksConfiguration.isConfigured {
                    CheckoutFlowView()
                        .environment(Clerk.shared)
                } else {
                    CheckoutFlowView()
                }
            }
            .environment(sync)
            .environment(session)
            .environment(router)
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                CommunityMerchantMCCSettingsStore().reconcileConsent()
                CommunityGiftCardInventorySettingsStore().reconcileConsent()
            }
        }
        .modelContainer(Self.sharedModelContainer)
    }

    /// Built from `CardCopilotSchema.current` rather than from a literal list of model types, and
    /// rather than from a version named literally.
    ///
    /// The literal list was a second copy of the schema's `models` that nothing kept in step:
    /// adding an eighth model and forgetting this line would compile, pass every test that
    /// builds its own container, and then have no table for the new type on a real device.
    ///
    /// Naming a version here would fail the same way. A container is keyed by the model *types* in
    /// its schema, so once the typealiased `StoredPrediction` moved to V2, a container still opened
    /// at V1 would hold V1's frozen classes and have no table for the type the app actually
    /// inserts — and, being a valid V1 container, would never run the V1→V2 stage at all. That
    /// mistake compiles, passes every test that builds its own container, and surfaces only on a
    /// device with a real store. `CardCopilotSchema.current` is the single name that moves.
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
                for: Schema(versionedSchema: CardCopilotSchema.current),
                migrationPlan: CardCopilotMigrationPlan.self)
        } catch {
            fatalError("Could not open the CardCopilot store at the current schema: \(error)")
        }
    }()
}
