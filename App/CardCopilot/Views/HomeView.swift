import SwiftUI
import CardCopilotEngine
import CardCopilotStore
import ClerkKit

/// The redesigned, Apple-grade main screen of PickMe.
/// Features Pip the mascot companion, Spotlight search, Checkout Radar,
/// 1-tap quick category peeks, and glanceable instant repeat cards.
struct HomeView: View {
    @Environment(CopilotSession.self) private var session
    @Environment(CheckoutRouter.self) private var router
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(SyncCoordinator.self) private var sync
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    /// The place the answer card is pointed at. A `String` because a subject may come from Radar
    /// (a MapKit POI id) or from visit history (a `StoredMerchant.identifier`).
    @State private var selectedSubjectID: String?
    /// Results of an explicit search submission, rendered inline. Home no longer navigates to a
    /// separate list to answer a question the owner asked from this screen.
    @State private var searchResults: [NearbyPlace] = []
    @State private var searchNotice: String?
    @State private var isSearching = false
    /// A place the owner reached by searching, kept at the head of the chip row so the card can
    /// point at somewhere Radar never returned.
    @State private var pinnedSubject: HomeAnswerSubject?
    @State private var greetingEasterEggCount = 0
    @State private var greetingIndex: Int = Int.random(in: 0..<100)
    @State private var showOriginToast = false
    @State private var chipCustomReactionText: String? = nil
    @State private var chipCustomReactionTag: String? = nil
    @State private var chipIsBubblePresented: Bool = false
    @State private var showPointsFlexSheet = false

    private var userFirstName: String? {
        if let first = ClerkSession.currentUser?.firstName, !first.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return first
        }
        return nil
    }

    private struct DynamicGreetingItem {
        let titlePrefix: String
        let titleSuffix: String
        let iconName: String
        let iconColor: Color
        let subcaption: String
    }

    private var greetingQuipsForCurrentTime: [DynamicGreetingItem] {
        let hour = Calendar.current.component(.hour, from: Date())

        switch hour {
        case 5..<12: // Morning
            return [
                DynamicGreetingItem(
                    titlePrefix: "Rise & optimize,",
                    titleSuffix: "!",
                    iconName: "sun.and.horizon.fill",
                    iconColor: .orange,
                    subcaption: "Don't let Starbucks swipe the wrong card"
                ),
                DynamicGreetingItem(
                    titlePrefix: "Good morning,",
                    titleSuffix: "!",
                    iconName: "cup.and.saucer.fill",
                    iconColor: .orange,
                    subcaption: "5x coffee mode engaged · Breakfast multipliers ready"
                ),
                DynamicGreetingItem(
                    titlePrefix: "Chief Multiplier,",
                    titleSuffix: "!",
                    iconName: "bolt.fill",
                    iconColor: Color(red: 1.0, green: 0.78, blue: 0.18),
                    subcaption: "Brewing maximum multipliers before the world wakes up"
                ),
                DynamicGreetingItem(
                    titlePrefix: "Morning,",
                    titleSuffix: "!",
                    iconName: "sparkles",
                    iconColor: .orange,
                    subcaption: "You and Chip: the points dream team on duty"
                )
            ]

        case 12..<17: // Afternoon
            return [
                DynamicGreetingItem(
                    titlePrefix: "Chief Multiplier,",
                    titleSuffix: "!",
                    iconName: "bolt.fill",
                    iconColor: Color(red: 1.0, green: 0.78, blue: 0.18),
                    subcaption: "Every swipe today is a multiplier waiting to be claimed"
                ),
                DynamicGreetingItem(
                    titlePrefix: "Good afternoon,",
                    titleSuffix: "!",
                    iconName: "sun.max.fill",
                    iconColor: Color(red: 1.0, green: 0.78, blue: 0.18),
                    subcaption: "Lunch is on—let's harvest that 5x return"
                ),
                DynamicGreetingItem(
                    titlePrefix: "Put down the debit,",
                    titleSuffix: "!",
                    iconName: "shield.fill",
                    iconColor: .green,
                    subcaption: "Breaking the 4th wall so you never get 1x on dining"
                ),
                DynamicGreetingItem(
                    titlePrefix: "Afternoon,",
                    titleSuffix: "!",
                    iconName: "target",
                    iconColor: .orange,
                    subcaption: "Point hacking never takes a lunch break"
                ),
                DynamicGreetingItem(
                    titlePrefix: "Hey,",
                    titleSuffix: "!",
                    iconName: "sparkles",
                    iconColor: .orange,
                    subcaption: "Your wallet's favourite partner in crime is on duty"
                )
            ]

        case 17..<22: // Evening
            return [
                DynamicGreetingItem(
                    titlePrefix: "Good evening,",
                    titleSuffix: "!",
                    iconName: "sunset.fill",
                    iconColor: .orange,
                    subcaption: "Amex Cobalt is primed for dinner · 5x dining ready"
                ),
                DynamicGreetingItem(
                    titlePrefix: "Chief Multiplier,",
                    titleSuffix: "!",
                    iconName: "bolt.fill",
                    iconColor: Color(red: 1.0, green: 0.78, blue: 0.18),
                    subcaption: "Dinner reservations? Let's harvest those 5x rewards"
                ),
                DynamicGreetingItem(
                    titlePrefix: "Put down the debit,",
                    titleSuffix: "!",
                    iconName: "shield.fill",
                    iconColor: .green,
                    subcaption: "Ready to outsmart the terminal at checkout"
                ),
                DynamicGreetingItem(
                    titlePrefix: "Evening,",
                    titleSuffix: "!",
                    iconName: "sparkles",
                    iconColor: .orange,
                    subcaption: "Maximum Effort mode: dinner is served"
                )
            ]

        default: // Late Night
            return [
                DynamicGreetingItem(
                    titlePrefix: "Night owl mode,",
                    titleSuffix: "!",
                    iconName: "moon.stars.fill",
                    iconColor: Color(red: 0.45, green: 0.65, blue: 1.0),
                    subcaption: "Midnight snacks still earn multipliers"
                ),
                DynamicGreetingItem(
                    titlePrefix: "Chief Multiplier,",
                    titleSuffix: "!",
                    iconName: "bolt.fill",
                    iconColor: Color(red: 1.0, green: 0.78, blue: 0.18),
                    subcaption: "Running 4,000 interchange algorithms while you sleep"
                ),
                DynamicGreetingItem(
                    titlePrefix: "Good evening,",
                    titleSuffix: "!",
                    iconName: "moon.fill",
                    iconColor: Color(red: 0.45, green: 0.65, blue: 1.0),
                    subcaption: "Late night cravings? We've got the multipliers covered"
                )
            ]
        }
    }

    private var activeGreetingItem: DynamicGreetingItem {
        let list = greetingQuipsForCurrentTime
        return list[greetingIndex % list.count]
    }

    /// Deliberately short. The line this replaced was truncated because a long status string had
    /// taken the headline; a long affordance would simply reintroduce the ellipsis one line down.
    private static let chipAffordance = "Tap Chip for a quick card tip"

    /// The top of Chip's own priority queue: a broken subsystem, else an engine insight,
    /// else a rotation quip, else the affordance.
    ///
    /// This line used to render `"Nearby: <place>"`, which was Radar state wearing a mascot. It
    /// duplicated the status pill and the nearby card, and — because it sat *outside* the queue
    /// below it — it took the most prominent slot even when a broken subsystem was waiting. The
    /// answer card owns "where am I" now, so Chip says what Chip actually has.
    private var chipHeadline: String {
        if let urgent = pinnedChipBanter.first { return urgent.text }
        if let insight = ambientInsights.first { return ChipInsightFormatter.format(insight).text }
        if let rotation = rotationChipBanter.first { return rotation.text }
        return Self.chipAffordance
    }

    /// Never empty: the card falls back to this string for the bubble when Chip has no quip.
    private var chipSubtitle: String {
        chipHeadline == Self.chipAffordance
            ? "Multipliers, caps, and merchant rules"
            : Self.chipAffordance
    }

    /// Every place the answer card can be pointed at, Radar first and visit history after.
    private var answerSubjects: [HomeAnswerSubject] {
        let base = HomeAnswerSubject.merged(nearby: session.preparedNearbyMerchants,
                                            remembered: session.homeMerchants)
        guard let pinnedSubject else { return base }
        return [pinnedSubject] + base.filter { $0.id != pinnedSubject.id }
    }

    /// Only states the owner can act on. "Radar ready · 16 nearby" and "Radar starts when needed"
    /// are gone: the answer card names the place it found and how old the fix is, so the pill
    /// repeating it was the third rendering of one fact. A ready-but-empty scan still speaks,
    /// because in that case there is no card to say anything.
    private var radarStatus: (text: String, icon: String, color: Color, retries: Bool)? {
        if session.locationDenied {
            return ("Location access disabled · Search still works", "location.slash", .secondary,
                    false)
        }
        switch session.nearbyPreparationState {
        case .permissionRequired:
            return ("Tap Radar to allow location", "hand.tap", .blue, false)
        case .preparing:
            return ("Preparing nearby merchants…", "location.magnifyingglass", .blue, false)
        case .ready(let count):
            return count == 0 && answerSubjects.isEmpty
                ? ("Radar ready · No places within 100 m", "checkmark.circle", .secondary, false)
                : nil
        case .unavailable(let reason):
            return (reason.retryStatusText, "arrow.clockwise", .orange, true)
        case .idle:
            return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. Hero Header: Brand, Greeting & Chip Companion
                heroCompanionSection

                // 2. Checkout Radar, Spotlight Search & the answer card
                primaryCheckoutSection

                // 3. The no-merchant fallback. Deliberately *below* the answer card: this asks
                //    the same question at a lower resolution, so it follows the precise answer
                //    rather than preceding it.
                if let graph = environment.graph {
                    QuickCategoryPeekBar(deps: graph) { category in
                        router.push(.categoryPicker(category))
                    }
                }

                // 4. Errands, after the checkout question is answered.
                expiringCreditsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 96) // Space for FloatingGlassNavBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            greetingIndex = Int.random(in: 0..<max(1, greetingQuipsForCurrentTime.count))
            if selectedSubjectID == nil {
                selectedSubjectID = answerSubjects.first?.id
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Only a real trip through the background earns a new greeting. Reshuffling on every
            // `.active` also fired for a dismissed permission alert or a Control Center pull.
            if oldPhase == .background, newPhase == .active {
                greetingIndex = Int.random(in: 0..<max(1, greetingQuipsForCurrentTime.count))
            }
        }
        .onChange(of: selectedSubjectID) { oldID, newID in
            if let newID, newID != oldID {
                UISelectionFeedbackGenerator().selectionChanged()
            }
        }
        .sheet(isPresented: $showPointsFlexSheet) {
            PointsFlexSheetView(
                valueRecoveredCad: session.valueRecoveredCad,
                onOpenDashboard: {
                    router.push(.dashboard)
                }
            )
        }
    }

    // MARK: - 1. Hero Header & Chip Mascot Companion

    /// Memo for `ambientInsights`.
    ///
    /// The property below is read on every body evaluation — which includes once per keystroke
    /// in the search field — and each miss runs merchant prediction plus a full engine
    /// recommendation. Keying the answer on the inputs that can actually change it keeps that
    /// work to once per real change while keeping the property's always-fresh semantics.
    private final class AmbientInsightMemo {
        var signature: String?
        var insights: [ChipInsight] = []
    }
    @State private var ambientInsightMemo = AmbientInsightMemo()

    private var activeAnswerSubject: HomeAnswerSubject? {
        if let selectedSubjectID,
           let match = answerSubjects.first(where: { $0.id == selectedSubjectID }) {
            return match
        }
        return answerSubjects.first
    }

    private var ambientInsights: [ChipInsight] {
        guard let graph = environment.graph,
              let active = activeAnswerSubject else {
            return []
        }

        let signature = [
            active.id,
            active.name,
            active.merchant.poiCategoryRaw ?? "",
            graph.ownerState.defaultCardId,
            graph.ownerState.ownedCardIds.joined(separator: ","),
            Date().formatted(.iso8601.year().month().day())
        ].joined(separator: "|")

        if ambientInsightMemo.signature == signature {
            return ambientInsightMemo.insights
        }

        let insights = computeAmbientInsights(graph: graph, active: active)
        ambientInsightMemo.signature = signature
        ambientInsightMemo.insights = insights
        return insights
    }

    /// Chip's read on whether arrival alerts are actually working.
    ///
    /// A broken subsystem is pinned to the front of his queue; the never-configured case takes
    /// its turn in the ordinary rotation instead, so the mascot mentions the feature without
    /// nagging about it. When alerts are healthy Chip says nothing at all — this is the whole
    /// reason the Home diagnostics card could go away without the failure mode going dark.
    /// Everything Chip has noticed about the app's own health, most pressing first.
    private var chipAdvisories: [ChipAdvisory] {
        ChipAdvisor.evaluate(
            walletIsEmpty: environment.graph?.walletCards.isEmpty ?? true,
            hasSyncIssue: sync.syncIssue != nil,
            ambientIsEnabled: environment.ambientEnabled,
            ambientStatus: environment.ambientRuntimeStatus
        )
    }

    private func banter(for advisory: ChipAdvisory) -> ChipBanterItem {
        ChipBanterItem(
            text: advisory.text,
            mood: advisory.mood,
            tag: advisory.tag,
            action: ChipBanterAction(
                label: advisory.actionLabel,
                systemImage: advisory.isUrgent ? "wrench.and.screwdriver.fill" : "arrow.right.circle.fill",
                perform: { router.push(advisory.destination) }
            )
        )
    }

    private var pinnedChipBanter: [ChipBanterItem] {
        chipAdvisories.filter(\.isUrgent).map(banter(for:))
    }

    private var rotationChipBanter: [ChipBanterItem] {
        chipAdvisories.filter { !$0.isUrgent }.map(banter(for:))
    }

    /// The face Chip wears between reactions. Home already computes the time-of-day tiers for the
    /// greeting; letting the mascot ignore them made him the one part of the screen with no idea
    /// what time it is.
    private var chipRestingMood: ChipMood {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return .idle
        case 12..<17: return .cool
        case 17..<22: return .idle
        default: return .sleepy
        }
    }

    private func computeAmbientInsights(graph: DependencyGraph, active: HomeAnswerSubject) -> [ChipInsight] {
        let category = active.prediction.category
        let purchase = CardCopilotStore.ambientPurchaseContext(merchant: active.merchant, category: category)
        let today = Date().formatted(.iso8601.year().month().day())

        guard case .advised(let rec) = graph.engine.recommend(purchase, asOf: today) else {
            return []
        }

        return ChipInsightAdvisor.evaluate(
            recommendation: rec,
            purchase: purchase,
            catalogue: graph.catalogue,
            defaultCardId: graph.ownerState.defaultCardId
        )
    }

    private var expiringCreditsCount: Int {
        guard let graph = environment.graph else { return 0 }
        let today = Date().formatted(.iso8601.year().month().day())
        let opportunities = CreditAdvisor.opportunities(
            catalogue: graph.catalogue,
            ownerState: graph.ownerState,
            asOf: today
        )
        return opportunities.filter { opp in
            opp.status == .available && (opp.daysRemaining ?? 999) <= 14
        }.count
    }

    private var greetingHeaderView: some View {
        Button {
            triggerGreetingEasterEgg()
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                // Tier 1: Single-Line Flowing Headline with 24K EMV Gold Name
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(activeGreetingItem.titlePrefix)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(userFirstName ?? "Co-Pilot")
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color(red: 1.0, green: 0.86, blue: 0.42),
                                    Color(red: 0.95, green: 0.64, blue: 0.18)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: Color.orange.opacity(0.35), radius: 3, x: 0, y: 1)

                    Text(activeGreetingItem.titleSuffix)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                // Tier 2: Vector Icon + Contextual Subcaption
                HStack(spacing: 5) {
                    Image(systemName: activeGreetingItem.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(activeGreetingItem.iconColor)

                    Text(activeGreetingItem.subcaption)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shuffles the greeting")
    }

    /// Taps needed on the header before Chip volunteers the origin story.
    private static let originToastTapCount = 3

    private func triggerGreetingEasterEgg() {
        greetingEasterEggCount += 1
        withAnimation(.spring(response: 0.32, dampingFraction: 0.75)) {
            greetingIndex += 1
        }
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        if greetingEasterEggCount % Self.originToastTapCount == 0 {
            let notification = UINotificationFeedbackGenerator()
            notification.notificationOccurred(.success)
            for step in 1...3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(step) * 0.08) {
                    impact.impactOccurred(intensity: 0.7)
                }
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showOriginToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
                withAnimation(.easeOut(duration: 0.3)) {
                    showOriginToast = false
                }
            }
        }
    }

    private var heroCompanionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top App Bar: Dynamic Time Greeting & Styled Name on Left + Value Recovered & Cloud Sync Button on Right
            HStack(alignment: .top, spacing: 8) {
                greetingHeaderView

                Spacer(minLength: 4)

                HStack(alignment: .center, spacing: 6) {
                    if session.valueRecoveredCad > 0.005 {
                        Button {
                            showPointsFlexSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .bold))
                                Text(String(format: "+$%.2f earned", session.valueRecoveredCad))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(Color.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View total value recovered")
                    }

                    SyncStatusToolbarButton(
                        isSyncing: sync.isSyncing || sync.isPreparingAccount,
                        lastSyncedAt: sync.lastSyncedAt,
                        syncIssue: sync.syncIssue,
                        action: { router.show(.sync) }
                    )
                }
                .padding(.top, 2)
            }
            .padding(.top, 2)

            // Origin Story Toast (surfaces every originToastTapCount header taps)
            if showOriginToast {
                HStack(spacing: 8) {
                    Image(systemName: "mapleleaf.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.red)

                    Text("Origin Story: PickMe was born out of sheer rage after realizing a grocery store wasn't coded as groceries and gave 1x instead of 5x. Never again!")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 0)

                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.40), lineWidth: 1)
                        )
                )
                .transition(.scale(scale: 0.95).combined(with: .opacity))
            }

            // Chip the EMV Micro-Bot Mascot Companion Interactive Card with Pulsing Glow & Live Reaction Binding
            ChipCompanionHeaderCard(
                statusText: chipHeadline,
                subtitle: chipSubtitle,
                insights: ambientInsights,
                pinnedBanter: pinnedChipBanter,
                rotationBanter: rotationChipBanter,
                activeSearchText: searchText,
                gaze: isSearchFocused ? .down : .wandering,
                restingMood: chipRestingMood,
                externalReactionText: $chipCustomReactionText,
                externalIsBubblePresented: $chipIsBubblePresented,
                externalReactionTag: $chipCustomReactionTag
            )
        }
        .padding(.top, 2)
    }

    // MARK: - 2. Primary Checkout Actions (Unified Search & GPS Radar Bar)

    private var primaryCheckoutSection: some View {
        VStack(spacing: 8) {
            // Unified Search & GPS Radar Capsule
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)

                TextField("Search or Use Radar", text: $searchText)
                    .font(.system(size: 15, weight: .regular))
                    .focused($isSearchFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .onSubmit { submitSearch() }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Button("Search") {
                        submitSearch()
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
                } else {
                    // Microphone Icon as shown in Concept A
                    Image(systemName: "mic.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.65))
                        .padding(.trailing, 2)
                }

                // Trailing 1-Tap GPS Radar Target Button (Exact Concept A Radar Icon)
                Button {
                    let impact = UIImpactFeedbackGenerator(style: .medium)
                    impact.impactOccurred()
                    refreshNearby()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        RadarTargetIconView(size: 36)
                            .opacity(session.nearbyPreparationState == .preparing ? 0.45 : 1)

                        if case .preparing = session.nearbyPreparationState {
                            ProgressView()
                                .controlSize(.mini)
                                .frame(width: 36, height: 36)
                        } else if case .ready = session.nearbyPreparationState {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white, .green)
                                .background(Circle().fill(.white).padding(1))
                                .offset(x: 2, y: -2)
                        }
                    }
                    .shadow(
                        color: session.locationDenied
                            ? Color.clear
                            : Color.blue.opacity(0.25),
                        radius: 4,
                        x: 0,
                        y: 2
                    )
                }
                .buttonStyle(PlainPressableButtonStyle())
                .disabled(session.locationDenied)
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(
                                isSearchFocused
                                    ? Color.blue.opacity(0.6)
                                    : Color.black.opacity(0.04),
                                lineWidth: 1.5
                            )
                    )
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            )

            // Radar Status Pill / Tip
            if let radarStatus {
                if radarStatus.retries {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        refreshNearby()
                    } label: {
                        radarStatusLabel(radarStatus)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Retries the nearby merchant search")
                } else {
                    radarStatusLabel(radarStatus)
                }
            }

            // The single answer surface: Radar results and remembered places, one card, one
            // chip row. Quick Pick used to render this same thing again further down the page.
            if searchText.isEmpty, let graph = environment.graph, !answerSubjects.isEmpty {
                HomeAnswerCardView(
                    subjects: answerSubjects,
                    deps: graph,
                    isStale: session.nearbyResultIsStale,
                    fetchedAt: session.nearbyResultFetchedAt,
                    selectedSubjectID: $selectedSubjectID
                )
            }

            // Instant Offline Pre-Index Autocomplete Dropdown & Easter Egg Matches
            if !searchText.isEmpty {
                let easterEgg = ChipEasterEgg.match(searchText)
                let preIndexMatches = CanadianMerchantPreIndex.search(searchText, limit: 3)
                if easterEgg != nil || !preIndexMatches.isEmpty {
                    VStack(spacing: 4) {
                        if let egg = easterEgg {
                            Button {
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()
                                let notification = UINotificationFeedbackGenerator()
                                notification.notificationOccurred(.success)
                                isSearchFocused = false
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    chipCustomReactionText = egg.dialogue
                                    chipCustomReactionTag = egg.tag
                                    chipIsBubblePresented = true
                                    searchText = ""
                                }
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: egg.iconName)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(egg.tint)
                                        .frame(width: 26, height: 26)
                                        .background(egg.tint.opacity(0.14), in: Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(egg.title)
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                                .foregroundStyle(.primary)

                                            Text(egg.tag)
                                                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                                                .foregroundStyle(egg.tint)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1.5)
                                                .background(egg.tint.opacity(0.14), in: Capsule())
                                        }

                                        Text(egg.subtitle)
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }

                                    Spacer()

                                    Image(systemName: "sparkles")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(egg.tint)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                .strokeBorder(egg.tint.opacity(0.40), lineWidth: 1.2)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        ForEach(preIndexMatches) { match in
                            Button {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                let merchant = NearbyPlace(preIndexed: match)
                                // Re-points the card instead of scoring immediately. Nothing is
                                // written until the owner asks for the breakdown, which keeps a
                                // merchant with no real coordinates out of the store.
                                retarget(merchant, provenance: .searched)
                            } label: {
                                HStack(spacing: 8) {
                                    MerchantBrandIconView(merchantName: match.name, category: match.category, size: 22)

                                    Text(match.name)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)

                                    Text("•")
                                        .foregroundStyle(.tertiary)

                                    Text(match.category)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    if let notes = match.notes {
                                        Text(notes)
                                            .font(.system(size: 11, weight: .medium, design: .rounded))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }

                                    Image(systemName: "arrow.up.left")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(.secondarySystemGroupedBackground))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                    .transition(.opacity)
                }
            }

            submittedSearchResults
        }
    }




    // MARK: - 4. Errands

    /// Expiring credits, moved out of the hero. It is a Perks errand, not an answer to "which
    /// card, here, now", so it no longer sits between the greeting and the checkout question.
    @ViewBuilder
    private var expiringCreditsSection: some View {
        if expiringCreditsCount > 0 {
            Button {
                router.push(.walletHealth)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.orange)

                    Text("\(expiringCreditsCount) card credit\(expiringCreditsCount == 1 ? "" : "s") expiring soon")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Radar & search

    /// Re-runs the scan and updates Home in place.
    ///
    /// This used to call `onFindNearby`, which set `router.step` and pushed the owner to the
    /// merchant list — leaving the screen to answer a question the card on it already displays.
    /// `MerchantConfirmView` still exists, reached from the ambient "which shop is this?" Live
    /// Activity, where the owner has no app context yet and a full list is the right answer.
    private func refreshNearby() {
        guard let graph = environment.graph else { return }
        Task { await session.rescanNearby(using: graph) }
    }

    private func radarStatusLabel(
        _ status: (text: String, icon: String, color: Color, retries: Bool)
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: status.icon)
                .font(.caption2.weight(.semibold))
            Text(status.text)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(status.color)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.leading, 6)
    }

    /// Points the answer card at a place instead of navigating to it.
    private func retarget(_ merchant: NearbyPlace, provenance: HomeSubjectProvenance) {
        UISelectionFeedbackGenerator().selectionChanged()
        isSearchFocused = false
        pinnedSubject = HomeAnswerSubject(nearby: merchant, provenance: provenance)
        selectedSubjectID = merchant.id
        searchText = ""
        searchResults = []
        searchNotice = nil
    }

    @ViewBuilder
    private var submittedSearchResults: some View {
        if !searchText.isEmpty {
            if isSearching {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching…")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if let searchNotice {
                Text(searchNotice)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                ForEach(searchResults) { merchant in
                    Button {
                        retarget(merchant, provenance: .searched)
                    } label: {
                        HStack(spacing: 8) {
                            MerchantBrandIconView(
                                merchantName: merchant.name,
                                category: CardCopilotStore.predict(
                                    poiCategoryRaw: merchant.poiCategoryRaw,
                                    merchantName: merchant.name).category,
                                size: 22)

                            Text(merchant.name)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer()

                            if let distance = merchant.distanceMeters {
                                Text("\(Int(distance.rounded())) m")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }

                            Image(systemName: "arrow.up.left")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Resolves the query on Home. Submitting used to push `MerchantConfirmView`; the results
    /// now render under the search bar and re-point the answer card when tapped, so the owner
    /// never leaves the screen they asked the question from.
    private func submitSearch() {
        guard let text = SearchSubmission.query(from: searchText),
              let graph = environment.graph else { return }
        isSearchFocused = false
        isSearching = true
        searchNotice = nil
        Task {
            let outcome = await session.search(text, using: graph)
            isSearching = false
            switch outcome {
            case .found(let merchants):
                searchResults = merchants
            case .nothingFound(let query):
                searchResults = []
                searchNotice = "Nothing found for “\(query ?? text)”."
            case .failed(let message):
                searchResults = []
                searchNotice = message
            case .locationDenied:
                searchResults = []
                searchNotice = nil
            }
        }
    }
}

/// The concentric radar / sonar target icon shown in Concept A.
struct RadarTargetIconView: View {
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            // Ambient outer soft circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.12, green: 0.50, blue: 1.0).opacity(0.16),
                            Color(red: 0.35, green: 0.65, blue: 1.0).opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)

            // Outer Concentric Radar Ring
            Circle()
                .strokeBorder(Color(red: 0.20, green: 0.55, blue: 1.0).opacity(0.40), lineWidth: 1.2)
                .frame(width: size * 0.78, height: size * 0.78)

            // Inner Concentric Radar Ring
            Circle()
                .strokeBorder(Color(red: 0.15, green: 0.50, blue: 1.0).opacity(0.70), lineWidth: 1.4)
                .frame(width: size * 0.48, height: size * 0.48)

            // Center Sonar Target Dot
            Circle()
                .fill(Color(red: 0.10, green: 0.45, blue: 0.98))
                .frame(width: size * 0.22, height: size * 0.22)
                .shadow(color: Color.blue.opacity(0.8), radius: 3)
        }
        .frame(width: size, height: size)
        .overlay(
            Circle()
                .strokeBorder(Color.blue.opacity(0.15), lineWidth: 0.8)
        )
    }
}

/// A button style providing tactile press scaling.
private struct PlainPressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
    }
}
