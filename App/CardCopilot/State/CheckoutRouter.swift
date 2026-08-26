import Foundation
import Observation

/// Owns where the owner is: which tab, what is pushed, and where they are in the act of paying.
///
/// Holds no dependencies and performs no I/O. That is deliberate — the previous design had
/// navigation state living beside MapKit calls and SwiftData writes in one view, so no part of
/// it could be exercised without a simulator.
@Observable
@MainActor
final class CheckoutRouter {
    /// The pushed stack for the current tab. Bound directly to `NavigationStack(path:)`.
    var path: [Destination] = []

    /// Where the owner is in the checkout flow. Replace-style: assigning a new step discards
    /// the previous one, which is why this is not part of `path`.
    var step: CheckoutStep = .idle

    private(set) var selectedTab: AppTab = .copilot

    func push(_ destination: Destination) {
        path.append(destination)
    }

    /// Safe on an empty path: a double-tapped back button must not crash.
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path.removeAll()
    }

    /// Clearing the path is load-bearing, not tidiness: a stack pushed from one tab would
    /// otherwise still be showing when the owner selects another.
    func selectTab(_ tab: AppTab) {
        selectedTab = tab
        path.removeAll()
    }

    func resetToIdle() {
        step = .idle
    }
}
