import SwiftUI
import CardCopilotEngine

/// The "two runs" screen: declare a planned purchase, see which card earns best
/// and — separately — what each card's certificate says about protecting it.
struct ProtectionLensView: View {
    let initialContext: BenefitContext
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var contextKind: BenefitContextKind
    @State private var abroad: Bool
    @State private var amountText = ""
    @State private var tripLengthText = ""
    @State private var rentalDaysText = ""
    @State private var vehicleValueText = ""
    @State private var province = "ON"
    @State private var coverageDateText = ""
    @State private var fullPaymentConfirmed = false
    @State private var selectedDisclosure: BenefitDisclosure?

    init(initialContext: BenefitContext = BenefitContext(kind: .flight)) {
        self.initialContext = initialContext
        _contextKind = State(initialValue: initialContext.kind)
        _abroad = State(initialValue: initialContext.abroad)
    }

    private var context: BenefitContext { BenefitContext(kind: contextKind, abroad: abroad) }

    private var contextTitle: String {
        switch contextKind {
        case .flight: return "Flight & Travel"
        case .trip: return "Trip & Vacation"
        case .carRental: return "Rental Car CDW"
        case .electronics: return "Tech & Electronics"
        case .mobileDevice: return "Mobile Device"
        case .applianceFurniture: return "Appliance & Furniture"
        case .other: return "Everyday / Other"
        }
    }

    private func comparison(for graph: DependencyGraph) -> ProtectionComparison {
        BenefitsAdvisor.comparison(context: context,
                                   wallet: graph.walletCardIds,
                                   catalogue: graph.benefits)
    }

    private var amountCad: Double? {
        Double(amountText.replacingOccurrences(of: "$", with: "")
                         .replacingOccurrences(of: ",", with: ""))
            .flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        if let graph = environment.graph {
            let comparison = comparison(for: graph)

            List {
                scenarioSelectorSection
                scenarioParametersSection
                eligibilityChecklistSection
                earnVsProtectSection(graph: graph, comparison: comparison)
                verdictSection(comparison: comparison, graph: graph)

                ForEach(comparison.columns, id: \.cardId) { column in
                    cardSection(column, comparison: comparison, graph: graph)
                }

                absentSection(comparison: comparison, graph: graph)

                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(BenefitsFormatting.certificateFooter)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(contextTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                }
            }
            .sheet(item: $selectedDisclosure) { disclosure in
                BenefitDetailSheet(disclosure: disclosure, cardName: cardName(disclosure.cardId, graph: graph))
            }
        } else {
            EmptyView()
        }
    }

    // MARK: - Scenario Selector
    private var scenarioSelectorSection: some View {
        Section {
            Picker("Scenario", selection: $contextKind) {
                Label("Flight", systemImage: "airplane").tag(BenefitContextKind.flight)
                Label("Trip / Vacation", systemImage: "suitcase.rolling.fill").tag(BenefitContextKind.trip)
                Label("Rental Car", systemImage: "car.fill").tag(BenefitContextKind.carRental)
                Label("Electronics / Tech", systemImage: "laptopcomputer").tag(BenefitContextKind.electronics)
                Label("Mobile Device", systemImage: "iphone").tag(BenefitContextKind.mobileDevice)
                Label("Appliance & Furniture", systemImage: "sofa.fill").tag(BenefitContextKind.applianceFurniture)
            }
            .pickerStyle(.menu)

            HStack {
                Text("Estimated Amount")
                    .font(.body)
                Spacer()
                HStack(spacing: 2) {
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("Optional", text: $amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(minWidth: 80)
                }
            }
        } header: {
            Text("Declared Purchase")
        } footer: {
            Text("Enter transaction details to simulate limits and compare rewards against insurance coverage.")
        }
    }

    // MARK: - Scenario Parameters & Live Checks
    @ViewBuilder
    private var scenarioParametersSection: some View {
        Section("Scenario Details") {
            if contextKind == .flight || contextKind == .trip {
                Toggle("Outside Canada", isOn: $abroad)

                HStack {
                    Text("Trip Length")
                    Spacer()
                    TextField("Optional", text: $tripLengthText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text("days")
                        .foregroundStyle(.secondary)
                }
            }

            if contextKind == .carRental {
                HStack {
                    Text("Rental Length")
                    Spacer()
                    TextField("Optional", text: $rentalDaysText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text("days")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Vehicle Value")
                    Spacer()
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("Optional", text: $vehicleValueText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text("CAD")
                        .foregroundStyle(.secondary)
                }
            }

            Label(detailPrompt, systemImage: "info.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var eligibilityChecklistSection: some View {
        Section("Eligibility checklist") {
            Picker("Province / territory", selection: $province) {
                ForEach(Self.provinces, id: \.code) { province in
                    Text(province.name).tag(province.code)
                }
            }

            HStack {
                Text("Coverage date")
                Spacer()
                TextField("YYYY-MM-DD", text: $coverageDateText)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
            }

            Toggle("Paid the eligible amount with this card", isOn: $fullPaymentConfirmed)

            Label(fullPaymentConfirmed
                  ? "Payment condition marked complete — still check the certificate exclusions."
                  : "Most benefits require the full eligible purchase to be charged to the card.",
                  systemImage: fullPaymentConfirmed ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(fullPaymentConfirmed ? .green : .orange)

            Text("Province, card version, effective date, and payment method can change eligibility. These inputs are a conservative checklist; they do not override the certificate or rank cards by themselves.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static let provinces: [(code: String, name: String)] = [
        ("AB", "Alberta"), ("BC", "British Columbia"), ("MB", "Manitoba"),
        ("NB", "New Brunswick"), ("NL", "Newfoundland & Labrador"), ("NS", "Nova Scotia"),
        ("NT", "Northwest Territories"), ("NU", "Nunavut"), ("ON", "Ontario"),
        ("PE", "Prince Edward Island"), ("QC", "Quebec"), ("SK", "Saskatchewan"),
        ("YT", "Yukon")
    ]

    private var detailPrompt: String {
        switch contextKind {
        case .flight, .trip:
            return abroad
                ? "Emergency medical coverage actively checked for out-of-country travel."
                : "Travel medical insurance typically applies only to travel outside Canada/province."
        case .carRental:
            return "Compare maximum rental duration, vehicle MSRP ceilings, and deductible waivers below."
        case .electronics, .applianceFurniture:
            return "Purchase protection covers theft/loss (typically 90-120 days) and warranty doubles manufacturer terms."
        case .mobileDevice:
            return "Cell phone insurance requires paying monthly bill or full phone price with the eligible card."
        case .other:
            return "No modelled protection-sensitive scenario applies to this checkout context."
        }
    }

    // MARK: - Earn vs Protect Decision Matrix
    @ViewBuilder
    private func earnVsProtectSection(graph: DependencyGraph, comparison: ProtectionComparison) -> some View {
        if let amount = amountCad {
            let today = Date().formatted(.iso8601.year().month().day())
            if case .advised(let recommendation) = graph.engine.recommend(
                PurchaseContext(amountCad: amount, category: "other"), asOf: today) {

                let earnCardId = recommendation.winner.cardId
                let protectCardId = comparison.dominantCardId

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left.arrow.right.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.indigo)
                            Text("Reward vs. Insurance Strategy")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        }

                        // Split Row: Best Earner vs Best Protector
                        HStack(alignment: .top, spacing: 12) {
                            // Earner Side
                            VStack(alignment: .leading, spacing: 6) {
                                Text("BEST CASH/POINTS")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .tracking(0.6)
                                    .foregroundStyle(.green)

                                HStack(spacing: 6) {
                                    CardMiniBadge(cardId: earnCardId, size: 18)
                                    Text(cardName(earnCardId, graph: graph))
                                        .font(.system(size: 12, weight: .bold, design: .rounded))
                                        .lineLimit(1)
                                }

                                Text("≈ $\(String(format: "%.2f", recommendation.winner.netValueCad)) return")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                            // Protector Side
                            if let dominant = protectCardId {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("BEST PROTECTION")
                                        .font(.system(size: 9, weight: .bold, design: .rounded))
                                        .tracking(0.6)
                                        .foregroundStyle(.indigo)

                                    HStack(spacing: 6) {
                                        CardMiniBadge(cardId: dominant, size: 18)
                                        Text(cardName(dominant, graph: graph))
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .lineLimit(1)
                                    }

                                    Text(dominant == earnCardId ? "Best on both!" : "Dominates coverage")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(dominant == earnCardId ? .green : .indigo)
                                }
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                        }

                        Text("Tip: For low-risk purchases, maximize rewards. For high-stakes flights, rentals, or devices, choose the strongest insurance policy.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Decision Strategy")
                }
            }
        }
    }

    // MARK: - Verdict Section
    @ViewBuilder
    private func verdictSection(comparison: ProtectionComparison, graph: DependencyGraph) -> some View {
        if comparison.columns.isEmpty {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "shield.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No Listed Coverage")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                        Text("No wallet cards have policy data for this scenario category.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Protection Verdict")
            }
        } else if let dominant = comparison.dominantCardId {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.16))
                            .frame(width: 42, height: 42)
                        Image(systemName: "shield.checkerboard")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.green)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Dominant Protection Card")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                        Text("\(cardName(dominant, graph: graph))")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Equals or beats every other card on all displayed coverage lines.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Protection Verdict")
            }
        } else {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.16))
                            .frame(width: 42, height: 42)
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Certificate Trade-Off")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                        Text("No single card dominates every line")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("Compare specific limit lines below (e.g. medical limits vs delay payout).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Protection Verdict")
            }
        }
    }

    // MARK: - Card Breakdown Section
    private func cardSection(_ column: ProtectionComparison.Column, comparison: ProtectionComparison,
                             graph: DependencyGraph) -> some View {
        Section {
            // Coverage Status Subhead
            HStack(spacing: 8) {
                Image(systemName: column.verification == .certificateVerified ? "checkmark.seal.fill" : "doc.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(column.verification == .certificateVerified ? .green : .blue)
                Text(coverageSummary(column, comparison: comparison))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Potential Mismatch Warning
            if let note = potentialMismatch(for: column) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(note)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, 2)
            }

            // Policy Lines
            ForEach(comparison.relevantKinds, id: \.rawValue) { kind in
                if let disclosure = column.byKind[kind.rawValue] {
                    Button {
                        selectedDisclosure = disclosure
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(BenefitsFormatting.kindDisplayName(kind.rawValue))
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)

                                Text(BenefitsFormatting.factsLine(for: disclosure.coverage, kind: kind.rawValue))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack(spacing: 8) {
                CardMiniBadge(cardId: column.cardId, size: 18)
                Text(cardName(column.cardId, graph: graph))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                Text(BenefitsFormatting.verificationLabel(column.verification))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        (column.verification == .certificateVerified ? Color.green : Color.blue).opacity(0.14),
                        in: Capsule()
                    )
                    .foregroundStyle(column.verification == .certificateVerified ? Color.green : Color.blue)
            }
        }
    }

    private func coverageSummary(_ column: ProtectionComparison.Column,
                                 comparison: ProtectionComparison) -> String {
        let listed = column.byKind.count
        if column.verification == .stub {
            return "\(listed) listed line\(listed == 1 ? "" : "s") · unverified draft"
        }
        if listed == comparison.relevantKinds.count {
            return "Complete coverage · all \(listed) relevant lines listed"
        }
        return "\(listed) of \(comparison.relevantKinds.count) scenario lines covered"
    }

    private func potentialMismatch(for column: ProtectionComparison.Column) -> String? {
        if (contextKind == .flight || contextKind == .trip),
           let days = Int(tripLengthText),
           column.byKind.values.contains(where: { coverage in
               if let limit = coverage.coverage.maxTripLengthDays { return days > limit }
               return false
           }) {
            return "Trip length (\(days) days) exceeds card policy limit"
        }

        if contextKind == .carRental {
            if let days = Int(rentalDaysText), column.byKind.values.contains(where: {
                if let limit = $0.coverage.maxRentalDays { return days > limit }
                return false
            }) {
                return "Rental length (\(days) days) exceeds max rental limit"
            }
            if let value = Double(vehicleValueText.replacingOccurrences(of: ",", with: "")),
               column.byKind.values.contains(where: {
                   if let limit = $0.coverage.maxVehicleValueCad { return value > limit }
                   return false
               }) {
                return "Vehicle value exceeds policy ceiling"
            }
        }

        if let amount = amountCad,
           (contextKind == .electronics || contextKind == .mobileDevice || contextKind == .applianceFurniture),
           column.byKind.values.contains(where: {
               let limit = $0.coverage.maxPerOccurrenceCad ?? $0.coverage.maxCad
               return limit.map { amount > $0 } ?? false
           }) {
            return "Purchase amount exceeds per-occurrence limit"
        }
        return nil
    }

    // MARK: - Absent Section
    @ViewBuilder
    private func absentSection(comparison: ProtectionComparison, graph: DependencyGraph) -> some View {
        if !comparison.absent.isEmpty {
            Section("No Applicable Coverage in Wallet") {
                ForEach(comparison.absent, id: \.cardId) { absent in
                    HStack(spacing: 10) {
                        CardMiniBadge(cardId: absent.cardId, size: 16)
                        Text(cardName(absent.cardId, graph: graph))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(absent.verification == .certificateVerified ? "No listed coverage" : "Unverified")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func cardName(_ cardId: String, graph: DependencyGraph) -> String {
        graph.catalogue.cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }
}
