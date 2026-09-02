import Foundation

/// The order Chip says things in, and which index is currently on deck.
///
/// This lives outside the view because the two worst bugs in Chip's first version were both here
/// and neither was testable while it was view state:
///
/// 1. `quipIndex` was bounds-checked when it was *assigned* but the list it indexes shrinks on its
///    own — `insights` empties whenever the engine has nothing to say. A stale index then trapped.
/// 2. The bubble's tag came from an externally supplied value that nothing ever cleared, so every
///    quip after the first easter egg wore that egg's tag.
///
/// Both are pure functions of their inputs, so they belong here where a test can pin them down.
struct ChipBanterQueue {
    /// Advisories that jump the queue — a broken subsystem outranks any joke or engine insight.
    var pinned: [ChipBanterItem] = []
    /// Typed engine insights about the purchase at hand.
    var insights: [ChipBanterItem] = []
    /// Chip's permanent repertoire of merchant rules and 4th-wall jokes.
    var standing: [ChipBanterItem] = []
    /// Quips that take their turn without demanding attention.
    var rotation: [ChipBanterItem] = []

    var items: [ChipBanterItem] {
        pinned + insights + standing + rotation
    }

    /// The quip at `index`, wrapped into range.
    ///
    /// Wrapping at *read* time rather than trusting the last assignment is the whole fix for the
    /// crash: the list can shrink between the assignment and any of the delayed closures that read
    /// it seconds later.
    func item(at index: Int) -> ChipBanterItem? {
        let list = items
        guard !list.isEmpty else { return nil }
        let wrapped = ((index % list.count) + list.count) % list.count
        return list[wrapped]
    }

    /// The index after `index`, wrapped. Returns 0 for an empty queue.
    func advanced(from index: Int) -> Int {
        let count = items.count
        guard count > 0 else { return 0 }
        return (index + 1) % count
    }

    /// The index before `index`, wrapped. Returns 0 for an empty queue.
    func retreated(from index: Int) -> Int {
        let count = items.count
        guard count > 0 else { return 0 }
        return ((index - 1) % count + count) % count
    }
}

/// Resolves the label above Chip's dialogue.
enum ChipBubbleTag {

    /// The tag for whatever Chip is currently saying.
    ///
    /// `externalTag` wins when present, which is why the caller has to be able to clear it — as a
    /// plain value that nothing reset, it outlived its own reaction and mislabelled every quip
    /// that followed. Everything else is derived from the reaction text itself, so it cannot go
    /// stale independently of what is on screen.
    static func resolve(
        externalTag: String?,
        reactionText: String?,
        fallback: String
    ) -> String {
        if let externalTag, !externalTag.isEmpty {
            return externalTag
        }
        guard let text = reactionText?.lowercased() else {
            return fallback
        }
        if text.contains("founder protocol") { return "FOUNDER PROTOCOL" }
        if text.contains("overclock") { return "OVERCLOCK ENGINE" }
        if text.contains("gyroscope") || text.contains("snowglobe") { return "GYROSCOPE" }
        if text.contains("costco") { return "COSTCO TRAP" }
        if text.contains("voltage") || text.contains("battery") { return "GRID VOLTAGE" }
        if text.contains("maximum effort") { return "MAXIMUM EFFORT" }
        if text.contains("cobalt") { return "HOLY GRAIL" }
        if text.contains("bmo") { return "FIRST CARD" }
        if text.contains("platinum") || text.contains("799") { return "FEE TRAUMA" }
        if text.contains("coffee") || text.contains("matcha") { return "ENERGY CHECK" }
        if text.contains("why pickme") { return "ORIGIN STORY" }
        return "CHIP REACTION"
    }
}
