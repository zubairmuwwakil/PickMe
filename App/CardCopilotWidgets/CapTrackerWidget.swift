import WidgetKit
import SwiftUI
import CardCopilotEngine
import CardCopilotStore

public struct CapTrackerEntry: TimelineEntry {
    public let date: Date
    public let primaryCardName: String
    public let primaryCapName: String
    public let spentCad: Double
    public let limitCad: Double
    public let remainingCad: Double
    public let percentRemaining: Double
    public let additionalCaps: [(card: String, name: String, spent: Double, limit: Double, remaining: Double)]

    public static var placeholder: CapTrackerEntry {
        CapTrackerEntry(
            date: Date(),
            primaryCardName: "Amex Cobalt",
            primaryCapName: "5× Eats & Drinks",
            spentCad: 850,
            limitCad: 2500,
            remainingCad: 1650,
            percentRemaining: 0.66,
            additionalCaps: [
                (card: "Scotiabank Gold", name: "6× Grocery", spent: 7800, limit: 50000, remaining: 42200)
            ]
        )
    }
}

public struct CapTrackerProvider: TimelineProvider {
    public init() {}

    public func placeholder(in context: Context) -> CapTrackerEntry {
        .placeholder
    }

    public func getSnapshot(in context: Context, completion: @escaping (CapTrackerEntry) -> Void) {
        completion(loadEntry())
    }

    public func getTimeline(in context: Context, completion: @escaping (Timeline<CapTrackerEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> CapTrackerEntry {
        let ownerState = OwnerStateLocalStore().load()
        let catalogue = (try? SeedLoader.loadCatalogue()) ?? Catalogue.empty

        var allCaps: [(card: String, name: String, spent: Double, limit: Double, remaining: Double)] = []

        if let ownerState {
            for cardId in ownerState.ownedCardIds {
                guard let card = catalogue.cards.first(where: { $0.cardId == cardId }) else { continue }
                let state = ownerState.cardStates[cardId]
                for cap in card.caps {
                    let spent = state?.capProgress?[cap.capId] ?? 0
                    let limit = cap.limit
                    let remaining = max(0, limit - spent)
                    let capName = cap.capId.replacingOccurrences(of: "-", with: " ").capitalized
                    allCaps.append((card: card.officialName, name: capName, spent: spent, limit: limit, remaining: remaining))
                }
            }
        }

        if allCaps.isEmpty {
            return .placeholder
        }

        let primary = allCaps[0]
        let pct = primary.limit > 0 ? (primary.remaining / primary.limit) : 1.0
        let others = Array(allCaps.dropFirst())

        return CapTrackerEntry(
            date: Date(),
            primaryCardName: primary.card,
            primaryCapName: primary.name,
            spentCad: primary.spent,
            limitCad: primary.limit,
            remainingCad: primary.remaining,
            percentRemaining: pct,
            additionalCaps: others
        )
    }
}

public struct CapTrackerWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: CapTrackerEntry

    public init(entry: CapTrackerEntry) {
        self.entry = entry
    }

    public var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .accessoryCircular:
            circularComplication
        case .accessoryRectangular:
            rectangularComplication
        case .accessoryInline:
            inlineComplication
        default:
            smallView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "creditcard.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text(entry.primaryCardName)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Spacer()
            }

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "$%.0f", entry.remainingCad))
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.green)
                Text("left at \(entry.primaryCapName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ProgressView(value: 1.0 - entry.percentRemaining)
                .tint(.blue)
        }
        .padding(12)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Card Spending Caps", systemImage: "gauge.with.needle.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                Spacer()
                Text(entry.date.formatted(.dateTime.month().day()))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            capRow(card: entry.primaryCardName, name: entry.primaryCapName,
                   remaining: entry.remainingCad, limit: entry.limitCad,
                   pct: entry.percentRemaining)

            if let second = entry.additionalCaps.first {
                Divider()
                let secondPct = second.limit > 0 ? (second.remaining / second.limit) : 1.0
                capRow(card: second.card, name: second.name,
                       remaining: second.remaining, limit: second.limit,
                       pct: secondPct)
            }
        }
        .padding(14)
    }

    private func capRow(card: String, name: String, remaining: Double, limit: Double, pct: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(card)
                    .font(.system(size: 13, weight: .semibold))
                Text("• \(name)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "$%.0f left", remaining))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
            }
            ProgressView(value: 1.0 - pct)
                .tint(.blue)
        }
    }

    private var circularComplication: some View {
        Gauge(value: entry.percentRemaining, in: 0...1) {
            Image(systemName: "creditcard.fill")
        } currentValueLabel: {
            Text(String(format: "%.0f%%", entry.percentRemaining * 100))
                .font(.system(size: 10, weight: .bold))
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangularComplication: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "creditcard.fill")
                    .font(.caption2)
                Text(entry.primaryCardName)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(String(format: "$%.0f left at %@", entry.remainingCad, entry.primaryCapName))
                .font(.system(size: 12, weight: .medium))
            ProgressView(value: 1.0 - entry.percentRemaining)
        }
    }

    private var inlineComplication: some View {
        Text(String(format: "%@: $%.0f 5× cap room", entry.primaryCardName, entry.remainingCad))
    }
}

public struct CapTrackerWidget: Widget {
    public let kind: String = "CapTrackerWidget"

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CapTrackerProvider()) { entry in
            CapTrackerWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color(.secondarySystemBackground) }
        }
        .configurationDisplayName("Spending Cap Tracker")
        .description("Track remaining monthly 5× and 6× spending caps on your cards.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
