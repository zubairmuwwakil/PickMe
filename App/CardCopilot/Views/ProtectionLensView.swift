import SwiftUI
import CardCopilotEngine

/// The "two runs" screen (spec §6.2): declare a planned purchase, see which card earns best
/// and — separately — what each card's certificate says about protecting it. The two rankings
/// are never merged; when certificates genuinely trade off, the screen says so instead of
/// hiding the judgement inside a weight nobody chose (spec B7).
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
        .navigationTitle("Big purchase or trip")
        .toolbar { Button("Done") { onDone() } }
        .sheet(item: $selectedDisclosure) { disclosure in
            BenefitDetailSheet(disclosure: disclosure, cardName: cardName(disclosure.cardId))
        }
    }

    private var contextSection: some View {
        Section("What are you buying?") {
            Picker("Kind", selection: $contextKind) {
                Text("Flight").tag(BenefitContextKind.flight)
                Text("Trip").tag(BenefitContextKind.trip)
                Text("Car rental").tag(BenefitContextKind.carRental)
                Text("Electronics").tag(BenefitContextKind.electronics)
                Text("Phone").tag(BenefitContextKind.mobileDevice)
                Text("Appliance/furniture").tag(BenefitContextKind.applianceFurniture)
            }
            Toggle("Outside Canada", isOn: $abroad)
            TextField("Amount (optional)", text: $amountText)
                .keyboardType(.decimalPad)
        }
    }

    /// The earn run — computed by the engine directly so nothing is logged (spec B9).
    @ViewBuilder
    private var earnSection: some View {
        if let amount = amountCad {
            let today = Date().formatted(.iso8601.year().month().day())
            let recommendation = deps.engine.recommend(
                PurchaseContext(amountCad: amount, category: "other"), asOf: today)
            Section("Best earn") {
                LabeledContent(cardName(recommendation.winner.cardId),
                               value: String(format: "≈ $%.2f back", recommendation.winner.netValueCad))
                Text("Earn and protection are separate calls — the best earner isn't always the best protector.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var verdictSection: some View {
        if comparison.columns.isEmpty {
            Section("Protection") {
                Text("No relevant coverage found in your wallet for this purchase kind.")
                    .foregroundStyle(.secondary)
            }
        } else if let dominant = comparison.dominantCardId {
            Section("Protection") {
                Label("\(cardName(dominant)) — equal or better on every line below",
                      systemImage: "shield.checkerboard")
                    .font(.headline)
            }
        } else {
            Section("Protection") {
                Label("Trade-off — your call. No card wins every line below.",
                      systemImage: "scalemass")
                    .font(.headline)
            }
        }
    }

    private func cardSection(_ column: ProtectionComparison.Column) -> some View {
        Section {
            ForEach(comparison.relevantKinds, id: \.rawValue) { kind in
                if let disclosure = column.byKind[kind.rawValue] {
                    Button { selectedDisclosure = disclosure } label: {
                        LabeledContent(BenefitsFormatting.kindDisplayName(kind.rawValue),
                                       value: BenefitsFormatting.factsLine(for: disclosure.coverage,
                                                                           kind: kind.rawValue))
                            .font(.footnote)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Text(cardName(column.cardId))
                Spacer()
                Text(BenefitsFormatting.verificationLabel(column.verification))
                    .font(.caption2)
                    .foregroundStyle(column.verification == .certificateVerified ? .green : .orange)
            }
        }
    }

    /// Spec B8: absence only means "no coverage" once the certificate proved the negative.
    @ViewBuilder
    private var absentSection: some View {
        if !comparison.absent.isEmpty {
            Section("Not covering this") {
                ForEach(comparison.absent, id: \.cardId) { absent in
                    LabeledContent(cardName(absent.cardId),
                                   value: absent.verification == .certificateVerified
                                       ? "No coverage"
                                       : "Unknown — unverified")
                        .font(.footnote)
                }
            }
        }
    }

    private func cardName(_ cardId: String) -> String {
        deps.catalogue.cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }
}
