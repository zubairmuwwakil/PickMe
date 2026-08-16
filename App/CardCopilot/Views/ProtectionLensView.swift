import SwiftUI
import CardCopilotEngine

/// The "two runs" screen: declare a planned purchase, see which card earns best
/// and — separately — what each card's certificate says about protecting it.
struct ProtectionLensView: View {
    let deps: CheckoutFlowView.Dependencies
    let initialContext: BenefitContext
    let onDone: () -> Void

    @State private var contextKind: BenefitContextKind
    @State private var abroad: Bool
    @State private var amountText = ""
    @State private var selectedDisclosure: BenefitDisclosure?

    init(deps: CheckoutFlowView.Dependencies,
         initialContext: BenefitContext = BenefitContext(kind: .flight),
         onDone: @escaping () -> Void) {
        self.deps = deps
        self.initialContext = initialContext
        self.onDone = onDone
        _contextKind = State(initialValue: initialContext.kind)
        _abroad = State(initialValue: initialContext.abroad)
    }

    private var context: BenefitContext { BenefitContext(kind: contextKind, abroad: abroad) }

    private var comparison: ProtectionComparison {
        BenefitsAdvisor.comparison(context: context,
                                   wallet: deps.catalogue.cards.map(\.cardId),
                                   catalogue: deps.benefits)
    }

    private var amountCad: Double? {
        Double(amountText.replacingOccurrences(of: "$", with: "")
                         .replacingOccurrences(of: ",", with: ""))
            .flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        List {
            contextSection
            earnSection
            verdictSection
            ForEach(comparison.columns, id: \.cardId) { column in
                cardSection(column)
            }
            absentSection
            Section {
                Text(BenefitsFormatting.certificateFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Big purchase or trip")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
                    .font(.headline)
            }
        }
        .sheet(item: $selectedDisclosure) { disclosure in
            BenefitDetailSheet(disclosure: disclosure, cardName: cardName(disclosure.cardId))
        }
    }

    private var contextSection: some View {
        Section("Purchase Context") {
            Picker("Purchase Type", selection: $contextKind) {
                Label("Flight", systemImage: "airplane").tag(BenefitContextKind.flight)
                Label("Trip / Vacation", systemImage: "suitcase.rolling.fill").tag(BenefitContextKind.trip)
                Label("Car Rental", systemImage: "car.fill").tag(BenefitContextKind.carRental)
                Label("Electronics / Tech", systemImage: "laptopcomputer").tag(BenefitContextKind.electronics)
                Label("Mobile Device", systemImage: "iphone").tag(BenefitContextKind.mobileDevice)
                Label("Appliance & Furniture", systemImage: "sofa.fill").tag(BenefitContextKind.applianceFurniture)
            }

            Toggle("Outside Canada", isOn: $abroad)

            HStack {
                Text("Planned Amount")
                Spacer()
                TextField("Optional ($)", text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// The earn run — computed by the engine directly so nothing is logged.
    @ViewBuilder
    private var earnSection: some View {
        if let amount = amountCad {
            let today = Date().formatted(.iso8601.year().month().day())
            let recommendation = deps.engine.recommend(
                PurchaseContext(amountCad: amount, category: "other"), asOf: today)
            Section("Best Reward Return") {
                HStack(spacing: 12) {
                    CardMiniBadge(cardId: recommendation.winner.cardId, size: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cardName(recommendation.winner.cardId))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text("Earns ≈ $\(String(format: "%.2f", recommendation.winner.netValueCad)) back on $\(Int(amount))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Earn rewards and certificate protections are evaluated separately — the highest earning card may not offer the best insurance coverage.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var verdictSection: some View {
        if comparison.columns.isEmpty {
            Section("Protection Verdict") {
                HStack(spacing: 10) {
                    Image(systemName: "shield.slash")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("No relevant insurance coverage found in your wallet for this category.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } else if let dominant = comparison.dominantCardId {
            Section("Protection Verdict") {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.14))
                            .frame(width: 38, height: 38)
                        Image(systemName: "shield.checkerboard")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.green)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dominant Protection Card")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                        Text("\(cardName(dominant)) equals or beats all other cards on every line below.")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            Section("Protection Verdict") {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.14))
                            .frame(width: 38, height: 38)
                        Image(systemName: "scalemass.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Certificate Trade-Off")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                        Text("No single card dominates every line — compare coverage limits below to decide.")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func cardSection(_ column: ProtectionComparison.Column) -> some View {
        Section {
            ForEach(comparison.relevantKinds, id: \.rawValue) { kind in
                if let disclosure = column.byKind[kind.rawValue] {
                    Button {
                        selectedDisclosure = disclosure
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
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
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack(spacing: 8) {
                CardMiniBadge(cardId: column.cardId, size: 16)
                Text(cardName(column.cardId))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                Text(BenefitsFormatting.verificationLabel(column.verification))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        (column.verification == .certificateVerified ? Color.green : Color.orange).opacity(0.15),
                        in: Capsule()
                    )
                    .foregroundStyle(column.verification == .certificateVerified ? Color.green : Color.orange)
            }
        }
    }

    @ViewBuilder
    private var absentSection: some View {
        if !comparison.absent.isEmpty {
            Section("No Applicable Coverage") {
                ForEach(comparison.absent, id: \.cardId) { absent in
                    HStack {
                        CardMiniBadge(cardId: absent.cardId, size: 16)
                        Text(cardName(absent.cardId))
                            .font(.system(size: 14, weight: .medium))
                        Spacer()
                        Text(absent.verification == .certificateVerified ? "Confirmed No Coverage" : "Unverified")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func cardName(_ cardId: String) -> String {
        deps.catalogue.cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }
}
