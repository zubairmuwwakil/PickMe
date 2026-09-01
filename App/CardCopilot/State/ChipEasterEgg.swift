import SwiftUI

/// The keyword-triggered personality beats Chip can perform.
///
/// Two surfaces need the same table: the Home search dropdown, which offers the beat as a
/// tappable row, and the mascot itself, which changes face while you are still typing. Keeping
/// the table here rather than in either view means there is one set of trigger words to keep
/// honest, and `match(_:)` is a pure function the test suite can pin down.
enum ChipEasterEgg: String, CaseIterable {
    case origin
    case founder
    case cobalt
    case bmo
    case platinum
    case matcha
    case maximumEffort

    /// Words that summon the beat.
    ///
    /// A trigger of three characters or fewer must match a whole typed word; a longer one may
    /// match a word's prefix. That rule is the whole reason "PC Optimum" no longer trips the
    /// coffee joke — `tim` is short, so op-`tim`-um is not a match, while `platinum` is long
    /// enough to still catch "platinums". Substring matching over the raw query, which is what
    /// this replaced, had no way to tell those two cases apart.
    private var triggers: [String] {
        switch self {
        case .origin: return ["why", "pickme"]
        case .founder: return ["founder", "zubair", "creator"]
        case .cobalt: return ["cobalt"]
        case .bmo: return ["bmo"]
        case .platinum: return ["platinum"]
        case .matcha: return ["coffee", "starbucks", "tim", "tims", "timmies", "timhortons"]
        case .maximumEffort: return ["deadpool"]
        }
    }

    /// Multi-word triggers, matched against the whole normalized query rather than a single word.
    private var phraseTriggers: [String] {
        switch self {
        case .origin: return ["pick me"]
        case .maximumEffort: return ["maximum effort"]
        default: return []
        }
    }

    /// The first beat whose triggers the query satisfies, or `nil` for an ordinary search.
    static func match(_ query: String) -> ChipEasterEgg? {
        let normalized = query
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let words = normalized.split(separator: " ").map(String.init)

        return allCases.first { egg in
            if egg.phraseTriggers.contains(where: { normalized.contains($0) }) { return true }
            return egg.triggers.contains { trigger in
                words.contains { word in
                    trigger.count <= 3 ? word == trigger : word.hasPrefix(trigger)
                }
            }
        }
    }

    // MARK: - Presentation

    /// The face Chip pulls while the trigger is still in the search field.
    var mood: ChipMood {
        switch self {
        case .origin: return .calculating
        case .founder, .cobalt: return .celebrating
        case .bmo: return .wink
        case .platinum: return .shocked
        case .matcha: return .alert
        case .maximumEffort: return .cool
        }
    }

    var title: String {
        switch self {
        case .origin: return "Why PickMe?"
        case .founder: return "Zubair Muwwakil"
        case .cobalt: return "Amex Cobalt Card"
        case .bmo: return "BMO CashBack Mastercard"
        case .platinum: return "Amex Platinum Card"
        case .matcha: return "Coffee Spot Finder: 404"
        case .maximumEffort: return "Maximum Effort Mode"
        }
    }

    var subtitle: String {
        switch self {
        case .origin: return "Because mental math at checkout is painful. We automate 5x multipliers."
        case .founder: return "PickMe creator · Built to rescue Canadians from 1x multiplier traps."
        case .cobalt: return "The 5x holy grail on groceries & dining. Sacred Canadian points math."
        case .bmo: return "The founder's first credit card. From humble roots to points mastery."
        case .platinum: return "Most regretted annual fee ($799)! Hope you used that dining credit."
        case .matcha: return "No coffee here. Rerouting you to bubble tea & matcha instead."
        case .maximumEffort: return "Chip & you: the best rewards duo in the multiverse."
        }
    }

    var tag: String {
        switch self {
        case .origin: return "ORIGIN STORY"
        case .founder: return "FOUNDER"
        case .cobalt: return "5X WINNER"
        case .bmo: return "FIRST CARD"
        case .platinum: return "FEE TRAUMA"
        case .matcha: return "MATCHA MODE"
        case .maximumEffort: return "CINEMATIC"
        }
    }

    var iconName: String {
        switch self {
        case .origin: return "sparkles"
        case .founder: return "crown.fill"
        case .cobalt: return "flame.fill"
        case .bmo: return "star.fill"
        case .platinum: return "creditcard.trianglebadge.exclamationmark"
        case .matcha: return "cup.and.saucer.fill"
        case .maximumEffort: return "theatermasks.fill"
        }
    }

    var tint: Color {
        switch self {
        case .origin: return .blue
        case .founder: return .orange
        case .cobalt: return .blue
        case .bmo: return .cyan
        case .platinum: return .purple
        case .matcha: return .green
        case .maximumEffort: return .red
        }
    }

    /// What Chip actually says once the beat is tapped.
    var dialogue: String {
        switch self {
        case .origin:
            return "Why PickMe? Because life is too short to do interchange arithmetic at the register. We calculate the exact multiplier so you always walk away with maximum points."
        case .founder:
            return "Founder Protocol active! Built by Zubair Muwwakil in Canada to save cardholders from confusing reward rules and sneaky interchange traps."
        case .cobalt:
            return "All hail the holy grail of Canadian multipliers! Amex Cobalt earning 5x on dining & groceries is the cornerstone of any legendary points portfolio."
        case .bmo:
            return "Baby's first credit card: the BMO CashBack Mastercard. Humble beginnings, but look at us now, running algorithmic multi-card optimization."
        case .platinum:
            return "Oof... that $799 annual fee still gives me digital chills. Unless you live in airport lounges, keep those multiplier cards on top!"
        case .matcha:
            return "Coffee recommendations? Error 404: this copilot runs on matcha. Rerouting coordinates to the nearest bubble tea spot instead!"
        case .maximumEffort:
            return "Maximum Effort mode engaged! Look at us: you, me, and a 5x multiplier. Best cinematic point-hacking duo in history."
        }
    }
}
