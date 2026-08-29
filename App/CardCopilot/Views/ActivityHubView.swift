import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// The Activity hub: pending queues, one chronological purchase history, category intelligence,
/// and the experiment scoreboard. Automatic Wallet captures share the history but never the
/// prediction-only metrics.
struct ActivityHubView: View {
    @Environment(CopilotSession.self) private var session
    @Environment(CheckoutRouter.self) private var router
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(SyncCoordinator.self) private var sync

    @State private var selectedCategory: String? = nil
    @State private var isShowingAllPurchases = false
    @State private var inspectingPurchase: StoredPurchase? = nil
    @State private var isChoosingArrivalScope = false

    private struct ArrivalPromptContext {
        let purchase: StoredPurchase
        let merchantKey: String
        let merchantName: String
        let supportsChain: Bool
        let locationIdentifier: String?
        let latitude: Double
        let longitude: Double
    }

    private var availableCategories: [String] {
        let cats = session.recentPurchaseItems.compactMap(category)
        var unique: [String] = []
        for cat in cats where !unique.contains(cat) {
            unique.append(cat)
        }
        return unique
    }

    private var filteredItems: [StoredPurchase] {
        if let selectedCategory {
            return session.recentPurchaseItems.filter { category(for: $0) == selectedCategory }
        }
        return session.recentPurchaseItems
    }

    private var displayedItems: [StoredPurchase] {
        if selectedCategory != nil {
            return filteredItems
        }
        return Array(session.recentPurchaseItems.prefix(5))
    }

    private var filteredCheckoutPurchases: [StoredPrediction] {
        filteredItems.compactMap(\.prediction)
    }

    /// Ask once after the first repeat (two separate visit days), while the exact branch is still
    /// known. Three days remains the threshold only for owners who choose automatic learning.
    private var arrivalPromptContext: ArrivalPromptContext? {
        let patronage = MerchantPatronageStore()
        let preferences = ArrivalAlertPreferenceStore()
        for purchase in session.recentPurchaseItems {
            guard let merchantKey = purchase.merchantKey
                    ?? merchantActivityKey(name: purchase.displayMerchant,
                                           locationIdentifier: purchase.merchantIdentifier),
                  preferences.preference(for: merchantKey) == nil,
                  patronage.visitDayKeys(for: merchantKey).count >= 2 else { continue }

            let stored = session.homeMerchants.first {
                purchase.merchantIdentifier != nil && $0.identifier == purchase.merchantIdentifier
            }
            guard let latitude = purchase.merchantLatitude ?? stored?.latitude,
                  let longitude = purchase.merchantLongitude ?? stored?.longitude,
                  latitude != 0 || longitude != 0 else { continue }
            return ArrivalPromptContext(
                purchase: purchase,
                merchantKey: merchantKey,
                merchantName: purchase.displayMerchant,
                supportsChain: supportsChainArrivalAlerts(merchantKey: merchantKey),
                locationIdentifier: purchase.merchantIdentifier ?? stored?.identifier,
                latitude: latitude,
                longitude: longitude)
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Section: Recent Purchases & Category Intelligence
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recent Purchases")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            if !session.recentPurchaseItems.isEmpty {
                                Text("\(session.recentPurchaseItems.count) total • \(availableCategories.count) categories")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if session.recentPurchaseItems.count > 5 {
                            Button {
                                isShowingAllPurchases = true
                            } label: {
                                Text("See All (\(session.recentPurchaseItems.count))")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    if session.recentPurchaseItems.isEmpty {
                        emptyPurchasesCard
                    } else {
                        // Horizontal Category Filter Pills
                        categoryFilterBar

                        // Category Insight & Cap Card (when filtering or aggregate)
                        if let selectedCategory, !filteredCheckoutPurchases.isEmpty {
                            categoryInsightCard(category: selectedCategory,
                                                purchases: filteredCheckoutPurchases)
                        }

                        // Purchase rows
                        VStack(spacing: 8) {
                            ForEach(displayedItems) { item in
                                Button {
                                    inspectingPurchase = item
                                } label: {
                                    purchaseRow(item)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let prompt = arrivalPromptContext {
                            arrivalAlertPrompt(for: prompt)
                        }
                    }
                }

                // Section: Action Queues
                VStack(alignment: .leading, spacing: 10) {
                    Text("Action Queues")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    VStack(spacing: 8) {
                        // Finish Purchases
                        Button { router.push(.finish) } label: {
                            queueActionRow(
                                icon: "square.and.pencil",
                                iconColor: session.completionQueue.isEmpty ? .green : .blue,
                                title: session.completionQueue.isEmpty ? "Finish Purchases" : "\(session.completionQueue.count) to Finish",
                                subtitle: session.completionQueue.isEmpty ? "All purchases have card & cost recorded" : "Add the card tapped and charge amount",
                                count: session.completionQueue.count,
                                badgeColor: Color.blue
                            )
                        }
                        .buttonStyle(.plain)

                        // Reconcile Statements
                        Button { router.push(.reconcile) } label: {
                            queueActionRow(
                                icon: "tray.full.fill",
                                iconColor: session.reconcileQueue.isEmpty ? .green : .orange,
                                title: session.reconcileQueue.isEmpty ? "Reconcile Queue" : "\(session.reconcileQueue.count) Waiting to Reconcile",
                                subtitle: session.reconcileQueue.isEmpty ? "All predictions confirmed against statements" : "Match posted issuer rewards to predictions",
                                count: session.reconcileQueue.count,
                                badgeColor: Color(red: 0.13, green: 0.77, blue: 0.37)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Section: Experiment Validation & Scoreboard
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Experiment Scoreboard")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Spacer()
                        Button { router.push(.dashboard) } label: {
                            Text("Full Breakdown")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.blue)
                        }
                    }

                    if let metrics = session.metrics {
                        experimentOverviewCard(metrics: metrics)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 90) // Inset for floating glass nav
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $isShowingAllPurchases) {
            AllPurchasesSheetView(
                purchases: session.recentPurchaseItems,
                cards: environment.graph?.walletCards ?? [],
                graph: environment.graph,
                knownMerchants: session.homeMerchants,
                onSelectPurchase: { item in
                    inspectingPurchase = item
                }
            )
        }
        .sheet(item: $inspectingPurchase) { purchase in
            PurchaseDetailSheetView(
                purchase: purchase,
                cards: environment.graph?.walletCards ?? [],
                onFinish: {
                    inspectingPurchase = nil
                    router.push(.finish)
                },
                onReconcile: {
                    inspectingPurchase = nil
                    router.push(.reconcile)
                },
                onUpdateCategory: updateCategory,
                onUpdateAmount: updateAmount
            )
        }
        .confirmationDialog(
            arrivalPromptContext.map { "Arrival alerts for \($0.merchantName)" }
                ?? "Arrival alerts",
            isPresented: $isChoosingArrivalScope,
            titleVisibility: .visible
        ) {
            if let prompt = arrivalPromptContext {
                if prompt.supportsChain {
                    Button("Any \(prompt.merchantName) location") {
                        saveArrivalPreference(.chain, prompt: prompt)
                    }
                }
                Button("Only this location") {
                    saveArrivalPreference(.exactLocation, prompt: prompt)
                }
                Button("Keep learning automatically") {
                    saveArrivalPreference(.automatic, prompt: prompt)
                }
                Button("Don't alert for this merchant", role: .destructive) {
                    saveArrivalPreference(.disabled, prompt: prompt)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if arrivalPromptContext?.supportsChain == true {
                Text("Choose whether PickMe should recognize every branch or only this exact store.")
            } else {
                Text("PickMe can alert you when you return to this exact store.")
            }
        }
    }

    private func updateCategory(_ purchase: StoredPurchase, _ category: String) {
        if let graph = environment.graph {
            session.updateCategory(for: purchase, to: category, using: graph)
        }
    }

    private func updateAmount(_ purchase: StoredPurchase, _ amount: Double) {
        if let graph = environment.graph {
            session.recordAmount(amount, for: purchase, using: graph)
        }
    }

    // MARK: - Category Filter Bar

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" Pill
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedCategory = nil
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("All")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("(\(session.recentPurchaseItems.count))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(selectedCategory == nil ? .white.opacity(0.8) : .secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        selectedCategory == nil
                            ? Color.blue
                            : Color(.secondarySystemGroupedBackground),
                        in: Capsule()
                    )
                    .foregroundStyle(selectedCategory == nil ? .white : .primary)
                    .overlay(
                        Capsule()
                            .strokeBorder(selectedCategory == nil ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // Individual Category Pills
                ForEach(availableCategories, id: \.self) { category in
                    let meta = CategoryVisuals.meta(for: category)
                    let count = session.recentPurchaseItems.filter { self.category(for: $0) == category }.count
                    let isSelected = selectedCategory == category

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedCategory = isSelected ? nil : category
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: meta.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : meta.color)
                            Text(meta.displayName)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text("(\(count))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            isSelected
                                ? meta.color
                                : Color(.secondarySystemGroupedBackground),
                            in: Capsule()
                        )
                        .foregroundStyle(isSelected ? .white : .primary)
                        .overlay(
                            Capsule()
                                .strokeBorder(isSelected ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Category Insight & Cap Card

    private func categoryInsightCard(category: String, purchases: [StoredPrediction]) -> some View {
        let meta = CategoryVisuals.meta(for: category)
        let totalSpend = purchases.reduce(0.0) { sum, p in
            sum + (p.purchase?.amountCad ?? p.scoredAmountCad ?? 0)
        }
        let optimalCount = purchases.filter {
            let cardUsed = $0.purchase?.cardUsedId ?? $0.winnerCardId
            return cardUsed == $0.winnerCardId
        }.count
        let optimalPct = purchases.isEmpty ? 100 : Int(Double(optimalCount) / Double(purchases.count) * 100)

        // Identify any card spend cap for this category in user's cards
        let matchingCap = findCap(for: category)

        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(meta.color.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: meta.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(meta.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(meta.displayName.uppercased()) SPEND INTELLIGENCE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(meta.color)
                    Text(String(format: "$%.2f CAD Total Spend", totalSpend))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button {
                    withAnimation { selectedCategory = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            Divider()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OPTIMAL PICK RATE")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: optimalPct >= 80 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(optimalPct >= 80 ? .green : .orange)
                        Text("\(optimalPct)%")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("TRANSACTIONS")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("\(purchases.count) logged")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }

            // Spend Cap Gauge (if present)
            if let (cardName, limit, period) = matchingCap {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(cardName) \(period.capitalized) Cap")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Spacer()
                        let burnPct = min(100, Int((totalSpend / limit) * 100))
                        Text(String(format: "$%.0f / $%.0f (%d%%)", totalSpend, limit, burnPct))
                            .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(burnPct >= 80 ? .orange : .secondary)
                    }

                    ProgressView(value: min(totalSpend, limit), total: limit)
                        .tint(totalSpend >= limit ? .red : (totalSpend >= limit * 0.8 ? .orange : meta.color))
                }
                .padding(10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(meta.color.opacity(0.3), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        )
    }

    private func findCap(for category: String) -> (cardName: String, limit: Double, period: String)? {
        for card in environment.graph?.walletCards ?? [] {
            for cap in card.caps {
                for rule in card.earnRules where rule.capId == cap.capId {
                    if let categories = rule.predicate.categories, categories.contains(category) {
                        let periodLabel = cap.period == .calendarMonth ? "Monthly" : "Annual"
                        let shortName = CardVisualTheme.styles[card.cardId]?.shortName ?? card.officialName
                        return (shortName, cap.limit, periodLabel)
                    }
                }
            }
        }
        return nil
    }

    private func queueActionRow(
        icon: String,
        iconColor: Color,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        count: Int,
        badgeColor: Color
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor, in: Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
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

    private var emptyPurchasesCard: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.10))
                    .frame(width: 54, height: 54)
                Image(systemName: "bag.badge.plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .padding(.top, 4)

            VStack(spacing: 4) {
                Text("No Purchases Logged Yet")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Pick a card in PickMe or capture a card tap, and every logged purchase will appear here.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
        )
    }

    private func purchaseRow(_ item: StoredPurchase) -> some View {
        let category = category(for: item)
        let meta = CategoryVisuals.meta(for: category ?? "other")
        let tint = category == nil ? Color.secondary : meta.color
        let icon = category == nil ? "wave.3.right" : meta.icon
        let cardId = item.cardUsedId
        let actualAmount = item.amountCad
        let estimatedAmount = actualAmount == nil ? item.prediction?.scoredAmountCad : nil

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayMerchant)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(cardId.map { cardDisplayName(for: $0) } ?? "Card not recorded")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        if let category {
                            Text("•").font(.system(size: 10)).foregroundStyle(.tertiary)
                            Text(CategoryVisuals.meta(for: category).displayName)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Text("•").font(.system(size: 10)).foregroundStyle(.tertiary)
                        Text(CategoryVisuals.relativeTime(from: item.createdAt))
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    if let actualAmount {
                        Text(String(format: "$%.2f", actualAmount))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    } else if let estimatedAmount {
                        Text(String(format: "~$%.2f", estimatedAmount))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if let prediction = item.prediction {
                        statusTag(for: prediction)
                    } else {
                        Text("Card tap")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                }
            }

            cardAssessmentLine(for: item)

            if environment.ambientEnabled && isFrequented(item) {
                Label("Arrival alerts prioritize this merchant", systemImage: "location.circle.fill")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.blue)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
        )
    }

    @ViewBuilder
    private func statusTag(for prediction: StoredPrediction) -> some View {
        if let observation = prediction.purchase?.observation {
            if observation.wasCorrect {
                Text("Reconciled")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12), in: Capsule())
            } else {
                Text(observation.missClass?.rawValue ?? "Mismatch")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            }
        } else if prediction.purchase?.isComplete == true {
            Text("Finished")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.12), in: Capsule())
        } else {
            Text("Needs Info")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.12), in: Capsule())
        }
    }

    @ViewBuilder
    private func cardAssessmentLine(for item: StoredPurchase) -> some View {
        if let graph = environment.graph {
            let assessment = PurchaseActivityEvaluator.cardAssessment(
                for: item, graph: graph, knownMerchants: session.homeMerchants,
                walletFeedback: walletFeedback(for: item))
            HStack(spacing: 6) {
                switch assessment {
                case .best:
                    Label("Best card used", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .better(let cardId, let advantageCad):
                    Label {
                        Text(betterCardText(cardId: cardId, advantageCad: advantageCad))
                    } icon: {
                        Image(systemName: "arrow.up.right.circle.fill")
                    }
                    .foregroundStyle(.orange)
                case .unavailable(let reason):
                    Label(reason, systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(itemSourceLabel(item))
                    .foregroundStyle(.tertiary)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }

    private func betterCardText(cardId: String, advantageCad: Double?) -> String {
        let card = cardDisplayName(for: cardId)
        guard let advantageCad else { return "Better card: \(card)" }
        return String(format: "Better card: %@ · +$%.2f", card, advantageCad)
    }

    private func itemSourceLabel(_ item: StoredPurchase) -> String {
        switch item.resolvedActivitySource {
        case .pickMeCheckout: return "PickMe advised"
        case .walletCapture: return "Auto-captured"
        case .arrivalAlert: return "Arrival alert"
        }
    }

    private func category(for item: StoredPurchase) -> String? {
        PurchaseActivityEvaluator.category(for: item, knownMerchants: session.homeMerchants)
    }

    private func walletFeedback(for item: StoredPurchase) -> WalletFeedback? {
        guard let eventId = item.walletEventId else { return nil }
        return sync.walletFeedback.first { $0.eventId == eventId }
    }

    private func isFrequented(_ item: StoredPurchase) -> Bool {
        guard let key = item.merchantKey
            ?? merchantActivityKey(name: item.displayMerchant,
                                   locationIdentifier: item.merchantIdentifier) else {
            return false
        }
        return MerchantPatronageStore().isFrequented(merchantKey: key)
    }

    private func arrivalAlertPrompt(for prompt: ArrivalPromptContext) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 3) {
                Text("Shop at \(prompt.merchantName) often?")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(prompt.supportsChain
                     ? "Choose any branch, this location only, or let PickMe keep learning."
                     : "Add this exact location, or let PickMe keep learning.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose") { isChoosingArrivalScope = true }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(14)
        .background(Color.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }

    private func saveArrivalPreference(_ scope: ArrivalAlertScope,
                                       prompt: ArrivalPromptContext) {
        ArrivalAlertPreferenceStore().save(ArrivalAlertPreference(
            merchantKey: prompt.merchantKey,
            merchantName: prompt.merchantName,
            scope: scope,
            locationIdentifier: scope == .exactLocation ? prompt.locationIdentifier : nil,
            latitude: scope == .exactLocation ? prompt.latitude : nil,
            longitude: scope == .exactLocation ? prompt.longitude : nil))
        environment.arrivalPreferenceChanged()
        if scope != .disabled, !environment.ambientEnabled { router.push(.ambientSetup) }
    }

    private func cardDisplayName(for cardId: String) -> String {
        if let style = CardVisualTheme.styles[cardId] {
            return style.shortName
        }
        if let product = environment.graph?.walletCards.first(where: { $0.cardId == cardId }) {
            return product.officialName
        }
        return cardId
    }

    private func experimentOverviewCard(metrics: ExperimentMetrics) -> some View {
        VStack(spacing: 16) {
            progressHeader(metrics: metrics)
            ProgressView(value: Double(min(metrics.progressToTarget, metrics.targetCheckouts)), total: Double(metrics.targetCheckouts))
                .tint(.blue)
            Divider()
            metricsGrid(metrics: metrics)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
    }

    private func progressHeader(metrics: ExperimentMetrics) -> some View {
        let progress = Double(min(metrics.progressToTarget, metrics.targetCheckouts))
        let target = Double(metrics.targetCheckouts)
        let percent = Int((progress / target) * 100)

        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("VALIDATION PROGRESS")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(metrics.progressToTarget)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("/ \(metrics.targetCheckouts) checkouts")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 5)
                    .frame(width: 48, height: 48)
                Circle()
                    .trim(from: 0, to: CGFloat(min(progress / target, 1.0)))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 48, height: 48)
                    .rotationEffect(.degrees(-90))
                Text("\(percent)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
    }

    private func metricsGrid(metrics: ExperimentMetrics) -> some View {
        HStack(spacing: 12) {
            metricMiniTile(
                title: "Category Accuracy",
                rate: metrics.categoryAccuracy,
                target: "85%",
                isMet: metrics.meetsCategoryBar == true
            )
            metricMiniTile(
                title: "Math Correctness",
                rate: metrics.arithmeticCorrectRate,
                target: "100%",
                isMet: metrics.meetsArithmeticBar == true
            )
        }
    }

    private func metricMiniTile(
        title: LocalizedStringKey,
        rate: Double?,
        target: String,
        isMet: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if isMet {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            if let rate {
                Text("\(Int(round(rate * 100)))%")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(isMet ? .green : .primary)
            } else {
                Text("—")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text("Target: \(target)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Sheet presenting the complete list of all recent purchases with Category Filtering and Search.
struct AllPurchasesSheetView: View {
    let purchases: [StoredPurchase]
    let cards: [CardProduct]
    let graph: DependencyGraph?
    let knownMerchants: [StoredMerchant]
    let onSelectPurchase: (StoredPurchase) -> Void

    @State private var selectedCategory: String? = nil
    @State private var searchQuery: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync

    private var availableCategories: [String] {
        let cats = purchases.compactMap(category)
        var unique: [String] = []
        for cat in cats where !unique.contains(cat) {
            unique.append(cat)
        }
        return unique
    }

    private var filteredPurchases: [StoredPurchase] {
        purchases.filter { item in
            let itemCategory = category(for: item)
            let matchesCategory = selectedCategory == nil || itemCategory == selectedCategory
            let matchesSearch = searchQuery.isEmpty
                || item.displayMerchant.localizedCaseInsensitiveContains(searchQuery)
                || (itemCategory?.localizedCaseInsensitiveContains(searchQuery) ?? false)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category Filter Bar
                if !availableCategories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            Button {
                                withAnimation { selectedCategory = nil }
                            } label: {
                                Text("All (\(purchases.count))")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(selectedCategory == nil ? Color.blue : Color(.secondarySystemGroupedBackground), in: Capsule())
                                    .foregroundStyle(selectedCategory == nil ? .white : .primary)
                            }
                            .buttonStyle(.plain)

                            ForEach(availableCategories, id: \.self) { category in
                                let meta = CategoryVisuals.meta(for: category)
                                let isSelected = selectedCategory == category
                                Button {
                                    withAnimation { selectedCategory = isSelected ? nil : category }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: meta.icon)
                                            .font(.system(size: 11))
                                            .foregroundStyle(isSelected ? .white : meta.color)
                                        Text(meta.displayName)
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(isSelected ? meta.color : Color(.secondarySystemGroupedBackground), in: Capsule())
                                    .foregroundStyle(isSelected ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .background(Color(.systemGroupedBackground))
                }

                List {
                    ForEach(filteredPurchases) { item in
                        Button {
                            dismiss()
                            onSelectPurchase(item)
                        } label: {
                            allPurchasesRow(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
            }
            .searchable(text: $searchQuery, prompt: "Search merchants or categories")
            .navigationTitle("Purchase History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                }
            }
        }
    }

    private func allPurchasesRow(_ item: StoredPurchase) -> some View {
        let category = category(for: item)
        let meta = CategoryVisuals.meta(for: category ?? "other")
        let tint = category == nil ? Color.secondary : meta.color
        let icon = category == nil ? "wave.3.right" : meta.icon
        let cardId = item.cardUsedId
        let amount = item.amountCad ?? item.prediction?.scoredAmountCad

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayMerchant)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text(cardId.map { cardDisplayName(for: $0) } ?? "Card not recorded")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    if let category {
                        Text("•").font(.system(size: 10)).foregroundStyle(.tertiary)
                        Text(CategoryVisuals.meta(for: category).displayName)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(item.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let amount {
                    Text(String(format: "$%.2f", amount))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                if let graph {
                    assessmentLabel(PurchaseActivityEvaluator.cardAssessment(
                        for: item, graph: graph, knownMerchants: knownMerchants,
                        walletFeedback: walletFeedback(for: item)))
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func assessmentLabel(_ assessment: PurchaseCardAssessment) -> some View {
        switch assessment {
        case .best:
            Label("Best card", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .better(let cardId, _):
            Text("Better: \(cardDisplayName(for: cardId))")
                .foregroundStyle(.orange)
        case .unavailable:
            Text("Not compared")
                .foregroundStyle(.secondary)
        }
    }

    private func category(for item: StoredPurchase) -> String? {
        PurchaseActivityEvaluator.category(for: item, knownMerchants: knownMerchants)
    }

    private func walletFeedback(for item: StoredPurchase) -> WalletFeedback? {
        guard let eventId = item.walletEventId else { return nil }
        return sync.walletFeedback.first { $0.eventId == eventId }
    }

    private func cardDisplayName(for cardId: String) -> String {
        if let style = CardVisualTheme.styles[cardId] {
            return style.shortName
        }
        if let product = cards.first(where: { $0.cardId == cardId }) {
            return product.officialName
        }
        return cardId
    }
}

/// Inspection sheet showing the full breakdown, cap context, and 1-tap category correction.
struct PurchaseDetailSheetView: View {
    let purchase: StoredPurchase
    let cards: [CardProduct]
    let onFinish: () -> Void
    let onReconcile: () -> Void
    let onUpdateCategory: (StoredPurchase, String) -> Void
    let onUpdateAmount: (StoredPurchase, Double) -> Void

    @State private var currentCategory: String
    @State private var isChangingCategory = false
    @State private var isEnteringAmount = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    init(
        purchase: StoredPurchase,
        cards: [CardProduct],
        onFinish: @escaping () -> Void,
        onReconcile: @escaping () -> Void,
        onUpdateCategory: @escaping (StoredPurchase, String) -> Void,
        onUpdateAmount: @escaping (StoredPurchase, Double) -> Void
    ) {
        self.purchase = purchase
        self.cards = cards
        self.onFinish = onFinish
        self.onReconcile = onReconcile
        self.onUpdateCategory = onUpdateCategory
        self.onUpdateAmount = onUpdateAmount
        _currentCategory = State(initialValue: purchase.displayCategory ?? "other")
    }

    private var prediction: StoredPrediction? { purchase.prediction }

    private var recommendedCardId: String? {
        purchase.bestCardId ?? prediction?.winnerCardId
    }

    private var selectableCategories: [String] {
        let catalogueCategories = cards.flatMap { card in
            card.earnRules.flatMap { $0.predicate.categories ?? [] }
        }
        return Array(Set(catalogueCategories + ["other"]))
            .sorted { CategoryVisuals.meta(for: $0).displayName
                < CategoryVisuals.meta(for: $1).displayName }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header card
                    let meta = CategoryVisuals.meta(for: currentCategory)
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(meta.color.opacity(0.14))
                                .frame(width: 64, height: 64)
                            Image(systemName: meta.icon)
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(meta.color)
                        }

                        VStack(spacing: 4) {
                            Text(purchase.displayMerchant)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            if let amount = purchase.amountCad {
                                Text(String(format: "$%.2f CAD", amount))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                            } else if let scored = prediction?.scoredAmountCad {
                                Text(String(format: "~$%.2f CAD (Estimated)", scored))
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Amount not recorded")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.top, 8)

                    // Details Section
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Transaction Details")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 12) {
                            detailRow(
                                title: "Card Tapped",
                                value: purchase.cardUsedId.map { cardDisplayName(for: $0) }
                                    ?? "Not recorded",
                                icon: "creditcard.fill",
                                color: .blue
                            )
                            if let recommendedCardId {
                                Divider()
                                detailRow(
                                    title: "Recommended Card",
                                    value: cardDisplayName(for: recommendedCardId),
                                    icon: "star.fill",
                                    color: .yellow
                                )
                            }
                            Divider()

                            Button {
                                isChangingCategory = true
                            } label: {
                                HStack {
                                    Image(systemName: "tag.fill")
                                        .font(.system(size: 15))
                                        .foregroundStyle(meta.color)
                                        .frame(width: 24)

                                    Text("Category")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    HStack(spacing: 6) {
                                        Text(purchase.displayCategory == nil
                                             ? "Add category" : meta.displayName)
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(purchase.displayCategory == nil
                                                             ? .blue : .primary)
                                        Image(systemName: "pencil.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .buttonStyle(.plain)

                            Divider()
                            detailRow(
                                title: "Date & Time",
                                value: purchase.createdAt.formatted(date: .abbreviated, time: .shortened),
                                icon: "clock.fill",
                                color: .purple
                            )
                            Divider()
                            if let locationURL {
                                Button { openURL(locationURL) } label: {
                                    HStack {
                                        detailRow(
                                            title: "Location",
                                            value: "Open in Maps",
                                            icon: "location.fill",
                                            color: .blue
                                        )
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            } else {
                                detailRow(
                                    title: "Location",
                                    value: "Not captured",
                                    icon: "location.slash.fill",
                                    color: .secondary
                                )
                            }
                            Divider()
                            detailRow(
                                title: "Captured Via",
                                value: activitySourceLabel,
                                icon: activitySourceIcon,
                                color: .teal
                            )
                            Divider()
                            detailRow(
                                title: "Status",
                                value: statusLabel,
                                icon: purchase.isComplete
                                    ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                                color: purchase.isComplete ? .green : .orange
                            )
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }

                    if purchase.amountCad == nil {
                        Button { isEnteringAmount = true } label: {
                            Label("Add Missing Amount", systemImage: "dollarsign.circle.fill")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 14,
                                                                            style: .continuous))
                                .foregroundStyle(.white)
                        }
                    }

                    // Advice Headline
                    if let prediction, !prediction.headline.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recommendation Advice")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)

                            HStack(spacing: 12) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.yellow)
                                Text(prediction.headline)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                        }
                    }

                    // Action buttons if unfinished or unreconciled
                    if prediction != nil, purchase.missingFacts.contains(.card) {
                        Button(action: onFinish) {
                            Label("Finish This Purchase", systemImage: "pencil.and.list.clipboard")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 8)
                    } else if prediction != nil, purchase.isComplete,
                              purchase.observation == nil {
                        Button(action: onReconcile) {
                            Label("Reconcile in Queue", systemImage: "tray.full.fill")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.orange, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Purchase Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                }
            }
            .sheet(isPresented: $isChangingCategory) {
                CategoryChangeSheetView(
                    currentCategory: currentCategory,
                    categories: selectableCategories,
                    onSelectCategory: { newCategory in
                        currentCategory = newCategory
                        onUpdateCategory(purchase, newCategory)
                        isChangingCategory = false
                    }
                )
            }
            .sheet(isPresented: $isEnteringAmount) {
                PurchaseAmountEntrySheetView(
                    merchantName: purchase.displayMerchant,
                    onSave: { amount in
                        onUpdateAmount(purchase, amount)
                        isEnteringAmount = false
                    },
                    onCancel: { isEnteringAmount = false }
                )
            }
        }
    }

    private var locationURL: URL? {
        guard let latitude = purchase.merchantLatitude,
              let longitude = purchase.merchantLongitude,
              latitude != 0 || longitude != 0 else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")
        components?.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: purchase.displayMerchant),
        ]
        return components?.url
    }

    private var activitySourceLabel: String {
        switch purchase.resolvedActivitySource {
        case .pickMeCheckout: return "PickMe checkout"
        case .walletCapture: return "Apple Wallet card tap"
        case .arrivalAlert: return "Arrival alert"
        }
    }

    private var activitySourceIcon: String {
        switch purchase.resolvedActivitySource {
        case .pickMeCheckout: return "sparkles"
        case .walletCapture: return "wave.3.right"
        case .arrivalAlert: return "location.circle.fill"
        }
    }

    private var statusLabel: String {
        if !purchase.isComplete { return "Needs information" }
        guard prediction != nil else { return "Captured" }
        return purchase.observation == nil ? "Finished" : "Reconciled"
    }

    private func detailRow(title: LocalizedStringKey, value: String, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .frame(width: 24)

            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
    }

    private func cardDisplayName(for cardId: String) -> String {
        if let style = CardVisualTheme.styles[cardId] {
            return style.shortName
        }
        if let product = cards.first(where: { $0.cardId == cardId }) {
            return product.officialName
        }
        return cardId
    }
}

/// A focused receipt-total editor for purchases whose Wallet capture omitted or could not decode
/// the amount. This is intentionally smaller than the checkout amount screen: the purchase
/// already exists and only one missing fact is being supplied.
struct PurchaseAmountEntrySheetView: View {
    let merchantName: String
    let onSave: (Double) -> Void
    let onCancel: () -> Void

    @State private var amountText = ""
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Purchase") {
                    LabeledContent("Merchant", value: merchantName)
                }

                Section {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("Amount charged", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($isAmountFocused)
                    }
                } header: {
                    Text("What did it come to?")
                } footer: {
                    Text("Enter the total from your receipt. It will be marked as added manually, not captured from Wallet.")
                }
            }
            .navigationTitle("Add Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let amount { onSave(amount) }
                    }
                    .disabled(amount == nil)
                }
            }
            .onAppear { isAmountFocused = true }
        }
    }

    private var amount: Double? {
        let cleaned = amountText
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }
}

/// 1-Tap Category picker modal for fast transaction reclassification.
struct CategoryChangeSheetView: View {
    let currentCategory: String
    let categories: [String]
    let onSelectCategory: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(categories, id: \.self) { category in
                        let meta = CategoryVisuals.meta(for: category)
                        let isSelected = category == currentCategory

                        Button {
                            onSelectCategory(category)
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(meta.color.opacity(isSelected ? 0.25 : 0.12))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: meta.icon)
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(meta.color)
                                }

                                Text(meta.displayName)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(isSelected ? meta.color : Color.clear, lineWidth: 2)
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reclassify Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
