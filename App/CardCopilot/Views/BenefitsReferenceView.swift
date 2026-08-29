import SwiftUI
import CardCopilotEngine

/// Per-card benefits browser: shows all certificate verified coverage and terms per card.
struct BenefitsReferenceView: View {
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedFamily = "All"

    var body: some View {
        if let graph = environment.graph {
            List {
                // Category Filter Pills
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                selectedFamily = "All"
                            } label: {
                                Text("All Categories")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(selectedFamily == "All" ? Color.indigo : Color(.tertiarySystemFill), in: Capsule())
                                    .foregroundStyle(selectedFamily == "All" ? .white : .primary)
                            }
                            .buttonStyle(.plain)

                            ForEach(BenefitFamily.allCases, id: \.rawValue) { family in
                                Button {
                                    selectedFamily = family.rawValue
                                } label: {
                                    Text(BenefitsFormatting.familyDisplayName(family.rawValue))
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(selectedFamily == family.rawValue ? Color.indigo : Color(.tertiarySystemFill), in: Capsule())
                                        .foregroundStyle(selectedFamily == family.rawValue ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14))
                }

                if filteredCards(graph: graph).isEmpty {
                    ContentUnavailableView("No matching benefits", systemImage: "magnifyingglass",
                                           description: Text("Try a card name, benefit, or another category."))
                } else {
                    Section {
                        ForEach(filteredCards(graph: graph)) { card in
                            NavigationLink {
                                CardBenefitsDetailView(card: card, cardName: cardName(card.cardId, graph: graph))
                            } label: {
                                HStack(spacing: 12) {
                                    CardMiniBadge(cardId: card.cardId, size: 20)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(cardName(card.cardId, graph: graph))
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                        Text(card.benefits.isEmpty
                                             ? (card.certificate.verificationStatus == .certificateVerified
                                                ? "Certificate confirms no listed coverage"
                                                : "No coverage found yet")
                                             : "\(card.benefits.count) listed benefit\(card.benefits.count == 1 ? "" : "s")")
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
                                .padding(.vertical, 3)
                            }
                        }
                    } header: {
                        Text("\(filteredCards(graph: graph).count) card\(filteredCards(graph: graph).count == 1 ? "" : "s")")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Card Benefits Library")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search cards or benefits")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                }
            }
        } else {
            EmptyView()
        }
    }

    private func cardName(_ cardId: String, graph: DependencyGraph) -> String {
        graph.catalogue.cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }

    private func filteredCards(graph: DependencyGraph) -> [CardBenefits] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return graph.benefits.cards.filter { card in
            let familyMatches = selectedFamily == "All" || card.benefits.contains { $0.family == selectedFamily }
            guard familyMatches else { return false }
            guard !query.isEmpty else { return true }
            let name = cardName(card.cardId, graph: graph).lowercased()
            return name.contains(query) || card.benefits.contains {
                BenefitsFormatting.kindDisplayName($0.kind).lowercased().contains(query)
                    || BenefitsFormatting.familyDisplayName($0.family).lowercased().contains(query)
            }
        }
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

    /// Catalogue 1.1 cards only have a single certificate URL. Expose that URL through the new
    /// document surface immediately, while allowing catalogue 1.2+ to supply multiple records.
    private var sourceDocuments: [CardDocument] {
        if !card.documents.isEmpty { return card.documents }
        guard let source = card.certificate.sourceUrl, !source.isEmpty else { return [] }
        return [CardDocument(
            documentId: "\(card.cardId)-certificate-source",
            kind: CardDocumentKind.certificateOfInsurance.rawValue,
            title: "Certificate / benefits source",
            url: source,
            effectiveDate: card.certificate.certificateDate,
            jurisdiction: card.certificate.jurisdiction,
            verificationStatus: card.certificate.verificationStatus,
            lastVerifiedAt: card.certificate.lastVerifiedAt
        )]
    }

    private func documentIcon(_ kind: String) -> String {
        switch CardDocumentKind(rawValue: kind) {
        case .certificateOfInsurance, .claimsInstructions: return "checkmark.shield"
        case .cardholderAgreement, .welcomeGuide: return "doc.text"
        case .feeSchedule: return "dollarsign.circle"
        case .loungeTerms: return "airplane"
        case .productPage: return "globe"
        case .other, nil: return "doc"
        }
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

            Section("Verification") {
                Label(BenefitsFormatting.verificationDescription(card.certificate.verificationStatus),
                      systemImage: card.certificate.verificationStatus == .certificateVerified
                        ? "checkmark.seal.fill" : "questionmark.circle")
                    .foregroundStyle(card.certificate.verificationStatus == .certificateVerified ? .green : .orange)

                if let underwriter = card.certificate.underwriter, !underwriter.isEmpty {
                    LabeledContent("Underwriter", value: underwriter)
                }
                if let date = card.certificate.certificateDate, !date.isEmpty {
                    LabeledContent("Certificate date", value: date)
                }
                if let verified = card.certificate.lastVerifiedAt, !verified.isEmpty {
                    LabeledContent("Last verified", value: verified)
                }
                if let jurisdiction = card.certificate.jurisdiction, !jurisdiction.isEmpty {
                    LabeledContent("Jurisdiction", value: jurisdiction)
                }
                if let source = card.certificate.sourceUrl, let url = URL(string: source) {
                    Link(destination: url) {
                        Label("Open certificate source", systemImage: "doc.text.magnifyingglass")
                    }
                }
            }

            if !sourceDocuments.isEmpty {
                Section("Documents") {
                    ForEach(sourceDocuments) { document in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: documentIcon(document.kind))
                                    .foregroundStyle(.teal)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(document.title)
                                        .font(.subheadline.weight(.semibold))
                                    Text(BenefitsFormatting.documentKindDisplayName(document.kind))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(BenefitsFormatting.verificationLabel(document.verificationStatus))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(document.verificationStatus == .certificateVerified ? .green : .orange)
                            }

                            if let date = document.effectiveDate, !date.isEmpty {
                                Text("Effective \(date)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let jurisdiction = document.jurisdiction, !jurisdiction.isEmpty {
                                Text(jurisdiction)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let url = URL(string: document.url) {
                                HStack(spacing: 16) {
                                    Link("Open document", destination: url)
                                    ShareLink(item: document.url,
                                              subject: Text(document.title),
                                              message: Text("Source document for \(cardName)")) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                        .padding(.vertical, 3)
                    }

                    if card.documents.isEmpty {
                        Text("Showing the existing certificate source. Add more documents to this card in the catalogue to expand this list.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
                                verification: card.certificate.verificationStatus,
                                underwriter: card.certificate.underwriter,
                                sourceURL: card.certificate.sourceUrl,
                                certificateDate: card.certificate.certificateDate,
                                lastVerifiedAt: card.certificate.lastVerifiedAt,
                                jurisdiction: card.certificate.jurisdiction)
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
