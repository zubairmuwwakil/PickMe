import SwiftUI
import CardCopilotEngine

/// Per-card benefits browser (spec §6.3) — and, deliberately, Zubair's verification
/// checklist: the day every chip on this screen reads "Certificate verified", the benefits
/// data phase is done. The JSON file stays the single source of truth; nothing edits here.
struct BenefitsReferenceView: View {
    let deps: CheckoutFlowView.Dependencies
    let onDone: () -> Void

    var body: some View {
        List(deps.benefits.cards) { card in
            NavigationLink {
                CardBenefitsDetailView(card: card, cardName: cardName(card.cardId))
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cardName(card.cardId))
                        Text(card.benefits.isEmpty
                             ? (card.certificate.verificationStatus == .certificateVerified
                                ? "No coverage" : "Unknown — unverified")
                             : "\(card.benefits.count) benefits")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(BenefitsFormatting.verificationLabel(card.certificate.verificationStatus))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(chipColor(card.certificate.verificationStatus).opacity(0.15),
                                    in: Capsule())
                        .foregroundStyle(chipColor(card.certificate.verificationStatus))
                }
            }
        }
        .navigationTitle("Card benefits")
        .toolbar { Button("Done") { onDone() } }
    }

    private func cardName(_ cardId: String) -> String {
        deps.catalogue.cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }

    private func chipColor(_ verification: BenefitVerification) -> Color {
        switch verification {
        case .stub: return .orange
        case .issuerPage: return .blue
        case .certificateVerified: return .green
        }
    }
}

struct CardBenefitsDetailView: View {
    let card: CardBenefits
    let cardName: String

    @State private var selectedDisclosure: BenefitDisclosure?

    private var families: [(name: String, benefits: [Benefit])] {
        let order = ["shopping", "travelDisruption", "rentalCdw", "travelMedical"]
        let grouped = Dictionary(grouping: card.benefits, by: \.family)
        let known = order.compactMap { family in
            grouped[family].map { (familyDisplayName(family), $0) }
        }
        let unknown = grouped.filter { !order.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }   // future families render raw, never crash
        return known + unknown
    }

    var body: some View {
        List {
            if card.benefits.isEmpty {
                Section {
                    Text(card.certificate.verificationStatus == .certificateVerified
                         ? "The certificate confirms no coverage on this card."
                         : "No coverage found yet — unverified. The certificate pass will settle it.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(families, id: \.name) { family in
                Section(family.name) {
                    ForEach(family.benefits, id: \.benefitId) { benefit in
                        Button {
                            selectedDisclosure = BenefitDisclosure(
                                cardId: card.cardId, kind: benefit.kind,
                                coverage: benefit.coverage, conditions: benefit.conditions,
                                exclusions: benefit.exclusions ?? [],
                                verification: card.certificate.verificationStatus)
                        } label: {
                            LabeledContent(BenefitsFormatting.kindDisplayName(benefit.kind),
                                           value: BenefitsFormatting.factsLine(for: benefit.coverage,
                                                                               kind: benefit.kind))
                                .font(.footnote)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section {
                Text(BenefitsFormatting.certificateFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(cardName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDisclosure) { disclosure in
            BenefitDetailSheet(disclosure: disclosure, cardName: cardName)
        }
    }

    private func familyDisplayName(_ family: String) -> String {
        switch BenefitFamily(rawValue: family) {
        case .shopping: return "Shopping"
        case .travelDisruption: return "Travel disruption"
        case .rentalCdw: return "Rental car"
        case .travelMedical: return "Travel medical"
        case nil: return family
        }
    }
}
