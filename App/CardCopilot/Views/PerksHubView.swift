import SwiftUI
import CardCopilotEngine

/// The protection workspace: start with a real scenario, compare your wallet, and view certificate-backed facts.
struct PerksHubView: View {
    @Environment(CheckoutRouter.self) private var router
    @Environment(CopilotEnvironment.self) private var environment
    @State private var searchText = ""
    @State private var selectedFilter: BenefitPillar = .all
    @State private var selectedDisclosure: BenefitDisclosure?

    enum BenefitPillar: String, CaseIterable, Identifiable {
        case all = "All"
        case travel = "Travel & Flights"
        case rental = "Rental Car"
        case shopping = "Purchases & Tech"
        case mobile = "Mobile Devices"
        case medical = "Travel Medical"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .all: return "sparkles"
            case .travel: return "airplane"
            case .rental: return "car.fill"
            case .shopping: return "bag.fill"
            case .mobile: return "iphone"
            case .medical: return "cross.case.fill"
            }
        }
    }

    var body: some View {
        Group {
            if let graph = environment.graph {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                        protectionRadarCard(graph: graph)
                        searchAndFilterSection(graph: graph)

                        if isSearchingOrFiltering {
                            searchResultsSection(graph: graph)
                        } else {
                            scenarioSection(graph: graph)
                            walletSuperpowersSection(graph: graph)
                            referenceSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 110)
                }
                .scrollIndicators(.hidden)
                .sheet(item: $selectedDisclosure) { disclosure in
                    BenefitDetailSheet(
                        disclosure: disclosure,
                        cardName: cardName(disclosure.cardId, graph: graph)
                    )
                }
            } else {
                ProgressView("Loading protection data…")
            }
        }
        .navigationTitle("Protection & Perks")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Header
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.indigo)
                Text("CERTIFICATE-BACKED PROTECTION")
                    .font(.caption.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.indigo)
            }

            Text("Know what your cards protect.")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("Compare insurance and warranty coverage across your wallet before making major bookings or purchases.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Hero Protection Radar Card
    private func protectionRadarCard(graph: DependencyGraph) -> some View {
        let walletIDs = Set(graph.walletCardIds)
        let walletCardsWithBenefits = graph.benefits.cards.filter { walletIDs.contains($0.cardId) }
        let coveredCardCount = walletCardsWithBenefits.filter { !$0.benefits.isEmpty }.count
        let totalCards = max(graph.walletCardIds.count, 1)

        // Count coverage across key pillars
        let hasTravel = walletCardsWithBenefits.contains { card in
            card.benefits.contains { $0.family == "travelDisruption" || $0.kind.contains("flight") || $0.kind.contains("baggage") || $0.kind.contains("trip") }
        }
        let hasRental = walletCardsWithBenefits.contains { card in
            card.benefits.contains { $0.family == "rentalCdw" || $0.kind == "rentalCdw" }
        }
        let hasPurchase = walletCardsWithBenefits.contains { card in
            card.benefits.contains { $0.family == "shopping" || $0.kind == "purchaseProtection" || $0.kind == "extendedWarranty" }
        }
        let hasMobile = walletCardsWithBenefits.contains { card in
            card.benefits.contains { $0.kind == "mobileDeviceInsurance" }
        }

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("WALLET COVERAGE RADAR")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(.white.opacity(0.8))

                    Text("\(coveredCardCount) of \(totalCards) Cards Covered")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Policies verified against official issuer certificates")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }

                Spacer()

                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            Divider()
                .overlay(Color.white.opacity(0.2))

            // 4 Pillars Grid
            HStack(spacing: 8) {
                pillarPill(title: "Travel", icon: "airplane", isCovered: hasTravel)
                pillarPill(title: "Rental CDW", icon: "car.fill", isCovered: hasRental)
                pillarPill(title: "Shopping", icon: "bag.fill", isCovered: hasPurchase)
                pillarPill(title: "Mobile", icon: "iphone", isCovered: hasMobile)
            }
        }
        .padding(16)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.16, blue: 0.32),
                        Color(red: 0.18, green: 0.22, blue: 0.44),
                        Color(red: 0.10, green: 0.12, blue: 0.26)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Subtle inner glow
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.indigo.opacity(0.25), radius: 12, x: 0, y: 6)
    }

    private func pillarPill(title: String, icon: String, isCovered: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isCovered ? Color.green : Color.white.opacity(0.4))

            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 3) {
                Circle()
                    .fill(isCovered ? Color.green : Color.orange.opacity(0.7))
                    .frame(width: 5, height: 5)
                Text(isCovered ? "Active" : "None")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(isCovered ? Color.green : Color.white.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Search & Quick Filter Pills
    private func searchAndFilterSection(graph: DependencyGraph) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search perks, insurance, or cards…", text: $searchText)
                    .font(.subheadline)
                    .autocorrectionDisabled()

                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            // Filter Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(BenefitPillar.allCases) { pillar in
                        Button {
                            withAnimation(.snappy(duration: 0.25)) {
                                selectedFilter = pillar
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: pillar.icon)
                                    .font(.caption2.weight(.semibold))
                                Text(pillar.rawValue)
                                    .font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                selectedFilter == pillar
                                    ? Color.indigo
                                    : Color(.secondarySystemGroupedBackground),
                                in: Capsule()
                            )
                            .foregroundStyle(selectedFilter == pillar ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var isSearchingOrFiltering: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedFilter != .all
    }

    // MARK: - Filtered Results View
    private func searchResultsSection(graph: DependencyGraph) -> some View {
        let matchingCards = filteredCardsWithBenefits(graph: graph)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Matching Benefits")
                    .font(.headline)
                Spacer()
                Text("\(matchingCards.count) cards")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if matchingCards.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("No matching benefits found")
                        .font(.subheadline.weight(.semibold))
                    Text("Try searching for terms like 'delay', 'rental', 'warranty', 'theft', or 'medical'.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ForEach(matchingCards, id: \.card.cardId) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            CardMiniBadge(cardId: item.card.cardId, size: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cardName(item.card.cardId, graph: graph))
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                Text(item.card.certificate.underwriter ?? "Verified Policy")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(BenefitsFormatting.verificationLabel(item.card.certificate.verificationStatus))
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.15), in: Capsule())
                                .foregroundStyle(.green)
                        }

                        Divider()

                        ForEach(item.matchingBenefits, id: \.benefitId) { benefit in
                            Button {
                                selectedDisclosure = BenefitDisclosure(
                                    cardId: item.card.cardId,
                                    kind: benefit.kind,
                                    coverage: benefit.coverage,
                                    conditions: benefit.conditions,
                                    exclusions: benefit.exclusions ?? [],
                                    verification: item.card.certificate.verificationStatus,
                                    underwriter: item.card.certificate.underwriter,
                                    sourceURL: item.card.certificate.sourceUrl,
                                    certificateDate: item.card.certificate.certificateDate,
                                    lastVerifiedAt: item.card.certificate.lastVerifiedAt,
                                    jurisdiction: item.card.certificate.jurisdiction
                                )
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(BenefitsFormatting.kindDisplayName(benefit.kind))
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.primary)
                                        Text(BenefitsFormatting.factsLine(for: benefit.coverage, kind: benefit.kind))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private func filteredCardsWithBenefits(graph: DependencyGraph) -> [(card: CardBenefits, matchingBenefits: [Benefit])] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let walletIDs = Set(graph.walletCardIds)

        return graph.benefits.cards.compactMap { card in
            guard walletIDs.contains(card.cardId) || walletIDs.isEmpty else { return nil }

            let matchingBenefits = card.benefits.filter { benefit in
                // Filter by pillar
                let pillarMatch: Bool
                switch selectedFilter {
                case .all:
                    pillarMatch = true
                case .travel:
                    pillarMatch = benefit.family == "travelDisruption" || benefit.kind.contains("flight") || benefit.kind.contains("baggage") || benefit.kind.contains("trip")
                case .rental:
                    pillarMatch = benefit.family == "rentalCdw" || benefit.kind == "rentalCdw"
                case .shopping:
                    pillarMatch = benefit.family == "shopping" || benefit.kind == "purchaseProtection" || benefit.kind == "extendedWarranty"
                case .mobile:
                    pillarMatch = benefit.kind == "mobileDeviceInsurance"
                case .medical:
                    pillarMatch = benefit.family == "travelMedical" || benefit.kind == "travelMedical"
                }

                guard pillarMatch else { return false }
                guard !query.isEmpty else { return true }

                let cardOfficialName = cardName(card.cardId, graph: graph).lowercased()
                let kindName = BenefitsFormatting.kindDisplayName(benefit.kind).lowercased()
                let familyName = BenefitsFormatting.familyDisplayName(benefit.family).lowercased()

                return cardOfficialName.contains(query) || kindName.contains(query) || familyName.contains(query) || benefit.conditions.joined().lowercased().contains(query)
            }

            if matchingBenefits.isEmpty { return nil }
            return (card, matchingBenefits)
        }
    }

    // MARK: - Scenario Section (Bento Grid)
    private func scenarioSection(graph: DependencyGraph) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Start with a scenario")
                    .font(.title3.weight(.bold))
                Spacer()
                Text("Compare Wallet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                // 1. Flight & Vacation
                scenarioFeatureCard(
                    kind: .flight,
                    icon: "airplane",
                    gradientColors: [Color.indigo, Color.blue],
                    title: "Flight or vacation",
                    subtitle: "Delay, cancellation, baggage loss & emergency medical",
                    tags: ["4h+ Flight Delay", "Up to $5M Medical", "Baggage Loss"]
                )

                // 2. Car Rental
                scenarioFeatureCard(
                    kind: .carRental,
                    icon: "car.fill",
                    gradientColors: [Color.blue, Color.teal],
                    title: "Rental car CDW",
                    subtitle: "Collision damage waiver, theft protection & vehicle limits",
                    tags: ["Save ~$30/day", "Zero Deductible", "Damage & Theft"]
                )

                // 3. Tech & Big Purchases
                scenarioFeatureCard(
                    kind: .electronics,
                    icon: "laptopcomputer",
                    gradientColors: [Color.purple, Color.indigo],
                    title: "Big purchase or tech",
                    subtitle: "Accidental damage, theft & extended warranty extensions",
                    tags: ["120-Day Theft/Loss", "+1-2 Yrs Warranty", "Price Drop"]
                )

                // 4. Phone & Mobile Devices
                scenarioFeatureCard(
                    kind: .mobileDevice,
                    icon: "iphone",
                    gradientColors: [Color.pink, Color.purple],
                    title: "Phone or mobile device",
                    subtitle: "Device insurance, screen cracks, drops & deductibles",
                    tags: ["Screen & Drops", "Up to $1,000", "Low Deductible"]
                )

                // 5. Appliance & Furniture
                scenarioFeatureCard(
                    kind: .applianceFurniture,
                    icon: "sofa.fill",
                    gradientColors: [Color.orange, Color.red],
                    title: "Appliance & furniture",
                    subtitle: "Doubles original manufacturer warranty on major household items",
                    tags: ["Repair Coverage", "Originals ≤ 5 Yrs"]
                )
            }
        }
    }

    private func scenarioFeatureCard(
        kind: BenefitContextKind,
        icon: String,
        gradientColors: [Color],
        title: String,
        subtitle: String,
        tags: [String]
    ) -> some View {
        Button {
            router.push(.protectionLens(BenefitContext(kind: kind)))
        } label: {
            HStack(alignment: .top, spacing: 14) {
                // Icon Box
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: gradientColors.map { $0.opacity(0.18) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(gradientColors.first ?? .blue)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(title)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Feature Tags
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Open comparison lens for \(title)")
    }

    // MARK: - Wallet Superpowers Section
    @ViewBuilder
    private func walletSuperpowersSection(graph: DependencyGraph) -> some View {
        let walletIDs = Set(graph.walletCardIds)
        let cardsWithBenefits = graph.benefits.cards.filter {
            walletIDs.contains($0.cardId) && !$0.benefits.isEmpty
        }

        if !cardsWithBenefits.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Wallet Superpowers")
                        .font(.title3.weight(.bold))
                    Spacer()
                    Text("\(cardsWithBenefits.count) cards")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(cardsWithBenefits, id: \.cardId) { card in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    CardMiniBadge(cardId: card.cardId, size: 20)
                                    Text(cardName(card.cardId, graph: graph))
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(card.benefits.prefix(2), id: \.benefitId) { benefit in
                                        HStack(spacing: 5) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 10))
                                                .foregroundStyle(.green)
                                            Text(BenefitsFormatting.kindDisplayName(benefit.kind))
                                                .font(.system(size: 11, weight: .medium))
                                                .lineLimit(1)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            .padding(12)
                            .frame(width: 210, alignment: .leading)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Reference & Provenance Section
    private var referenceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reference")
                .font(.title3.weight(.bold))

            Button { router.push(.benefitsReference) } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.teal.opacity(0.14))
                            .frame(width: 44, height: 44)
                        Image(systemName: "books.vertical.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.teal)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Search All Card Benefits")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Certificates, coverage limits, and issuer sources")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            // Trust Footnote
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Backed by official issuer certificates (Chubb, Belair, Allianz, Desjardins).")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private func cardName(_ cardId: String, graph: DependencyGraph) -> String {
        graph.catalogue.cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }
}
