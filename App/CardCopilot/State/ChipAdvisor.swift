import Foundation

/// Something Chip has noticed about the app's own health, and where the owner can go to fix it.
///
/// Deliberately App-layer. `ChipInsight` lives in the Engine and its contract is that every case
/// derives from a `Recommendation`, a `PurchaseContext`, or a `CandidateScore` — card semantics,
/// twinned in Kotlin. An empty wallet, a stalled sync and a revoked iOS permission are none of
/// those. They are the states where the app cannot do its job, which is exactly the thing a
/// mascot is worth having: Chip is the only surface that volunteers them unasked.
struct ChipAdvisory: Equatable {
    enum Kind: Equatable {
        case emptyWallet
        case ambient(ChipAmbientAdvisory)
        case syncStalled
    }

    let kind: Kind
    let text: String
    let tag: String
    let actionLabel: String
    let mood: ChipMood
    let destination: Destination
    /// Urgent advisories pin to the front of Chip's queue. The rest take their turn in the
    /// ordinary rotation, so Chip mentions them without nagging.
    let isUrgent: Bool
}

enum ChipAdvisor {

    /// Everything Chip should say about app health, most pressing first.
    ///
    /// Order is a claim about what blocks what. An empty wallet comes first because it stops
    /// checkout advice outright — nothing else matters until there is a card to recommend.
    /// Broken arrival alerts come next because they fail silently and no other surface reports
    /// them unprompted. A stalled sync and an unconfigured feature are last and unpinned: picks
    /// still work offline, and never enabling an optional feature is a choice, not a fault.
    static func evaluate(
        walletIsEmpty: Bool,
        hasSyncIssue: Bool,
        ambientIsEnabled: Bool,
        ambientStatus: AmbientRuntimeStatus
    ) -> [ChipAdvisory] {
        var advisories: [ChipAdvisory] = []

        if walletIsEmpty {
            advisories.append(ChipAdvisory(
                kind: .emptyWallet,
                text: "I've got nothing to work with yet. Add the cards you actually carry and I'll tell you exactly which one to tap at every checkout — I only ever recommend cards you own.",
                tag: "EMPTY WALLET",
                actionLabel: "Add your cards",
                mood: .wink,
                destination: .walletSetup,
                isUrgent: true
            ))
        }

        if let ambient = ChipAmbientAdvisory.evaluate(isEnabled: ambientIsEnabled, status: ambientStatus) {
            advisories.append(ChipAdvisory(
                kind: .ambient(ambient),
                text: ambient.text,
                tag: ambient.tag,
                actionLabel: ambient.actionLabel,
                mood: ambient.mood,
                destination: .ambientSetup,
                isUrgent: ambient.isUrgent
            ))
        }

        if hasSyncIssue {
            advisories.append(ChipAdvisory(
                kind: .syncStalled,
                text: "Couldn't reach PickMe Cloud on the last sync, so your caps might be a little behind. Your card picks still work offline — I just can't promise the cap maths is current.",
                tag: "SYNC STALLED",
                actionLabel: "Check sync",
                mood: .alert,
                destination: .sync,
                isUrgent: false
            ))
        }

        // Partition rather than sort: `sorted` is not stable in Swift, and the order the
        // advisories were appended in above *is* the priority claim.
        return advisories.filter(\.isUrgent) + advisories.filter { !$0.isUrgent }
    }
}
