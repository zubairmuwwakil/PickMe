import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// Home's single answer to "which card, here, now".
///
/// This replaces two components that rendered the same thing for different inputs: a nearby
/// dropdown taking `[NearbyMerchant]` and a Quick Pick carousel taking `StoredMerchant`. They
/// were 400 points apart on the same screen, so the duplication read as two competing answers.
/// Both now feed `HomeAnswerSubject`, and the chip row below re-points this one card.
///
/// Rendering advice is not evidence that a purchase happened — that invariant is inherited from
/// the Quick Pick card and still holds here. Nothing is logged until the owner taps Breakdown.
struct HomeAnswerCardView: View {
    let subjects: [HomeAnswerSubject]
    let deps: DependencyGraph
    /// The displayed radar result has aged past the window in which it may be trusted blind.
    let isStale: Bool
    let fetchedAt: Date?
    @Binding var selectedSubjectID: String?

    @Environment(CopilotSession.self) private var session
    @Environment(CheckoutRouter.self) private var router
    @Environment(\.openURL) private var openURL

    /// `nil` means "follow confidence". A tap pins the card open or shut until the subject
    /// changes, at which point the confidence rule takes over again.
    @State private var expansionOverride: Bool?
    @State private var selectedAmount: Double = InstantRepeatAdvisor.comparisonAmountCad

    private var activeSubject: HomeAnswerSubject? {
        if let selectedSubjectID,
           let match = subjects.first(where: { $0.id == selectedSubjectID }) {
            return match
        }
        return subjects.first
    }

    /// Whether the app genuinely knows where the owner is standing.
    ///
    /// `confidentPreparedMerchant` was engineered for exactly this judgement — accurate fix,
    /// nearest place close, runner-up clearly further — and was previously used only to pick a
    /// label colour.
    private var isConfident: Bool {
        guard let active = activeSubject else { return false }
        return session.confidentPreparedMerchant?.id == active.id
    }

    /// The answer card expands automatically when a subject is selected (including nearby places),
    /// showing the card pick recommendation and card art immediately instead of staying hidden.
    /// Tapping the header toggle allows the owner to hide or show it manually.
    private var isExpanded: Bool {
        if let expansionOverride { return expansionOverride }
        return activeSubject != nil
    }

    var body: some View {
        if let current = activeSubject {
            VStack(spacing: 0) {
                headerBar(for: current)

                if isExpanded {
                    expandedTray(active: current)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .top)),
                            removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                        ))
                }

                if subjects.count > 1 {
                    subjectChipsBar(activeID: current.id)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(isExpanded ? 0.08 : 0.03),
                            radius: isExpanded ? 12 : 6, x: 0, y: isExpanded ? 4 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isExpanded ? Color.blue.opacity(0.18) : Color.blue.opacity(0.08),
                                  lineWidth: 1.2)
                    // A decorative border has no business taking touches away from the content.
                    .allowsHitTesting(false)
            )
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isExpanded)
            .onChange(of: activeSubject?.id) { _, _ in
                expansionOverride = nil
            }
            .onAppear {
                if selectedSubjectID == nil { selectedSubjectID = subjects.first?.id }
            }
            .onChange(of: subjects) { _, updated in
                if let current = selectedSubjectID, !updated.contains(where: { $0.id == current }) {
                    selectedSubjectID = updated.first?.id
                } else if selectedSubjectID == nil {
                    selectedSubjectID = updated.first?.id
                }
            }
        }
    }

    // MARK: - Header

    private func headerBar(for subject: HomeAnswerSubject) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                expansionOverride = !isExpanded
            }
        } label: {
            HStack(spacing: 12) {
                MerchantBrandIconView(merchantName: subject.name,
                                      category: subject.prediction.category,
                                      size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(eyebrow(for: subject))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(eyebrowColor(for: subject))
                            .textCase(.uppercase)

                        if let detail = subtitleDetail(for: subject) {
                            Text("•")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Text(detail)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(subject.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Text(isExpanded ? "Hide" : "Card Pick")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.blue)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.blue)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isExpanded)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.10), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded
            ? "Collapse card recommendation for \(subject.name)"
            : "Expand card recommendation for \(subject.name)")
    }

    private func eyebrow(for subject: HomeAnswerSubject) -> String {
        switch subject.provenance {
        case .nearby: return isConfident ? "Likely here" : "Closest nearby"
        case .recent: return subject.isConfirmed ? "Confirmed here" : "Recent place"
        case .searched: return "Searched"
        }
    }

    private func eyebrowColor(for subject: HomeAnswerSubject) -> Color {
        switch subject.provenance {
        case .nearby: return isConfident ? .green : .blue
        case .recent: return subject.isConfirmed ? .green : .secondary
        case .searched: return .blue
        }
    }

    /// Distance for a live radar result; how long ago the scan ran once it has aged. Saying
    /// "82 m away" from a fix taken twenty minutes ago would assert a precision Home no longer has.
    private func subtitleDetail(for subject: HomeAnswerSubject) -> String? {
        switch subject.provenance {
        case .nearby:
            if isStale { return fetchedAt.map(Self.ageText) ?? "Tap Radar to refresh" }
            return subject.distanceMeters.map { "\(Int($0.rounded())) m away" }
        case .recent, .searched:
            return subject.prediction.category.isEmpty
                ? nil
                : CategoryVisuals.meta(for: subject.prediction.category).displayName
        }
    }

    static func ageText(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 90 { return "moments ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "as of \(minutes) min ago" }
        let hours = minutes / 60
        return "as of \(hours) hr ago"
    }

    // MARK: - Expanded tray

    private func expandedTray(active: HomeAnswerSubject) -> some View {
        VStack(spacing: 12) {
            Divider().padding(.horizontal, 14)
            recommendationContent(for: active)
                .padding(.horizontal, 14)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Subject chips

    private var nearbySubjects: [HomeAnswerSubject] {
        subjects.filter { $0.provenance == .nearby }
    }

    private var recentSubjects: [HomeAnswerSubject] {
        subjects.filter { $0.provenance == .recent }
    }

    private var searchedSubjects: [HomeAnswerSubject] {
        subjects.filter { $0.provenance == .searched }
    }

    private func subjectChipsBar(activeID: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !searchedSubjects.isEmpty {
                subjectChipsSection(
                    title: "Searched",
                    items: searchedSubjects,
                    activeID: activeID,
                    showsTapHint: true
                )
            }

            if !nearbySubjects.isEmpty {
                subjectChipsSection(
                    title: "Nearby",
                    items: nearbySubjects,
                    activeID: activeID,
                    showsTapHint: searchedSubjects.isEmpty
                )
            }

            if !recentSubjects.isEmpty {
                subjectChipsSection(
                    title: "Recent",
                    items: recentSubjects,
                    activeID: activeID,
                    showsTapHint: searchedSubjects.isEmpty && nearbySubjects.isEmpty
                )
            }
        }
        .padding(.bottom, 12)
    }

    private func subjectChipsSection(
        title: String,
        items: [HomeAnswerSubject],
        activeID: String,
        showsTapHint: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Spacer()

                if showsTapHint {
                    Text("Tap to switch")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { subject in
                            subjectChip(subject, isSelected: subject.id == activeID)
                                .id(subject.id)
                        }
                    }
                }
                .contentMargins(.horizontal, 14, for: .scrollContent)
                .onChange(of: selectedSubjectID) { _, newID in
                    if let newID, items.contains(where: { $0.id == newID }) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func subjectChip(_ subject: HomeAnswerSubject, isSelected: Bool) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedSubjectID = subject.id
                expansionOverride = true
            }
        } label: {
            HStack(spacing: 6) {
                MerchantBrandIconView(merchantName: subject.name,
                                      category: subject.prediction.category,
                                      size: 20)

                Text(subject.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.blue : Color.primary)
                    .lineLimit(1)

                // Provenance is stated, never inferred: a pin means Radar returned this place,
                // a clock means it comes from visit history.
                Image(systemName: subject.provenance.symbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(isSelected ? Color.blue.opacity(0.8) : Color.secondary)

                if subject.provenance == .nearby, !isStale,
                   let distance = subject.distanceMeters {
                    Text("\(Int(distance.rounded()))m")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(isSelected ? Color.blue.opacity(0.8) : Color.secondary)
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 9)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue.opacity(0.12) : Color(.tertiarySystemFill),
                        in: Capsule())
            .overlay(
                Capsule().strokeBorder(isSelected ? Color.blue.opacity(0.3) : Color.clear,
                                       lineWidth: 1)
            )
            // Makes the whole capsule tappable rather than only the glyphs and icons inside it.
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show recommendation for \(subject.name), \(subject.provenance.eyebrow.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Recommendation

    @ViewBuilder
    private func recommendationContent(for subject: HomeAnswerSubject) -> some View {
        if deps.walletCards.isEmpty {
            ContentUnavailableView(
                "Add a card to get a pick",
                systemImage: "creditcard.badge.plus",
                description: Text("PickMe only recommends cards you add to your wallet."))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        } else if let eval = InstantRepeatAdvisor.evaluate(
            merchantId: subject.id,
            merchantName: subject.name,
            prediction: subject.prediction,
            amountCad: selectedAmount,
            catalogue: deps.catalogue,
            ownerState: deps.ownerState,
            engine: deps.engine
        ) {
            VStack(alignment: .leading, spacing: 12) {
                winnerRow(eval)
                amountRow(eval)
                actionRow(for: subject)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("At \(subject.name), use \(displayName(for: eval)). \(eval.multiplierText).")
        } else {
            Label("Recommendation unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        }
    }

    private func displayName(for eval: InstantRepeatEvaluation) -> String {
        let short = CardVisualTheme.style(for: eval.winnerCardId).shortName
        return short.isEmpty ? eval.winnerCardName : short
    }

    private func winnerRow(_ eval: InstantRepeatEvaluation) -> some View {
        HStack(alignment: .center, spacing: 14) {
            CardArtView(cardId: eval.winnerCardId,
                        officialName: eval.winnerCardName,
                        isHero: true,
                        cleanArtwork: true)
                .frame(width: 110)
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text("USE THIS CARD")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Text(displayName(for: eval))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(eval.multiplierText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.green)

                if let adv = eval.advantageText, eval.switchedFromDefault {
                    Text(adv)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }

                if let networkBadge = eval.networkBadge {
                    Label(networkBadge, systemImage: "creditcard.trianglebadge.exclamationmark")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private func amountRow(_ eval: InstantRepeatEvaluation) -> some View {
        HStack(spacing: 6) {
            Text("Amount:")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            ForEach([25.0, 50.0, 100.0, 250.0], id: \.self) { amount in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        selectedAmount = amount
                    }
                } label: {
                    Text("$\(Int(amount))")
                        .font(.system(size: 11,
                                      weight: selectedAmount == amount ? .bold : .medium,
                                      design: .rounded))
                        .foregroundStyle(selectedAmount == amount ? Color.blue : Color.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selectedAmount == amount
                                        ? Color.blue.opacity(0.12)
                                        : Color(.tertiarySystemFill),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text(String(format: "$%.2f return", eval.returnCad))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Color.green)
        }
    }

    private func actionRow(for subject: HomeAnswerSubject) -> some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if let walletURL = URL(string: "shoebox://") { openURL(walletURL) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Pay with Apple Wallet")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Color.blue, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: Color.blue.opacity(0.25), radius: 4, x: 0, y: 2)
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                router.step = session.recommend(merchant: subject.merchant,
                                                amount: selectedAmount,
                                                using: deps)
            } label: {
                HStack(spacing: 3) {
                    Text("Breakdown")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(Color.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(Color.blue.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}
