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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Hero Overview Card
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            CardMiniBadge(cardId: disclosure.cardId, size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cardName)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                                if let underwriter = disclosure.underwriter, !underwriter.isEmpty {
                                    Text(underwriter)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(BenefitsFormatting.verificationLabel(disclosure.verification))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    (disclosure.verification == .certificateVerified ? Color.green : Color.blue).opacity(0.15),
                                    in: Capsule()
                                )
                                .foregroundStyle(disclosure.verification == .certificateVerified ? Color.green : Color.blue)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text("COVERAGE SUMMARY")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(0.7)
                                .foregroundStyle(.secondary)
                            Text(BenefitsFormatting.factsLine(for: disclosure.coverage, kind: disclosure.kind))
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Certificate Provenance
                Section("Certificate Provenance") {
                    if let underwriter = disclosure.underwriter, !underwriter.isEmpty {
                        LabeledContent("Underwriter", value: underwriter)
                    }
                    if let date = disclosure.certificateDate, !date.isEmpty {
                        LabeledContent("Certificate Date", value: date)
                    }
                    if let verified = disclosure.lastVerifiedAt, !verified.isEmpty {
                        LabeledContent("Last Verified", value: verified)
                    }
                    if let jurisdiction = disclosure.jurisdiction, !jurisdiction.isEmpty {
                        LabeledContent("Jurisdiction", value: jurisdiction)
                    }
                    if let source = disclosure.sourceURL, let url = URL(string: source) {
                        Link(destination: url) {
                            Label("Open Official Certificate PDF", systemImage: "doc.richtext")
                                .font(.system(size: 14, weight: .medium))
                        }
                        ShareLink(item: source,
                                  subject: Text("\(BenefitsFormatting.kindDisplayName(disclosure.kind)) Certificate"),
                                  message: Text("Official insurance policy certificate for \(cardName)")) {
                            Label("Share Policy Link", systemImage: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .medium))
                        }
                    }
                }

                // Conditions
                if !disclosure.conditions.isEmpty {
                    Section("Conditions (per certificate)") {
                        ForEach(disclosure.conditions, id: \.self) { condition in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "checkmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .padding(.top, 2)
                                Text(condition)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Exclusions
                if !disclosure.exclusions.isEmpty {
                    Section("Exclusions (per certificate)") {
                        ForEach(disclosure.exclusions, id: \.self) { exclusion in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "xmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
                                Text(exclusion)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Notice
                Section {
                    Label("Claims are adjudicated directly by the issuer's underwriter according to cardholder certificate terms.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(BenefitsFormatting.certificateFooter)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(BenefitsFormatting.kindDisplayName(disclosure.kind))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
