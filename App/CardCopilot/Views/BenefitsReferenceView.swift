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
                researchStatusSection(graph: graph)

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
                                CardBenefitsDetailView(cardId: card.cardId,
                                                        cardName: cardName(card.cardId, graph: graph))
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

    private func researchStatusSection(graph: DependencyGraph) -> some View {
        let health = BenefitsSourceHealth(catalogue: graph.benefits)
        return Section("Research status") {
            LabeledContent("Source coverage", value: health.sourceCoverageLabel)
            LabeledContent("Documents indexed", value: "\(health.documentCount)")
            LabeledContent("Owner-confirmed cards", value: "\(health.ownerVerifiedCards)")

            if health.staleCards > 0 || health.staleDocuments > 0 {
                Label("\(health.staleCards + health.staleDocuments) source\(health.staleCards + health.staleDocuments == 1 ? "" : "s") need a refresh",
                      systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
            } else {
                Label("All indexed sources checked within the last year",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Text("Public sources are research references. Import your own certificate below a card and confirm that it belongs to you before relying on coverage.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct CardBenefitsDetailView: View {
    let cardId: String
    let cardName: String

    @Environment(CopilotEnvironment.self) private var environment
    @State private var selectedDisclosure: BenefitDisclosure?
    @State private var isImporting = false
    @State private var importKind = CardDocumentKind.certificateOfInsurance.rawValue
    @State private var pendingVerification: PersonalBenefitsDocument?

    private var card: CardBenefits? {
        environment.graph?.benefits.card(cardId)
    }

    private func families(for card: CardBenefits) -> [(name: String, icon: String, benefits: [Benefit])] {
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
    private func sourceDocuments(for card: CardBenefits) -> [CardDocument] {
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

    private func personalDocumentID(_ document: CardDocument) -> UUID? {
        let prefix = "personal-"
        guard document.documentId.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(document.documentId.dropFirst(prefix.count)))
    }

    private func documentVerificationLabel(_ document: CardDocument) -> String {
        guard URL(string: document.url)?.isFileURL == true else {
            return BenefitsFormatting.verificationLabel(document.verificationStatus)
        }
        return document.verificationStatus == .certificateVerified ? "Owner confirmed" : "Imported"
    }

    var body: some View {
        Group {
            if let card {
                cardContent(card)
            } else {
                ContentUnavailableView("Benefits unavailable", systemImage: "doc.text.magnifyingglass")
            }
        }
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: [.pdf, .image, .data],
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            if environment.addPersonalBenefitDocument(cardId: cardId, sourceURL: url, kind: importKind) {
                pendingVerification = environment.benefitsDocumentVault.documents.last { $0.cardId == cardId && $0.fileName == url.lastPathComponent }
            }
        }
        .confirmationDialog("Confirm this document",
                            isPresented: Binding(get: { pendingVerification != nil },
                                                 set: { if !$0 { pendingVerification = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingVerification) { document in
            Button("I checked — verify this card") {
                environment.verifyPersonalBenefitDocument(id: document.id)
            }
            Button("Keep imported, verify later") {}
        } message: { document in
            Text("Only confirm if \(document.fileName) is the current certificate or card document for your \(cardName) account. PickMe cannot determine eligibility from the file alone.")
        }
    }

    @ViewBuilder
    private func cardContent(_ card: CardBenefits) -> some View {
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

                Menu {
                    Button("Certificate of insurance") {
                        importKind = CardDocumentKind.certificateOfInsurance.rawValue
                        isImporting = true
                    }
                    Button("Cardholder agreement") {
                        importKind = CardDocumentKind.cardholderAgreement.rawValue
                        isImporting = true
                    }
                    Button("Claims instructions") {
                        importKind = CardDocumentKind.claimsInstructions.rawValue
                        isImporting = true
                    }
                    Button("Other benefit document") {
                        importKind = CardDocumentKind.other.rawValue
                        isImporting = true
                    }
                } label: {
                    Label("Import my document", systemImage: "square.and.arrow.down")
                }
                Text("Stored only on this iPhone. Importing does not verify coverage until you confirm the document belongs to this card.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !sourceDocuments(for: card).isEmpty {
                Section("Documents") {
                    ForEach(sourceDocuments(for: card)) { document in
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
                                Text(documentVerificationLabel(document))
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
                                    if url.isFileURL {
                                        ShareLink(item: url,
                                                  subject: Text(document.title),
                                                  message: Text("Personal benefit document for \(cardName)")) {
                                            Label("Share file", systemImage: "square.and.arrow.up")
                                        }
                                        Text("On this iPhone")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Link(document.kind == CardDocumentKind.claimsInstructions.rawValue
                                             ? "Start claim" : "Open document", destination: url)
                                        ShareLink(item: document.url,
                                                  subject: Text(document.title),
                                                  message: Text("Source document for \(cardName)")) {
                                            Label("Share link", systemImage: "square.and.arrow.up")
                                        }
                                    }
                                }
                                .font(.caption.weight(.semibold))

                                if let personalID = personalDocumentID(document) {
                                    Menu {
                                        if document.verificationStatus != .certificateVerified {
                                            Button("Confirm this document") {
                                                pendingVerification = environment.benefitsDocumentVault.documents.first { $0.id == personalID }
                                            }
                                        }
                                        Button("Remove from this iPhone", role: .destructive) {
                                            environment.removePersonalBenefitDocument(id: personalID)
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
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

            ForEach(families(for: card), id: \.name) { family in
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
