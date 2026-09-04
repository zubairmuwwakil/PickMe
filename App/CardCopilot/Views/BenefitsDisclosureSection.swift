import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// Benefit facts and the final-decision bridge under a single reward recommendation.
///
/// `RecommendationEngine` still owns reward economics. This section makes it explicit when a
/// material purchase needs item context before rewards should be treated as the whole decision,
/// then routes the owner into the existing certificate-backed protection lens.
struct BenefitsDisclosureSection: View {
    let result: CheckoutResult
    let deps: DependencyGraph
    let winnerCardId: String
    let onCompare: (BenefitContextKind) -> Void

    @State private var selectedDisclosure: BenefitDisclosure?

    private var purchase: PurchaseContext {
        PurchaseContext(amountCad: result.effectiveAmountCad,
                        category: result.prediction.category)
    }

    private var disclosureResult: DisclosureResult {
        BenefitsAdvisor.disclosures(
            purchase: purchase,
            recommendedCardId: winnerCardId,
            wallet: deps.walletCardIds,
            catalogue: deps.benefits)
    }

    private var decisionAssessment: PurchaseDecisionAssessment {
        // The checkout does not know the purchased item type yet. The conservative policy therefore
        // asks for context on material purchases instead of deriving "electronics" or "phone" from
        // the merchant's MCC/category.
        guard case .single(let recommendation) = result.outcome else {
            return PurchaseDecisionAssessment(verdict: .rewardLeader,
                                              rewardCardId: winnerCardId)
        }
        return PurchaseDecisionAdvisor.assess(
            rewardRecommendation: recommendation,
            purchase: purchase,
            wallet: deps.walletCardIds,
            benefits: deps.benefits)
    }

    var body: some View {
        let disclosures = disclosureResult
        let decision = decisionAssessment
        if decision.verdict != .rewardLeader
            || !disclosures.recommended.isEmpty
            || !disclosures.nudges.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider()

                decisionBanner(decision)

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

    @ViewBuilder
    private func decisionBanner(_ assessment: PurchaseDecisionAssessment) -> some View {
        switch assessment.verdict {
        case .purchaseContextNeeded:
            VStack(alignment: .leading, spacing: 8) {
                Label("Rewards are only part of this decision",
                      systemImage: "shield.lefthalf.filled.trianglebadge.exclamationmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)

                Text("This is a material purchase and your wallet has verified shopping protection. PickMe will not infer the item from the merchant category; choose what you are buying to compare protection before treating the reward winner as final.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    contextButton("Electronics", kind: .electronics)
                    contextButton("Phone", kind: .mobileDevice)
                    contextButton("Appliance", kind: .applianceFurniture)
                }
            }
            .padding(10)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

        case .rewardProtectionTradeoff:
            Label("Reward winner and protection leader differ — compare before paying.",
                  systemImage: "arrow.left.arrow.right.circle")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)

        case .protectionTradeoffUnresolved:
            Label("Protection has a genuine trade-off; there is no single protection winner.",
                  systemImage: "scale.3d")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)

        case .rewardProtectionAligned:
            Label("Reward and protection signals align for the declared purchase.",
                  systemImage: "checkmark.shield.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.green)

        case .rewardLeader:
            EmptyView()
        }
    }

    private func contextButton(_ label: String, kind: BenefitContextKind) -> some View {
        Button(label) { onCompare(kind) }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
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
