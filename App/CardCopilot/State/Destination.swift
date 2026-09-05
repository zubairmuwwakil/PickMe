import Foundation
import CardCopilotEngine
import CardCopilotStore

/// A screen the owner navigates to and can come back from.
///
/// Separate from `CheckoutStep` because these two things have different rules and were
/// previously one 19-case `Stage` enum. A destination is pushed onto a navigation stack: it
/// animates in, back-swipe works, and popping it returns you exactly where you were. That is
/// why every one of these used to need its own `onDone: { stage = .idle }` closure — thirteen
/// hand-written copies of what a NavigationStack does for free.
enum Destination: Hashable {
    case finish
    case reconcile
    case dashboard
    case protectionLens(BenefitContext)
    case benefitsReference
    case categoryPicker(String?)
    case walletHealth
    case valuationSandbox
    case sync
    case settings
    case walletSetup
    case ambientSetup
    case arrivalPlaces
    case learnedMerchants
    case merchantMCCDecisionQuality
}

/// Where the owner is in the act of paying for something.
///
/// Deliberately NOT a navigation stack. These steps replace one another: backing out of a
/// recommendation must return to idle, never to `.locating`, and no step here should be
/// reachable with a back-swipe. Modelling them as pushable destinations is what made the old
/// `Stage` enum incoherent.
///
/// `recommendation` carries a `CheckoutResult`, which is `Sendable` but not `Hashable` — a
/// second reason these cannot live in a navigation path.
///
/// No `.amount` step (removed 2026-08-31): confirming a merchant scores straight to
/// `.recommendation` using a category estimate, and the owner refines that estimate in place on
/// the answer screen (`AmountRefineRow`) rather than at a gate before it.
enum CheckoutStep {
    case idle
    case locating
    case confirming([NearbyPlace])
    case recommendation(CheckoutResult)
    /// Reserved for genuine checkout dead ends — nothing nearby, an empty search. Operational
    /// failures (a SwiftData write, a sync call) go to `CopilotSession.lastError` and surface
    /// as an alert, because losing the owner's place mid-reconcile to report a write failure
    /// is a bug, not error handling.
    case failed(String)
}
