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

    private var timeGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hello"
        }
    }

    private var personalizedGreeting: String {
        if let first = Clerk.shared.user?.firstName, !first.isEmpty {
            return "\(timeGreeting), \(first)!"
        }
        return "\(timeGreeting)!"
    }

    private var companionStatusText: String {
        if session.locationDenied {
            return "Location access disabled"
        } else if let cached = session.cachedLocation, cached.isRecent {
            return "GPS Ready · Scanning nearby"
        } else if let top = session.homeMerchants.first {
            return "Nearby: Ready at \(top.name)"
        } else {
            return "Ready to maximize rewards"
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

                // 5. Ambient Arrival Alert Pill
                ambientDiagnosticsRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 96) // Space for FloatingGlassNavBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 1. Hero Header & Chip Mascot Companion

    private var ambientInsights: [ChipInsight] {
        guard let graph = environment.graph,
              let top = session.homeMerchants.first else {
            return []
        }
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

    private var heroCompanionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top App Bar: PickMe Brand Logo on Left + Cloud Sync Button on Right
            HStack(alignment: .center) {
                Text("PickMe")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.08, green: 0.48, blue: 0.98))

                Spacer()

                SyncStatusToolbarButton(
                    isSyncing: sync.isSyncing || sync.isPreparingAccount,
                    lastSyncedAt: sync.lastSyncedAt,
                    syncIssue: sync.syncIssue,
                    action: { router.show(.sync) }
                )
            }
            .padding(.top, 2)

            // Dynamic Greeting
            Text(personalizedGreeting)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            // Chip the EMV Micro-Bot Mascot Companion Interactive Card with Pulsing Glow
            ChipCompanionHeaderCard(
                statusText: companionStatusText,
                subtitle: session.locationDenied
                    ? "Tap settings to enable GPS checkout"
                    : "Tap Chip for quick multiplier tips & merchant rules",
                insights: ambientInsights
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
                    .disableAutocorrection(true)
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
                    RadarTargetIconView(size: 36)
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

            // Instant Offline Pre-Index Autocomplete Dropdown
            if !searchText.isEmpty {
                let preIndexMatches = CanadianMerchantPreIndex.search(searchText, limit: 3)
                if !preIndexMatches.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(preIndexMatches) { match in
                            Button {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                                searchText = ""
                                router.step = .amount(NearbyMerchant(
                                    id: "preindex:\(match.id)",
                                    name: match.name,
                                    poiCategoryRaw: match.category,
                                    latitude: 0,
                                    longitude: 0,
                                    distanceMeters: nil
                                ))
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

    // MARK: - 4. Instant Repeats Section (Concept A 2-Column Grid)

    private var instantRepeatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Instant Repeats")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                if !session.homeMerchants.isEmpty {
                    Label(
                        session.cachedLocation?.isRecent == true ? "Nearby Places" : "Recent Places",
                        systemImage: session.cachedLocation?.isRecent == true ? "location.fill" : "clock.fill"
                    )
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }

            if session.homeMerchants.isEmpty {
                emptyRepeatsCard
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(session.homeMerchants) { merchant in
                        if let graph = environment.graph {
                            InstantRepeatCardView(
                                merchant: merchant,
                                deps: graph,
                                onSelect: { merchant in
                                    router.step = session.startInstantRepeatWithAmount(
                                        merchant,
                                        amount: 50,
                                        using: graph
                                    )
                                }
                            )
                        } else {
                            fallbackMerchantRow(merchant)
                        }
                    }
                }
            }
        }
    }

    private var emptyRepeatsCard: some View {
        VStack(spacing: 12) {
            ChipMascotView(mood: .cool, size: 52, isWaving: true, enable3DTilt: true)

            VStack(spacing: 4) {
                Text("No Repeats Yet")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Search a merchant once or tap GPS Radar, and I'll build live reward checkout tiles right here inside your screen!")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
    }

    private func fallbackMerchantRow(_ merchant: StoredMerchant) -> some View {
        let prediction = predictionForKnownMerchant(merchant)
        let meta = CategoryVisuals.meta(for: prediction.category)

        return Button {
            router.step = session.startInstantRepeat(merchant)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(meta.color.opacity(0.18))
                    .aspectRatio(85.60 / 53.98, contentMode: .fit)

                HStack(spacing: 6) {
                    MerchantBrandIconView(merchantName: merchant.name, category: meta.displayName, size: 20)
                    Text(merchant.name)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 5. Ambient Arrival Alert Section

    private var ambientDiagnosticsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Smart Automation")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.8)
                .padding(.horizontal, 2)

            Button { router.push(.ambientSetup) } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(environment.ambientEnabled ? Color.blue.opacity(0.15) : Color(.tertiarySystemFill))
                            .frame(width: 36, height: 36)
                        Image(systemName: environment.ambientEnabled ? "location.circle.fill" : "location.circle")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(environment.ambientEnabled ? .blue : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Arrival Detection")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(environment.ambientEnabled
                             ? "\(environment.ambientDiagnostics.fired) arrival alerts fired in last 7 days"
                             : "Set up automatic on-device arrival alerts")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !environment.ambientEnabled {
                        Text("Set up")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                    }

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
                )
            }
            .buttonStyle(.plain)
        }
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
