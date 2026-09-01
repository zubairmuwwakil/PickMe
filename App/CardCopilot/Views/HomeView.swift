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
    let onFindNearby: () -> Void
    let onSearch: (String) -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var isFindingNearbyPressed = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedRepeatMerchantID: UUID?
    @State private var greetingEasterEggCount = 0
    @State private var greetingIndex: Int = Int.random(in: 0..<100)
    @State private var showOriginToast = false
    @State private var chipCustomReactionText: String? = nil
    @State private var chipCustomReactionTag: String? = nil
    @State private var chipIsBubblePresented: Bool = false

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

    private var companionStatusText: String {
        if session.locationDenied {
            return "Location access disabled"
        } else if let nearest = session.preparedNearestMerchant {
            return "Nearby: \(nearest.name)"
        } else if case .preparing = session.nearbyPreparationState {
            return "GPS Ready · Scanning nearby"
        } else if let top = session.homeMerchants.first {
            return "Nearby: Ready at \(top.name)"
        } else {
            return "Ready to maximize rewards"
        }
    }

    private var radarStatus: (text: String, icon: String, color: Color) {
        if session.locationDenied {
            return ("Location access disabled · Search still works", "location.slash", .secondary)
        }
        switch session.nearbyPreparationState {
        case .idle:
            return ("Radar starts when needed", "location", .secondary)
        case .permissionRequired:
            return ("Tap Radar to allow location", "hand.tap", .blue)
        case .preparing:
            return ("Preparing nearby merchants…", "location.magnifyingglass", .blue)
        case .ready(let count):
            return count == 0
                ? ("Radar ready · No places within 200 m", "checkmark.circle", .secondary)
                : ("Radar ready · \(count) nearby", "checkmark.circle.fill", .green)
        case .unavailable:
            return ("Radar couldn't prepare · Tap to retry", "arrow.clockwise", .orange)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. Hero Header: Brand, Greeting & Chip Companion
                heroCompanionSection

                // 2. Checkout Radar & Spotlight Search Bar
                primaryCheckoutSection

                // 3. Quick Category Peek Bar
                if let graph = environment.graph {
                    QuickCategoryPeekBar(deps: graph)
                }

                // 4. Instant Repeats (Glanceable Checkout Deck)
                instantRepeatsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 96) // Space for FloatingGlassNavBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            greetingIndex = Int.random(in: 0..<max(1, greetingQuipsForCurrentTime.count))
            if selectedRepeatMerchantID == nil {
                selectedRepeatMerchantID = session.homeMerchants.first?.id
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Only a real trip through the background earns a new greeting. Reshuffling on every
            // `.active` also fired for a dismissed permission alert or a Control Center pull.
            if oldPhase == .background, newPhase == .active {
                greetingIndex = Int.random(in: 0..<max(1, greetingQuipsForCurrentTime.count))
            }
        }
        .onChange(of: session.homeMerchants) { _, newMerchants in
            if let current = selectedRepeatMerchantID, !newMerchants.contains(where: { $0.id == current }) {
                selectedRepeatMerchantID = newMerchants.first?.id
            } else if selectedRepeatMerchantID == nil {
                selectedRepeatMerchantID = newMerchants.first?.id
            }
        }
        .onChange(of: selectedRepeatMerchantID) { oldID, newID in
            if let newID, newID != oldID {
                let impact = UISelectionFeedbackGenerator()
                impact.selectionChanged()
            }
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

    private var ambientInsights: [ChipInsight] {
        guard let graph = environment.graph,
              let top = session.homeMerchants.first else {
            return []
        }

        let signature = [
            top.id.uuidString,
            top.name,
            top.poiCategoryRaw ?? "",
            graph.ownerState.defaultCardId,
            graph.ownerState.ownedCardIds.joined(separator: ","),
            Date().formatted(.iso8601.year().month().day())
        ].joined(separator: "|")

        if ambientInsightMemo.signature == signature {
            return ambientInsightMemo.insights
        }

        let insights = computeAmbientInsights(graph: graph, top: top)
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

    private func computeAmbientInsights(graph: DependencyGraph, top: StoredMerchant) -> [ChipInsight] {
        let prediction = CardCopilotStore.predict(poiCategoryRaw: top.poiCategoryRaw, merchantName: top.name)
        let category = prediction.category
        let nearby = NearbyMerchant(id: top.identifier ?? top.id.uuidString, name: top.name, poiCategoryRaw: top.poiCategoryRaw, latitude: top.latitude, longitude: top.longitude, distanceMeters: nil)

        let purchase = CardCopilotStore.ambientPurchaseContext(merchant: nearby, category: category)
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
    private static let originToastTapCount = 4

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
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                showOriginToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
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
                            router.push(.dashboard)
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

                    Text("PickMe Origin: Built with precision by Zubair Muwwakil so Canadians never get 1x points on a 5x grocery run!")
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

            // Expiring Credits Banner (if any)
            if expiringCreditsCount > 0 {
                Button {
                    router.push(.walletHealth)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.orange)

                        Text("\(expiringCreditsCount) card credit\(expiringCreditsCount == 1 ? "" : "s") expiring soon")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Chip the EMV Micro-Bot Mascot Companion Interactive Card with Pulsing Glow & Live Reaction Binding
            ChipCompanionHeaderCard(
                statusText: companionStatusText,
                subtitle: session.locationDenied
                    ? "Tap settings to enable GPS checkout"
                    : "Tap Chip for quick multiplier tips & merchant rules",
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
                    onFindNearby()
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
            HStack(spacing: 5) {
                Image(systemName: radarStatus.icon)
                    .font(.caption2.weight(.semibold))
                Text(radarStatus.text)
                    .font(.caption2.weight(.medium))
            }
            .foregroundStyle(radarStatus.color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)

            // Dynamic Ambient Location Banner (if nearby merchants prepared)
            if searchText.isEmpty, let graph = environment.graph, !session.preparedNearbyMerchants.isEmpty {
                NearbyRadarDropdownView(
                    merchants: session.preparedNearbyMerchants,
                    deps: graph,
                    onViewAllNearby: { onFindNearby() }
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
                                searchText = ""
                                let merchant = NearbyMerchant(
                                    id: "preindex:\(match.id)",
                                    name: match.name,
                                    poiCategoryRaw: match.category,
                                    latitude: 0,
                                    longitude: 0,
                                    distanceMeters: nil
                                )
                                if let graph = environment.graph {
                                    router.step = session.recommend(merchant: merchant, amount: nil,
                                                                    using: graph)
                                }
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
        }
    }




    // MARK: - 4. Quick Pick

    private var quickPickMerchants: [StoredMerchant] {
        Array(session.homeMerchants.prefix(8))
    }

    private var selectedRepeatMerchant: StoredMerchant? {
        if let selectedRepeatMerchantID,
           let selected = session.homeMerchants.first(where: { $0.id == selectedRepeatMerchantID }) {
            return selected
        }
        return session.homeMerchants.first
    }

    private var instantRepeatsSection: some View {
        Group {
            if let graph = environment.graph, !quickPickMerchants.isEmpty {
                let merchants = quickPickMerchants
                let activeMerchant = selectedRepeatMerchant ?? merchants[0]

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Quick Pick")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Spacer()

                        Label(
                            repeatContext(for: activeMerchant) == .nearby ? "Nearby" : "Recent",
                            systemImage: repeatContext(for: activeMerchant) == .nearby ? "location.fill" : "clock.fill"
                        )
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    }

                    if merchants.count == 1 {
                        InstantRepeatCardView(
                            merchant: merchants[0],
                            deps: graph,
                            context: repeatContext(for: merchants[0])
                        )
                    } else {
                        VStack(spacing: 8) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(merchants) { item in
                                        InstantRepeatCardView(
                                            merchant: item,
                                            deps: graph,
                                            context: repeatContext(for: item)
                                        )
                                        .containerRelativeFrame(.horizontal)
                                        .id(item.id)
                                    }
                                }
                                .scrollTargetLayout()
                            }
                            .scrollTargetBehavior(.viewAligned)
                            .scrollPosition(id: $selectedRepeatMerchantID)

                            HStack(spacing: 6) {
                                ForEach(merchants) { item in
                                    Circle()
                                        .fill(activeMerchant.id == item.id ? Color.blue : Color(.tertiarySystemFill))
                                        .frame(
                                            width: activeMerchant.id == item.id ? 7 : 5,
                                            height: activeMerchant.id == item.id ? 7 : 5
                                        )
                                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: activeMerchant.id)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                        }
                    }

                    if merchants.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Recent places")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Text("Swipe or tap to preview")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.tertiary)
                            }

                            ScrollViewReader { proxy in
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(merchants) { recentMerchant in
                                            recentMerchantButton(recentMerchant)
                                                .id(recentMerchant.id)
                                        }
                                    }
                                }
                                .contentMargins(.horizontal, 1, for: .scrollContent)
                                .onChange(of: selectedRepeatMerchantID) { _, newID in
                                    if let newID {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            proxy.scrollTo(newID, anchor: .center)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: activeMerchant.id)
            }
        }
    }

    private func repeatContext(for merchant: StoredMerchant) -> InstantRepeatContext {
        if session.cachedLocation?.isRecent == true,
           session.homeMerchants.first?.id == merchant.id {
            return .nearby
        }
        return .recent
    }

    private func recentMerchantButton(_ merchant: StoredMerchant) -> some View {
        let prediction = predictionForKnownMerchant(merchant)
        let meta = CategoryVisuals.meta(for: prediction.category)
        let isSelected = (selectedRepeatMerchant?.id ?? quickPickMerchants.first?.id) == merchant.id

        return Button {
            let impact = UISelectionFeedbackGenerator()
            impact.selectionChanged()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selectedRepeatMerchantID = merchant.id
            }
        } label: {
            HStack(spacing: 7) {
                MerchantBrandIconView(
                    merchantName: merchant.name,
                    category: meta.displayName,
                    size: 24
                )

                Text(merchant.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.blue : Color.primary)
                    .lineLimit(1)
            }
            .padding(.leading, 7)
            .padding(.trailing, 10)
            .padding(.vertical, 7)
            .background(
                isSelected ? Color.blue.opacity(0.12) : Color(.tertiarySystemFill),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preview recommendation for \(merchant.name)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func submitSearch() {
        guard let text = SearchSubmission.query(from: searchText) else { return }
        isSearchFocused = false
        onSearch(text)
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
