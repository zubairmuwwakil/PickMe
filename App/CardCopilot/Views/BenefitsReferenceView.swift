import SwiftUI
import CardCopilotEngine

/// Per-card benefits browser: shows all certificate verified coverage and terms per card.
struct BenefitsReferenceView: View {
    let deps: DependencyGraph
    let onDone: () -> Void

    var body: some View {
        List(deps.benefits.cards) { card in
            NavigationLink {
                CardBenefitsDetailView(card: card, cardName: cardName(card.cardId))
            } label: {
                HStack(spacing: 12) {
                    CardMiniBadge(cardId: card.cardId, size: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(cardName(card.cardId))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Text(card.benefits.isEmpty
                             ? (card.certificate.verificationStatus == .certificateVerified
                                ? "No coverage" : "Unknown — unverified")
                             : "\(card.benefits.count) certificate benefits")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(BenefitsFormatting.verificationLabel(card.certificate.verificationStatus))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(chipColor(card.certificate.verificationStatus).opacity(0.15),
                                    in: Capsule())
                        .foregroundStyle(chipColor(card.certificate.verificationStatus))
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Card benefits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
                    .font(.headline)
            }
        }
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

    private var families: [(name: String, icon: String, benefits: [Benefit])] {
        let familyMeta: [(key: String, name: String, icon: String)] = [
            ("shopping", "Purchase & Shopping", "cart.fill"),
            ("travelDisruption", "Travel Disruption & Delay", "airplane"),
            ("rentalCdw", "Rental Car CDW", "car.fill"),
            ("travelMedical", "Emergency Travel Medical", "cross.case.fill")
        ]
        let grouped = Dictionary(grouping: card.benefits, by: \.family)
        let known = familyMeta.compactMap { meta in
            grouped[meta.key].map { (meta.name, meta.icon, $0) }
        }
        let unknown = grouped.filter { group in !familyMeta.contains { $0.key == group.key } }
            .sorted { $0.key < $1.key }
            .map { ($0.key.capitalized, "shield.fill", $0.value) }
        return known + unknown
    }

    var body: some View {
        List {
            // Card Hero Header in list
            Section {
                CardArtView(
                    cardId: card.cardId,
                    officialName: cardName,
                    rewardHeadline: "\(card.benefits.count) Policy Benefits",
                    isHero: false
                )
                .padding(.vertical, 4)
            }

            if card.benefits.isEmpty {
                Section {
                    Text(card.certificate.verificationStatus == .certificateVerified
                         ? "The certificate confirms no insurance coverage on this card product."
                         : "No coverage found yet — unverified. The certificate pass will settle it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(families, id: \.name) { family in
                Section {
                    ForEach(family.benefits, id: \.benefitId) { benefit in
                        Button {
                            selectedDisclosure = BenefitDisclosure(
                                cardId: card.cardId, kind: benefit.kind,
                                coverage: benefit.coverage, conditions: benefit.conditions,
                                exclusions: benefit.exclusions ?? [],
                                verification: card.certificate.verificationStatus)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(BenefitsFormatting.kindDisplayName(benefit.kind))
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Text(BenefitsFormatting.factsLine(for: benefit.coverage,
                                                                      kind: benefit.kind))
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
                } header: {
                    Label(family.name, systemImage: family.icon)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                }
            }

            Section {
                Text(BenefitsFormatting.certificateFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(cardName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDisclosure) { disclosure in
            BenefitDetailSheet(disclosure: disclosure, cardName: cardName)
        }
    }
}
