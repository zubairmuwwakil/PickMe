import SwiftUI
import CardCopilotEngine
import CardCopilotStore

struct HomeView: View {
    @Environment(CopilotSession.self) private var session
    @Environment(CheckoutRouter.self) private var router
    @Environment(CopilotEnvironment.self) private var environment
    let onFindNearby: () -> Void
    let onSearch: (String) -> Void

    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                primaryCheckoutSection
                instantRepeatsSection
                ambientDiagnosticsRow
                valueRecoveredCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 90)
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
    }

    private var ambientDiagnosticsRow: some View {
        Button { router.push(.ambientSetup) } label: {
            HStack(spacing: 12) {
                Image(systemName: environment.ambientEnabled ? "location.circle.fill" : "location.circle")
                    .font(.title3)
                    .foregroundStyle(environment.ambientEnabled ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Arrival alerts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(environment.ambientEnabled
                         ? "Last 7 days: \(environment.ambientDiagnostics.fired) fired · \(environment.ambientDiagnostics.suppressed) suppressed"
                         : "Set up on-device arrival detection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !environment.ambientEnabled {
                    Text("Set up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Value Recovered & Experiment Banner

    private var valueRecoveredCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tint)
                        Text("VALUE RECOVERED")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.0)
                            .foregroundStyle(.secondary)
                    }

                    Text(String(format: "$%.2f", session.valueRecoveredCad))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .contentTransition(.numericText())

                    if session.pendingValueCad > 0 {
                        Text(String(format: "+$%.2f awaiting your statement", session.pendingValueCad))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Experiment status badge
                Button { router.push(.dashboard) } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green)
                        Text("\(session.metrics?.confirmedCount ?? 0)/30 confirmed")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            // Progress bar to 30 checkouts
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Experiment Progress")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((Double(min(session.metrics?.confirmedCount ?? 0, 30)) / 30.0) * 100))%")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: Double(min(session.metrics?.confirmedCount ?? 0, 30)), total: 30.0)
                    .tint(.blue)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - Primary Checkout Actions

    private var primaryCheckoutSection: some View {
        VStack(spacing: 12) {
            // Hero Find Nearby Button
            Button(action: onFindNearby) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 42, height: 42)
                        Image(systemName: "location.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Find Nearby Merchant")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(session.locationDenied ? "Location off — tap to retry" : "One-tap GPS check at checkout")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: session.locationDenied
                            ? [Color.gray, Color.gray.opacity(0.8)]
                            : [Color.blue, Color(red: 0.1, green: 0.45, blue: 0.95)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: session.locationDenied ? Color.clear : Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(session.locationDenied)

            // Modern Integrated Search Bar
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)

                    TextField("Search merchant (e.g. Costco, Loblaws)", text: $searchText)
                        .font(.system(size: 15))
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.blue)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(isSearchFocused ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 1.5)
                        )
                )

                // Instant Offline Pre-Index Autocomplete
                if !searchText.isEmpty {
                    let preIndexMatches = CanadianMerchantPreIndex.search(searchText, limit: 3)
                    if !preIndexMatches.isEmpty {
                        VStack(spacing: 4) {
                            ForEach(preIndexMatches) { match in
                                Button {
                                    searchText = ""
                                    router.step = .amount(NearbyMerchant(id: "preindex:\(match.id)",
                                                                         name: match.name,
                                                                         poiCategoryRaw: match.category,
                                                                         latitude: 0,
                                                                         longitude: 0,
                                                                         distanceMeters: nil))
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "bolt.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                        Text(match.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Text("•")
                                            .foregroundStyle(.tertiary)
                                        Text(match.category)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        if let notes = match.notes {
                                            Text(notes)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                                .lineLimit(1)
                                        }
                                        Image(systemName: "arrow.up.left")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
        }
    }

    // MARK: - Instant Repeats Section

    private var instantRepeatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Instant Repeats")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Spacer()

                if !session.homeMerchants.isEmpty {
                    Label(session.cachedLocation?.isRecent == true ? "Nearby" : "Recent",
                          systemImage: session.cachedLocation?.isRecent == true ? "location.fill" : "clock.fill")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }

            if session.homeMerchants.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No repeats yet")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Find or search a merchant once, then this list gives you instant 1-tap checkout advice.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
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
                                    router.step = session.startInstantRepeatWithAmount(merchant, amount: amount,
                                                                                         using: graph)
                                }
                            )
                        } else {
                            merchantRow(merchant)
                        }
                    }
                }
            }
        }
    }

    private func merchantRow(_ merchant: StoredMerchant) -> some View {
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
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(formattedCategory)
                        Text("•")
                        Text(relativeTime)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("Pick")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
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

    // MARK: - Tools & Experiment Hub

    private var toolsAndExperimentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wallet & Tools")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            VStack(spacing: 10) {
                // Which Card? — a no-amount category lookup, so it belongs before anything that
                // needs a purchase already in progress.
                Button { router.push(.categoryPicker) } label: {
                    toolRow(
                        icon: "square.grid.2x2.fill",
                        iconColor: .teal,
                        title: "Which Card?",
                        subtitle: "Pick a category, see the card",
                        badge: nil,
                        badgeColor: .teal
                    )
                }
                .buttonStyle(.plain)

                // Wallet Health (keep/cancel)
                Button { router.push(.walletHealth) } label: {
                    toolRow(
                        icon: "heart.text.square.fill",
                        iconColor: .mint,
                        title: "Wallet Health",
                        subtitle: "What to keep, cancel, or add — marginal, not gross",
                        badge: "Estimate",
                        badgeColor: .mint
                    )
                }
                .buttonStyle(.plain)

                // Point Valuation Sandbox
                Button { router.push(.valuationSandbox) } label: {
                    toolRow(
                        icon: "slider.horizontal.3",
                        iconColor: .purple,
                        title: "Valuation Sandbox",
                        subtitle: "What-If sensitivity for MR, Aeroplan, Scene+, Avion",
                        badge: "Live",
                        badgeColor: .purple
                    )
                }
                .buttonStyle(.plain)

                // Finish Purchases Row. Placed above Reconcile because it gates it: a purchase
                // missing its card or its charge cannot be checked against a statement yet.
                Button { router.push(.finish) } label: {
                    toolRow(
                        icon: "square.and.pencil",
                        iconColor: session.completionQueue.isEmpty ? .green : .blue,
                        title: session.completionQueue.isEmpty ? "Finish Purchases" : "\(session.completionQueue.count) to Finish",
                        subtitle: session.completionQueue.isEmpty ? "Every purchase has its card and amount" : "Add the card you tapped and what it cost",
                        badge: session.completionQueue.isEmpty ? nil : "\(session.completionQueue.count)",
                        badgeColor: .blue
                    )
                }
                .buttonStyle(.plain)

                // Reconcile Queue Row
                Button { router.push(.reconcile) } label: {
                    toolRow(
                        icon: "tray.full.fill",
                        iconColor: session.reconcileQueue.isEmpty ? .green : .orange,
                        title: session.reconcileQueue.isEmpty ? "Reconcile Queue" : "\(session.reconcileQueue.count) Waiting to Reconcile",
                        subtitle: session.reconcileQueue.isEmpty ? "All predictions matched to statements" : "Match posted rewards against predictions",
                        badge: session.reconcileQueue.isEmpty ? nil : "\(session.reconcileQueue.count)",
                        badgeColor: .orange
                    )
                }
                .buttonStyle(.plain)

                // Experiment Dashboard
                Button { router.push(.dashboard) } label: {
                    toolRow(
                        icon: "chart.bar.fill",
                        iconColor: .blue,
                        title: "Experiment Scoreboard",
                        subtitle: "Category accuracy & arithmetic correctness",
                        badge: nil,
                        badgeColor: .blue
                    )
                }
                .buttonStyle(.plain)

                // Protection Lens
                Button { router.push(.protectionLens(BenefitContext(kind: .flight))) } label: {
                    toolRow(
                        icon: "shield.lefthalf.filled",
                        iconColor: .indigo,
                        title: "Big Purchase or Trip Lens",
                        subtitle: "Compare insurance, CDW & extended warranty",
                        badge: "Advisory",
                        badgeColor: .indigo
                    )
                }
                .buttonStyle(.plain)

                // Card Benefits
                Button { router.push(.benefitsReference) } label: {
                    toolRow(
                        icon: "creditcard.and.123",
                        iconColor: .purple,
                        title: "Card Benefits Library",
                        subtitle: "Verified certificate coverage per card",
                        badge: nil,
                        badgeColor: .purple
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toolRow(
        icon: String,
        iconColor: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        badge: String?,
        badgeColor: Color
    ) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(badgeColor, in: Capsule())
                    }
                }

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func submitSearch() {
        guard let text = SearchSubmission.query(from: searchText) else { return }
        isSearchFocused = false
        onSearch(text)
    }
}
