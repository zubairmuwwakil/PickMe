import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// An interactive "What-If" Point Valuation Sandbox.
/// Allows the user to experiment with different cents-per-point valuations (Amex MR, Aeroplan,
/// Scene+, Avion) and visually observe where credit card recommendations flip against cash back.
struct ValuationSandboxView: View {
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss

    @State private var amexMrCents: Double = 1.8
    @State private var aeroplanCents: Double = 2.0
    @State private var scenePlusCents: Double = 1.0
    @State private var avionCents: Double = 1.5

    private struct SimulationSample: Identifiable {
        let id: String
        let label: String
        let category: String
        let amountCad: Double
        let icon: String
    }

    private let samples: [SimulationSample] = [
        .init(id: "coffee", label: "Coffee", category: "dining", amountCad: 6.00, icon: "cup.and.saucer.fill"),
        .init(id: "dining", label: "Restaurant", category: "dining", amountCad: 50.00, icon: "fork.knife"),
        .init(id: "grocery", label: "Groceries", category: "grocery", amountCad: 140.00, icon: "cart.fill"),
        .init(id: "gas", label: "Gas Fill-up", category: "gasStation", amountCad: 70.00, icon: "fuelpump.fill"),
        .init(id: "flight", label: "Flight Booking", category: "travel", amountCad: 600.00, icon: "airplane"),
        .init(id: "shopping", label: "General Shopping", category: "other", amountCad: 100.00, icon: "bag.fill"),
    ]

    var body: some View {
        if let graph = environment.graph {
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                explainerBanner
                valuationSlidersCard
                simulationResultsSection(graph: graph)
            }
            .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Point Valuation Sandbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(.headline)
                }
            }
        } else {
            EmptyView()
        }
    }

    private var explainerBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("What-If Sensitivity Sandbox", systemImage: "slider.horizontal.3")
                .font(.headline)
            Text("Points don't have a fixed face value — their return depends on how you redeem them (e.g. transfer to airlines vs statement credits). Adjust the sliders below to see which card wins at each valuation.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var valuationSlidersCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reward Currency Valuations").font(.headline)

            sliderRow(name: "Amex Membership Rewards", value: $amexMrCents, range: 0.8...2.5, step: 0.1,
                      baseline: "1.8¢ (Transfers) · 1.0¢ (Statement credit)")
            Divider()
            sliderRow(name: "Air Canada Aeroplan", value: $aeroplanCents, range: 1.0...2.5, step: 0.1,
                      baseline: "2.0¢ (Flight redemptions)")
            Divider()
            sliderRow(name: "RBC Avion Rewards", value: $avionCents, range: 1.0...2.2, step: 0.1,
                      baseline: "1.5¢ (Air travel schedule)")
            Divider()
            sliderRow(name: "Scotiabank Scene+", value: $scenePlusCents, range: 0.8...1.2, step: 0.05,
                      baseline: "1.0¢ (Fixed travel / grocery offset)")
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func sliderRow(name: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, baseline: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(String(format: "%.2f¢ / pt", value.wrappedValue))
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .foregroundStyle(.blue)
            }
            Slider(value: value, in: range, step: step)
            Text(baseline).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func simulationResultsSection(graph: DependencyGraph) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Simulated Checkout Outcomes").font(.headline)
            Text("Live evaluation using your active cards and customized point valuations.")
                .font(.footnote).foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(samples) { sample in
                    let result = simulateCheckout(sample: sample, graph: graph)
                    HStack(spacing: 12) {
                        Image(systemName: sample.icon)
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 36, height: 36)
                            .background(Color.blue.opacity(0.1), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(sample.label) ($\(Int(sample.amountCad)))")
                                .font(.subheadline.weight(.semibold))
                            Text("Winner: \(result.winningCardName)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "$%.2f", result.returnCad))
                                .font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(.green)
                            Text(String(format: "%.1f%% return", (result.returnCad / sample.amountCad) * 100))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private struct SimulationResult {
        let winningCardName: String
        let returnCad: Double
    }

    private func simulateCheckout(sample: SimulationSample, graph: DependencyGraph) -> SimulationResult {
        // Build customized owner state with current slider values
        var customOwner = graph.ownerState
        customOwner.valuationsCad[points: "amexMembershipRewards"]?.centsPerPoint = amexMrCents
        customOwner.valuationsCad[points: "rbcAvion"]?.centsPerPoint = avionCents
        customOwner.valuationsCad[points: "aeroplan"]?.centsPerPoint = aeroplanCents
        customOwner.valuationsCad[points: "scenePlus"]?.centsPerPoint = scenePlusCents

        let context = PurchaseContext(amountCad: sample.amountCad, category: sample.category)
        let engine = RecommendationEngine(catalogue: graph.catalogue, ownerState: customOwner)
        let today = Date().formatted(.iso8601.year().month().day())
        let outcome = engine.recommend(context, asOf: today)

        if case .advised(let recommendation) = outcome {
            let winnerName = graph.catalogue.cards.first { $0.cardId == recommendation.winner.cardId }?.officialName ?? recommendation.winner.cardId
            return SimulationResult(winningCardName: winnerName, returnCad: recommendation.winner.netValueCad)
        } else {
            return SimulationResult(winningCardName: "Cannot advise", returnCad: 0.0)
        }
    }
}
