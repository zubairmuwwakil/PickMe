import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// Quiet benefit facts under a single recommendation (spec §6.1): at most two lines for the
/// winning card, one compare-nudge when another card covers something the winner doesn't.
/// Facts only — this section never re-ranks and never says "covered".
struct BenefitsDisclosureSection: View {
    let result: CheckoutResult
    let deps: DependencyGraph
    let winnerCardId: String
    let onCompare: (BenefitContextKind) -> Void

    @State private var selectedDisclosure: BenefitDisclosure?

    private var disclosureResult: DisclosureResult {
        BenefitsAdvisor.disclosures(
            purchase: PurchaseContext(amountCad: result.effectiveAmountCad,
                                      category: result.prediction.category),
            recommendedCardId: winnerCardId,
            wallet: deps.walletCardIds,
            catalogue: deps.benefits)
    }

    var body: some View {
        let disclosures = disclosureResult
        if !disclosures.recommended.isEmpty || !disclosures.nudges.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                ForEach(disclosures.recommended.prefix(2), id: \.kind) { disclosure in
                    Button {
                        selectedDisclosure = disclosure
                    } label: {
                        Label {
                            Text("\(BenefitsFormatting.kindDisplayName(disclosure.kind)) · \(BenefitsFormatting.factsLine(for: disclosure.coverage, kind: disclosure.kind)) — per certificate")
                                .multilineTextAlignment(.leading)
                        } icon: {
                            Image(systemName: "checkmark.shield")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(disclosures.nudges.prefix(1), id: \.kind) { nudge in
                    Button {
                        onCompare(BenefitsFormatting.contextKind(forNudgedKind: nudge.kind))
                    } label: {
                        Label("\(cardName(nudge.cardId)) adds \(BenefitsFormatting.kindDisplayName(nudge.kind).lowercased()) — compare",
                              systemImage: "shield.lefthalf.filled")
                            .font(.footnote)
                    }
                    .buttonStyle(.plain)
                }

                Text(BenefitsFormatting.certificateFooter)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .sheet(item: $selectedDisclosure) { disclosure in
                BenefitDetailSheet(disclosure: disclosure, cardName: cardName(disclosure.cardId))
            }
        }
    }

    private func cardName(_ cardId: String) -> String {
        deps.catalogue.cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }
}

/// Full facts for one benefit: coverage numbers, then the certificate's own conditions and
/// exclusions verbatim (spec B2 — quoted, never summarized into promises).
struct BenefitDetailSheet: View {
    let disclosure: BenefitDisclosure
    let cardName: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Card", value: cardName)
                    LabeledContent("Coverage",
                                   value: BenefitsFormatting.factsLine(for: disclosure.coverage,
                                                                       kind: disclosure.kind))
                    LabeledContent("Status",
                                   value: BenefitsFormatting.verificationLabel(disclosure.verification))
                }
                if !disclosure.conditions.isEmpty {
                    Section("Conditions (per certificate)") {
                        ForEach(disclosure.conditions, id: \.self) { Text($0).font(.footnote) }
                    }
                }
                if !disclosure.exclusions.isEmpty {
                    Section("Exclusions (per certificate)") {
                        ForEach(disclosure.exclusions, id: \.self) { Text($0).font(.footnote) }
                    }
                }
                Section {
                    Text(BenefitsFormatting.certificateFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(BenefitsFormatting.kindDisplayName(disclosure.kind))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
