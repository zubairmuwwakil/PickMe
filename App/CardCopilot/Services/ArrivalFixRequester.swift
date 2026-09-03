import CardCopilotStore
import Foundation

/// Holds an arrival open until iOS answers "where is the owner", or until the wake runs out of
/// patience.
///
/// The class comment on `AmbientLocationService` has always claimed that which shop the owner is
/// in "gets resolved on arrival, from a fresh fix". No fix was ever requested, so resolution ran
/// on the area centroid and on the order `clusterIntoAreas` happened to leave its members in.
/// This is the missing half.
///
/// Split out of the service, and free of CoreLocation, because all three outcomes need pinning
/// and only one of them is convenient to reach through a real `CLLocationManager`: the fix lands,
/// the fix never lands, the fix lands after the arrival has already been answered. A background
/// region wake is short — the timeout is the contract, not a safety net.
@MainActor
final class ArrivalFixRequester {
    private let timeout: Duration
    /// Asks the platform for one fix. Injected so the state machine above can be tested without a
    /// location manager, and so the caller keeps ownership of *which* manager is asked — arrival
    /// fixes must not arrive on the same delegate path as significant-change updates.
    private let start: @MainActor () -> Void

    private var waiters: [CheckedContinuation<ArrivalFix?, Never>] = []
    private var timeoutTask: Task<Void, Never>?

    /// How many arrivals were answered without a fix because the window closed first. Recorded
    /// rather than merely tolerated: a build where this is most arrivals is one where the
    /// resolution work below it is measuring nothing.
    private(set) var timeouts = 0

    /// How many arrivals are currently sharing the outstanding request. Kept read-only so the
    /// request can be diagnosed without exposing its continuations or mutable state.
    var waiterCount: Int { waiters.count }

    init(timeout: Duration = .seconds(5), start: @escaping @MainActor () -> Void) {
        self.timeout = timeout
        self.start = start
    }

    /// Suspends until a fix lands, a failure is reported, or the window closes. Never throws and
    /// never hangs: `nil` is a complete answer meaning "resolve exactly as you did before fixes
    /// existed".
    func fix() async -> ArrivalFix? {
        // Several storefronts in one plaza can wake several arrivals inside one window. They join
        // the outstanding request instead of each asking iOS for a fix of its own, which on a
        // background wake is the difference between one GPS spin-up and five.
        if waiters.isEmpty {
            start()
            armTimeout()
        }
        return await withCheckedContinuation { waiters.append($0) }
    }

    func deliver(_ fix: ArrivalFix) {
        // A fix that arrives after the window closed resolves nothing. The arrival it was
        // requested for has already been answered, and answering it twice would mean either a
        // second notification or a crashed continuation.
        guard !waiters.isEmpty else { return }
        resumeAll(with: fix)
    }

    /// A CoreLocation error is the same answer as an expiry — no fix — and is delivered
    /// immediately rather than making the arrival wait out a window nothing will arrive in.
    func fail() {
        guard !waiters.isEmpty else { return }
        resumeAll(with: nil)
    }

    private func armTimeout() {
        timeoutTask?.cancel()
        let window = timeout
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: window)
            guard !Task.isCancelled, let self, !self.waiters.isEmpty else { return }
            self.timeouts += 1
            self.resumeAll(with: nil)
        }
    }

    private func resumeAll(with fix: ArrivalFix?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let pending = waiters
        waiters = []
        for waiter in pending { waiter.resume(returning: fix) }
    }
}
