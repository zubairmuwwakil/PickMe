import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// The redesigned, Apple-grade main screen of PickMe.
/// Features Pip the mascot companion, Spotlight search, Checkout Radar,
/// 1-tap quick category peeks, and glanceable instant repeat cards.
struct HomeView: View {
    @Environment(CopilotSession.self) private var session
    @Environment(CheckoutRouter.self) private var router
    @Environment(CopilotEnvironment.self) private var environment
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

    private var companionStatusText: String {
        if session.locationDenied {
            return "Location access disabled"
        } else if let cached = session.cachedLocation, cached.isRecent {
            return "GPS Ready · Scanning nearby"
        } else if !session.homeMerchants.isEmpty {
            return "Ready for checkout"
        } else {
            return "Ready to maximize rewards"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. Hero Header: Time Greeting & Pip Mascot Companion
                heroCompanionSection

                // 2. Checkout Radar & Spotlight Search Bar
                primaryCheckoutSection

                // 3. Quick Category Peek Bar
                if let graph = environment.graph {
                    QuickCategoryPeekBar(deps: graph)
                }

                // 4. Instant Repeats (Glanceable Checkout Deck)
                instantRepeatsSection

                // 5. Value Recovered & Experiment Scoreboard Bento
                valueRecoveredCard

                // 6. Ambient Arrival Alert Pill
                ambientDiagnosticsRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 96) // Space for FloatingGlassNavBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - 1. Hero Header & Pip Mascot Companion

    private var heroCompanionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeGreeting)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Which card are you tapping today?")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Queue indicator badge if items are waiting to finish/reconcile
                let pendingCount = session.completionQueue.count + session.reconcileQueue.count
                if pendingCount > 0 {
                    Button { router.selectTab(.activity) } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 7, height: 7)
                            Text("\(pendingCount) to review")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Chip the EMV Micro-Bot Mascot Companion Interactive Card
            ChipCompanionHeaderCard(
                statusText: companionStatusText,
                subtitle: session.locationDenied
                    ? "Tap settings to enable GPS checkout"
                    : "Tap Chip for quick multiplier tips & merchant rules"
            )
        }
        .padding(.top, 2)
    }

    // MARK: - 2. Primary Checkout Actions (Radar + Spotlight)

    private var primaryCheckoutSection: some View {
        VStack(spacing: 10) {
            // "Find Nearby" Hero Radar Card
            Button {
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                onFindNearby()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.20))
                            .frame(width: 44, height: 44)

                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .symbolEffect(.pulse, options: .repeating)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Find Nearby Merchant")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            Image(systemName: "sparkle")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.yellow)
                        }

                        Text(session.locationDenied
                             ? "Location off — tap to retry access"
                             : "Instant 1-tap GPS checkout advice")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: session.locationDenied
                            ? [Color.gray, Color.gray.opacity(0.85)]
                            : [
                                Color(red: 0.08, green: 0.38, blue: 0.95),
                                Color(red: 0.12, green: 0.50, blue: 1.0)
                            ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(
                    color: session.locationDenied
                        ? Color.clear
                        : Color.blue.opacity(0.35),
                    radius: 8,
                    x: 0,
                    y: 4
                )
            }
            .buttonStyle(PlainPressableButtonStyle())
            .disabled(session.locationDenied)

            // Modern Spotlight Search Bar
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Search merchant (e.g. Costco, Loblaws, Tim Hortons)", text: $searchText)
                        .font(.system(size: 14, weight: .regular))
                        .focused($isSearchFocused)
                        .textInputAutocapitalization(.words)
                        .disableAutocorrection(true)
                        .onSubmit { submitSearch() }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)

                        Button("Search") {
                            submitSearch()
                        }
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    isSearchFocused ? Color.blue.opacity(0.6) : Color.black.opacity(0.04),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 1)
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
                                        ZStack {
                                            Circle()
                                                .fill(Color.orange.opacity(0.15))
                                                .frame(width: 22, height: 22)
                                            Image(systemName: "bolt.fill")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(.orange)
                                        }

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
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
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
    }

    // MARK: - 4. Instant Repeats Section

    private var instantRepeatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Instant Repeats")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
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
                LazyVStack(spacing: 12) {
                    ForEach(session.homeMerchants) { merchant in
                        if let graph = environment.graph {
                            InstantRepeatCardView(
                                merchant: merchant,
                                deps: graph,
                                onLogPurchase: { merchant, amount in
                                    session.logInstantPurchase(merchant, amount: amount, using: graph)
                                },
                                onOpenDetails: { merchant, amount in
                                    router.step = session.startInstantRepeatWithAmount(
                                        merchant,
                                        amount: amount,
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
            ChipMascotView(mood: .idle, size: 52)

            VStack(spacing: 4) {
                Text("No Repeats Yet")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Find or search a merchant once, and Chip will build 1-tap checkout tiles here with live CAD returns.")
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
        let meta = CategoryVisuals.meta(for: merchant.confirmedCategory ?? merchant.poiCategoryRaw ?? "general")
        let formattedCategory = CategoryVisuals.humanizePoiCategory(merchant.poiCategoryRaw) ?? meta.displayName
        let relativeTime = CategoryVisuals.relativeTime(from: merchant.lastSeenAt)

        return Button {
            router.step = session.startInstantRepeat(merchant)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(meta.color.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: meta.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(meta.color)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(merchant.name)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(formattedCategory)
                        Text("•")
                        Text(relativeTime)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("Pick")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.blue.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1), in: Capsule())
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 5. Value Recovered & Scoreboard Bento Card

    private var valueRecoveredCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.blue)

                        Text("VALUE RECOVERED")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)
                    }

                    Text(String(format: "$%.2f", session.valueRecoveredCad))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    if session.pendingValueCad > 0 {
                        Text(String(format: "+$%.2f awaiting statement confirmation", session.pendingValueCad))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Experiment status badge
                Button { router.push(.dashboard) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.green)
                        Text("\(session.metrics?.confirmedCount ?? 0)/30 confirmed")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            // Milestone progress bar
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Model Calibration Progress")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((Double(min(session.metrics?.confirmedCount ?? 0, 30)) / 30.0) * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: Double(min(session.metrics?.confirmedCount ?? 0, 30)), total: 30.0)
                    .tint(.blue)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - 6. Ambient Arrival Alert Pill

    private var ambientDiagnosticsRow: some View {
        Button { router.push(.ambientSetup) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(environment.ambientEnabled ? Color.blue.opacity(0.15) : Color(.tertiarySystemFill))
                        .frame(width: 32, height: 32)
                    Image(systemName: environment.ambientEnabled ? "location.circle.fill" : "location.circle")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(environment.ambientEnabled ? .blue : .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Arrival Detection")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(environment.ambientEnabled
                         ? "\(environment.ambientDiagnostics.fired) arrival alerts fired in last 7 days"
                         : "Set up automatic on-device arrival alerts")
                        .font(.system(size: 11, weight: .medium))
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
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func submitSearch() {
        guard let text = SearchSubmission.query(from: searchText) else { return }
        isSearchFocused = false
        onSearch(text)
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
