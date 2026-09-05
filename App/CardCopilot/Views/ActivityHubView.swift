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
    @State private var filterNeedsAttention = false
    @State private var isShowingAllPurchases = false
    @State private var inspectingPurchase: StoredPurchase? = nil
    @State private var quickAmountPurchase: StoredPurchase? = nil
    @State private var quickCategoryPurchase: StoredPurchase? = nil
    @State private var quickCardPurchase: StoredPurchase? = nil
    @State private var quickDeletePurchase: StoredPurchase? = nil
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

    private var needsAttentionPurchases: [StoredPurchase] {
        session.recentPurchaseItems.filter { item in
            PurchaseAttentionEvaluator.needsAttention(
                item,
                graph: environment.graph,
                knownMerchants: session.homeMerchants,
                walletFeedback: walletFeedback(for: item)
            )
        }
    }

    private var filteredItems: [StoredPurchase] {
        if filterNeedsAttention {
            return needsAttentionPurchases
        }
        if let selectedCategory {
            return session.recentPurchaseItems.filter { category(for: $0) == selectedCategory }
        }
        return session.recentPurchaseItems
    }

    private var filteredCheckoutPurchases: [StoredPrediction] {
        filteredItems.compactMap(\.prediction)
    }

    // MARK: - Robust Date Grouping

    private struct PurchaseSection: Identifiable {
        let id: String
        let title: String
        let items: [StoredPurchase]
    }

    private var purchaseSections: [PurchaseSection] {
        let sorted = Array(filteredItems.sorted { $0.createdAt > $1.createdAt }.prefix(5))
        let calendar = Calendar.current
        var sections: [PurchaseSection] = []

        let todayItems = sorted.filter { calendar.isDateInToday($0.createdAt) }
        if !todayItems.isEmpty {
            sections.append(PurchaseSection(id: "today", title: "Today", items: todayItems))
        }

        let yesterdayItems = sorted.filter { calendar.isDateInYesterday($0.createdAt) }
        if !yesterdayItems.isEmpty {
            sections.append(PurchaseSection(id: "yesterday", title: "Yesterday", items: yesterdayItems))
        }

        let thisWeekItems = sorted.filter { item in
            !calendar.isDateInToday(item.createdAt)
            && !calendar.isDateInYesterday(item.createdAt)
            && (calendar.dateComponents([.day], from: item.createdAt, to: Date()).day ?? 99) < 7
            && (calendar.dateComponents([.day], from: item.createdAt, to: Date()).day ?? -1) >= 0
        }
        if !thisWeekItems.isEmpty {
            sections.append(PurchaseSection(id: "thisWeek", title: "This Week", items: thisWeekItems))
        }

        let earlierItems = sorted.filter { item in
            !calendar.isDateInToday(item.createdAt)
            && !calendar.isDateInYesterday(item.createdAt)
            && ((calendar.dateComponents([.day], from: item.createdAt, to: Date()).day ?? 99) >= 7
                || (calendar.dateComponents([.day], from: item.createdAt, to: Date()).day ?? 0) < 0)
        }
        if !earlierItems.isEmpty {
            sections.append(PurchaseSection(id: "earlier", title: "Earlier", items: earlierItems))
        }

        // Fallback: if all items failed specific date buckets, group all into one
        if sections.isEmpty && !sorted.isEmpty {
            sections.append(PurchaseSection(id: "all", title: "Recent Activity", items: sorted))
        }

        return sections
    }

    // MARK: - Overview Pulse Stats

    private var totalSpendAmount: Double {
        filteredItems.reduce(0.0) { sum, item in
            sum + (item.amountCad ?? item.prediction?.scoredAmountCad ?? 0)
        }
    }

    private var optimalStats: (optimalCount: Int, evaluatedCount: Int, percent: Int, totalAdvantageCad: Double) {
        guard let graph = environment.graph else { return (0, 0, 100, 0) }
        var optimal = 0
        var evaluated = 0
        var advantageSum: Double = 0

        for item in filteredItems {
            let assessment = PurchaseActivityEvaluator.cardAssessment(
                for: item,
                graph: graph,
                knownMerchants: session.homeMerchants,
                walletFeedback: walletFeedback(for: item)
            )
            switch assessment {
            case .best:
                optimal += 1
                evaluated += 1
            case .better(_, let advantageCad):
                evaluated += 1
                if let advantageCad { advantageSum += advantageCad }
            case .unavailable:
                break
            }
        }
        let pct = evaluated > 0 ? Int((Double(optimal) / Double(evaluated)) * 100) : 100
        return (optimal, evaluated, pct, advantageSum)
    }

    private var selectableCategories: [String] {
        let catalogueCategories = (environment.graph?.walletCards ?? []).flatMap { card in
            card.earnRules.flatMap { $0.predicate.categories ?? [] }
        }
        return Array(Set(catalogueCategories + ["other"]))
            .sorted { CategoryVisuals.meta(for: $0).displayName < CategoryVisuals.meta(for: $1).displayName }
    }

    /// Ask once after the first repeat (two separate visit days), while the exact branch is still
    /// known. Three days remains the threshold only for owners who choose automatic learning.
    private var arrivalPromptContext: ArrivalPromptContext? {
        let patronage = MerchantPatronageStore()
        let preferences = ArrivalAlertPreferenceStore()
        for purchase in session.recentPurchaseItems {
            guard let merchantKey = purchase.merchantKey
                    ?? merchantActivityKey(name: purchase.displayMerchant,
                                           locationIdentifier: purchase.merchantIdentifier,
                                           latitude: purchase.merchantLatitude,
                                           longitude: purchase.merchantLongitude),
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
                // 1. Activity Pulse Hero Card
                activityPulseHeroCard

                // 2. Smart Action Queues Banner (Finish & Reconcile)
                actionQueuesBanner

                // 3. Category Filter Capsules
                if !availableCategories.isEmpty {
                    categoryFilterBar
                }

                // 4. Category Insight & Spend Cap Card (when a category is selected)
                if let selectedCategory, !filteredCheckoutPurchases.isEmpty {
                    categoryInsightCard(category: selectedCategory,
                                        purchases: filteredCheckoutPurchases)
                }

                // 5. Purchases Feed Header & Date Grouped List
                purchasesFeedSection

                // 6. Arrival Alert Prompt
                if let prompt = arrivalPromptContext {
                    arrivalAlertPrompt(for: prompt)
                }

                // 7. Experiment Validation & Scoreboard
                experimentScoreboardSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 90) // Inset for floating glass nav
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .task {
            refreshHistoryAndCaptures()
        }
        .onAppear {
            refreshHistoryAndCaptures()
        }
        .onChange(of: sync.walletFeedback) { _, _ in
            refreshHistoryAndCaptures()
        }
        .sheet(isPresented: $isShowingAllPurchases) {
            AllPurchasesSheetView(
                purchases: session.recentPurchaseItems,
                cards: environment.graph?.walletCards ?? [],
                graph: environment.graph,
                knownMerchants: session.homeMerchants,
                initialCategory: selectedCategory,
                onSelectPurchase: { item in
                    inspectingPurchase = item
                },
                onQuickAmount: { item in
                    quickAmountPurchase = item
                }
            )
        }
        .sheet(item: $inspectingPurchase) { purchase in
            PurchaseDetailSheetView(
                purchase: purchase,
                cards: environment.graph?.walletCards ?? [],
                graph: environment.graph,
                onFinish: {
                    inspectingPurchase = nil
                    router.push(.finish)
                },
                onReconcile: {
                    inspectingPurchase = nil
                    router.push(.reconcile)
                },
                onUpdateCategory: updateCategory,
                onUpdateAmount: updateAmount,
                onUpdateCard: updateCard,
                onDeletePurchase: deletePurchase
            )
        }
        .sheet(item: $quickAmountPurchase) { purchase in
            PurchaseAmountEntrySheetView(
                merchantName: purchase.displayMerchant,
                initialAmountCad: purchase.amountCad,
                onSave: { amount in
                    updateAmount(purchase, amount)
                    quickAmountPurchase = nil
                },
                onCancel: { quickAmountPurchase = nil }
            )
        }
        .sheet(item: $quickCategoryPurchase) { purchase in
            CategoryChangeSheetView(
                currentCategory: category(for: purchase) ?? "other",
                categories: selectableCategories,
                onSelectCategory: { newCategory in
                    updateCategory(purchase, newCategory)
                    quickCategoryPurchase = nil
                }
            )
        }
        .sheet(item: $quickCardPurchase) { purchase in
            CardChangeSheetView(
                currentCardId: purchase.cardUsedId,
                recommendedCardId: purchase.bestCardId ?? purchase.prediction?.winnerCardId,
                cards: environment.graph?.walletCards ?? [],
                onSelectCard: { newCardId in
                    updateCard(purchase, newCardId)
                    quickCardPurchase = nil
                }
            )
        }
        .confirmationDialog(
            "Delete this purchase?",
            isPresented: Binding(get: { quickDeletePurchase != nil }, set: { if !$0 { quickDeletePurchase = nil } }),
            titleVisibility: .visible
        ) {
            if let target = quickDeletePurchase {
                Button("Delete Purchase", role: .destructive) {
                    deletePurchase(target)
                    quickDeletePurchase = nil
                }
            }
            Button("Cancel", role: .cancel) { quickDeletePurchase = nil }
        } message: {
            Text("This removes the record from your purchase history.")
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

    private func refreshHistoryAndCaptures() {
        guard let graph = environment.graph else { return }
        do {
            _ = try graph.service.ingestAutomaticCaptures(from: sync.walletFeedback)
        } catch {
            session.report(FlowError(message:
                "Purchase feedback downloaded, but it could not be saved on this iPhone: \(error.localizedDescription)"))
        }
        session.refresh(using: graph)
    }

    // MARK: - 1. Activity Pulse Hero Card

    private var activityPulseHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.blue)
                    Text("ACTIVITY PULSE")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.9)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let selectedCategory {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            self.selectedCategory = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Filtered: \(CategoryVisuals.meta(for: selectedCategory).displayName)")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else if !session.recentPurchaseItems.isEmpty {
                    Text("\(session.recentPurchaseItems.count) purchases")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }

            // Main Spend Metric
            VStack(alignment: .leading, spacing: 3) {
                Text(String(format: "$%.2f", totalSpendAmount))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText())

                Text(selectedCategory != nil
                     ? "\(CategoryVisuals.meta(for: selectedCategory!).displayName) tracked spend"
                     : "Total tracked spending in PickMe")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Sub-metrics (Optimization Score & Value Impact)
            HStack(spacing: 12) {
                // Optimization Rate Pill
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .stroke(Color.green.opacity(0.2), lineWidth: 3)
                            .frame(width: 24, height: 24)
                        Circle()
                            .trim(from: 0, to: CGFloat(Double(optimalStats.percent) / 100.0))
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 24, height: 24)
                            .rotationEffect(.degrees(-90))
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(optimalStats.percent)% Optimal")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("\(optimalStats.optimalCount)/\(max(optimalStats.evaluatedCount, 1)) best card used")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                // Rewards Opportunity / Advantage
                HStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(optimalStats.totalAdvantageCad > 0 ? Color.orange.opacity(0.15) : Color.blue.opacity(0.12))
                            .frame(width: 24, height: 24)
                        Image(systemName: optimalStats.totalAdvantageCad > 0 ? "arrow.up.right" : "sparkle")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(optimalStats.totalAdvantageCad > 0 ? .orange : .blue)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        if optimalStats.totalAdvantageCad > 0 {
                            Text(String(format: "+$%.2f", optimalStats.totalAdvantageCad))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.orange)
                            Text("Better card potential")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("\(availableCategories.count) Categories")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("Active merchant diversity")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }

    // MARK: - 2. Smart Action Queues Banner

    @ViewBuilder
    private var actionQueuesBanner: some View {
        let finishCount = session.completionQueue.count
        let reconcileCount = session.reconcileQueue.count
        let totalActions = finishCount + reconcileCount

        if totalActions > 0 {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 5) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.blue)
                        Text("ACTION REQUIRED")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("\(totalActions) pending")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.blue, in: Capsule())
                }

                HStack(spacing: 10) {
                    if finishCount > 0 {
                        Button {
                            router.push(.finish)
                        } label: {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.blue.opacity(0.16))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.blue)
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(finishCount) to Finish")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Text("Add card or amount")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    if reconcileCount > 0 {
                        Button {
                            router.push(.reconcile)
                        } label: {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color(red: 0.13, green: 0.77, blue: 0.37).opacity(0.16))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "tray.full.fill")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))
                                }

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(reconcileCount) to Reconcile")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(.primary)
                                    Text("Confirm statement")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(10)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.blue.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.blue.opacity(0.18), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - 3. Category Filter Capsules

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // "All" Pill
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedCategory = nil
                        filterNeedsAttention = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("All")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Text("\(session.recentPurchaseItems.count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(selectedCategory == nil && !filterNeedsAttention ? Color.white.opacity(0.25) : Color(.tertiarySystemFill), in: Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        selectedCategory == nil && !filterNeedsAttention
                            ? Color.blue
                            : Color(.secondarySystemGroupedBackground),
                        in: Capsule()
                    )
                    .foregroundStyle(selectedCategory == nil && !filterNeedsAttention ? .white : .primary)
                    .overlay(
                        Capsule()
                            .strokeBorder(selectedCategory == nil && !filterNeedsAttention ? Color.clear : Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                // "Needs Attention" Pill (if any issues exist)
                if !needsAttentionPurchases.isEmpty {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            filterNeedsAttention.toggle()
                            if filterNeedsAttention {
                                selectedCategory = nil
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(filterNeedsAttention ? .white : .orange)
                            Text("Needs Attention")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text("\(needsAttentionPurchases.count)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(filterNeedsAttention ? Color.white.opacity(0.25) : Color.orange.opacity(0.18), in: Capsule())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            filterNeedsAttention
                                ? Color.orange
                                : Color(.secondarySystemGroupedBackground),
                            in: Capsule()
                        )
                        .foregroundStyle(filterNeedsAttention ? .white : .primary)
                        .overlay(
                            Capsule()
                                .strokeBorder(filterNeedsAttention ? Color.clear : Color.orange.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Individual Category Pills
                ForEach(availableCategories, id: \.self) { category in
                    let meta = CategoryVisuals.meta(for: category)
                    let count = session.recentPurchaseItems.filter { self.category(for: $0) == category }.count
                    let isSelected = selectedCategory == category && !filterNeedsAttention

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            filterNeedsAttention = false
                            selectedCategory = isSelected ? nil : category
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: meta.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : meta.color)
                            Text(meta.displayName)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                            Text("\(count)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(isSelected ? Color.white.opacity(0.25) : Color(.tertiarySystemFill), in: Capsule())
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
                                .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 4. Category Insight & Spend Cap Card

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
                        .frame(width: 38, height: 38)
                    Image(systemName: meta.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(meta.color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(meta.displayName.uppercased()) INTELLIGENCE")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(meta.color)
                    Text(String(format: "$%.2f CAD Total Spend", totalSpend))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                VStack(alignment: .leading, spacing: 3) {
                    Text("OPTIMAL CARD ACCURACY")
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

                VStack(alignment: .trailing, spacing: 3) {
                    Text("PURCHASES")
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
                for rule in card.earnRules where rule.effectiveCapIds.contains(cap.capId) {
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

    // MARK: - 5. Purchases Feed Header & List

    private var purchasesFeedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header Row
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedCategory == nil ? "Recent Purchases" : "\(CategoryVisuals.meta(for: selectedCategory!).displayName) Purchases")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    if !filteredItems.isEmpty {
                        Text("\(filteredItems.count) total · Chronological feed")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                if filteredItems.count > 5 {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        isShowingAllPurchases = true
                    } label: {
                        HStack(spacing: 3) {
                            Text("See All (\(filteredItems.count))")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.blue.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            if filteredItems.isEmpty {
                emptyPurchasesCard
            } else {
                // Grouped Date Sections
                VStack(spacing: 14) {
                    ForEach(purchaseSections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            // Section Date Header
                            HStack {
                                Text(section.title)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)

                                Spacer()

                                let subtotal = section.items.reduce(0.0) { sum, item in
                                    sum + (item.amountCad ?? item.prediction?.scoredAmountCad ?? 0)
                                }
                                if subtotal > 0 {
                                    Text(String(format: "$%.2f", subtotal))
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 4)

                            // Purchases inside this date section
                            VStack(spacing: 8) {
                                ForEach(section.items) { item in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        inspectingPurchase = item
                                    } label: {
                                        purchaseRow(item)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            inspectingPurchase = item
                                        } label: {
                                            Label("View Details", systemImage: "info.circle")
                                        }

                                        Button {
                                            quickAmountPurchase = item
                                        } label: {
                                            Label(item.amountCad == nil ? "Add Amount" : "Edit Amount", systemImage: "dollarsign.circle")
                                        }

                                        Button {
                                            quickCardPurchase = item
                                        } label: {
                                            Label("Change Card Tapped", systemImage: "creditcard")
                                        }

                                        Button {
                                            quickCategoryPurchase = item
                                        } label: {
                                            Label("Reclassify Category", systemImage: "tag")
                                        }

                                        Divider()

                                        Button(role: .destructive) {
                                            quickDeletePurchase = item
                                        } label: {
                                            Label("Delete Purchase", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if filteredItems.count > 5 {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            isShowingAllPurchases = true
                        } label: {
                            HStack(spacing: 6) {
                                Text("View All \(filteredItems.count) Purchases")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                }
            }
        }
    }

    private var emptyPurchasesCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.10))
                    .frame(width: 58, height: 58)
                Image(systemName: "bag.badge.plus")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.blue)
            }
            .padding(.top, 6)

            VStack(spacing: 5) {
                Text(selectedCategory != nil ? "No \(selectedCategory!) Purchases" : "No Purchases Logged Yet")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(selectedCategory != nil
                     ? "Try selecting another category or clear the filter to view all purchases."
                     : "Pick a card in PickMe or capture a card tap, and every logged purchase will appear here.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            if selectedCategory != nil {
                Button {
                    withAnimation { selectedCategory = nil }
                } label: {
                    Text("Clear Filter")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.blue.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 1)
        )
    }

    // MARK: - Purchase Row Component

    private func purchaseRow(_ item: StoredPurchase) -> some View {
        let category = category(for: item)
        let meta = CategoryVisuals.meta(for: category ?? "other")
        let tint = category == nil ? Color.secondary : meta.color
        let icon = category == nil ? "wave.3.right" : meta.icon
        let cardId = item.cardUsedId
        let actualAmount = item.amountCad
        let estimatedAmount = actualAmount == nil ? item.prediction?.scoredAmountCad : nil

        return VStack(alignment: .leading, spacing: 10) {
            // Main row top: Avatar + Merchant & Card + Amount
            HStack(alignment: .top, spacing: 12) {
                // Category Avatar
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(tint.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                }

                // Title + Subtitle
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayMerchant)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        // Mini Card Chip
                        if let cardId {
                            HStack(spacing: 3) {
                                Image(systemName: "creditcard.fill")
                                    .font(.system(size: 8))
                                Text(cardDisplayName(for: cardId))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.primary.opacity(0.85))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        } else {
                            Text("Card not recorded")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        if let category {
                            Text("•").font(.system(size: 9)).foregroundStyle(.tertiary)
                            Text(CategoryVisuals.meta(for: category).displayName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Text("•").font(.system(size: 9)).foregroundStyle(.tertiary)
                        Text(CategoryVisuals.relativeTime(from: item.createdAt))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Amount Display & Tag
                VStack(alignment: .trailing, spacing: 4) {
                    if let actualAmount {
                        Text(String(format: "$%.2f", actualAmount))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    } else if let estimatedAmount {
                        Text(String(format: "~$%.2f", estimatedAmount))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 5) {
                            Text("—")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Button {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                quickAmountPurchase = item
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 8, weight: .bold))
                                    Text("Amount")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                                .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
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

            // Bottom Assessment & Source Line
            cardAssessmentLine(for: item)

            if environment.ambientEnabled && isFrequented(item) {
                HStack(spacing: 5) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 11))
                    Text("Arrival alerts prioritize this store")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.blue)
                .padding(.top, 2)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 5, x: 0, y: 1)
        )
        .contextMenu {
            Button {
                quickCardPurchase = item
            } label: {
                Label("Change Card", systemImage: "creditcard")
            }
            Button {
                quickAmountPurchase = item
            } label: {
                Label(item.amountCad == nil ? "Add Amount & Currency" : "Edit Amount & Currency", systemImage: "dollarsign.circle")
            }
            Button {
                quickCategoryPurchase = item
            } label: {
                Label("Reclassify Category", systemImage: "tag")
            }
            Divider()
            Button(role: .destructive) {
                quickDeletePurchase = item
            } label: {
                Label("Delete Purchase", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func statusTag(for prediction: StoredPrediction) -> some View {
        if let observation = prediction.purchase?.observation {
            if observation.wasCorrect {
                Text("Reconciled")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12), in: Capsule())
            } else {
                Text(observation.missClass?.rawValue ?? "Mismatch")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.12), in: Capsule())
            }
        } else if prediction.purchase?.isComplete == true {
            Text("Finished")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.12), in: Capsule())
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
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                        Text("Best card used")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.green.opacity(0.12), in: Capsule())

                case .better(let cardId, let advantageCad):
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.system(size: 11))
                        Text(betterCardText(cardId: cardId, advantageCad: advantageCad))
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.orange.opacity(0.12), in: Capsule())

                case .unavailable(let reason):
                    if item.amountCad == nil {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            quickAmountPurchase = item
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 11))
                                Text("Add the amount to compare cards")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                            }
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 11))
                            Text(reason)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 3) {
                    sourceIcon(for: item.resolvedActivitySource)
                        .font(.system(size: 9))
                    Text(itemSourceLabel(item))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func sourceIcon(for source: PurchaseActivitySource) -> Image {
        switch source {
        case .pickMeCheckout: return Image(systemName: "sparkles")
        case .walletCapture: return Image(systemName: "creditcard")
        case .arrivalAlert: return Image(systemName: "location.circle")
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
                                   locationIdentifier: item.merchantIdentifier,
                                   latitude: item.merchantLatitude,
                                   longitude: item.merchantLongitude) else {
            return false
        }
        return MerchantPatronageStore().isFrequented(merchantKey: key)
    }

    // MARK: - 6. Arrival Alert Prompt

    private func arrivalAlertPrompt(for prompt: ArrivalPromptContext) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "location.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Frequent Store: \(prompt.merchantName)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(prompt.supportsChain
                     ? "Enable automatic arrival card alerts for all branches or this branch only."
                     : "Enable automatic arrival card alerts for this location.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("Configure") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                isChoosingArrivalScope = true
            }
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.blue.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func saveArrivalPreference(_ scope: ArrivalAlertScope,
                                       prompt: ArrivalPromptContext) {
        ArrivalAlertPreferenceStore().save(ArrivalAlertPreference(
            merchantKey: prompt.merchantKey,
            merchantName: prompt.merchantName,
            scope: scope,
            locationIdentifier: prompt.locationIdentifier,
            latitude: prompt.latitude,
            longitude: prompt.longitude))
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

    private func updateCard(_ purchase: StoredPurchase, _ cardId: String?) {
        if let graph = environment.graph {
            session.recordCard(cardId, for: purchase, using: graph)
        }
    }

    private func deletePurchase(_ purchase: StoredPurchase) {
        if let graph = environment.graph {
            session.deletePurchase(purchase, using: graph)
            sync.refreshWalletFeedbackAfterDeletion()
        }
    }

    // MARK: - 7. Experiment Validation & Scoreboard Section

    private var experimentScoreboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.blue)
                    Text("EXPERIMENT VALIDATION")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    router.push(.dashboard)
                } label: {
                    HStack(spacing: 2) {
                        Text("Full Breakdown")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(.blue)
                }
            }

            if let metrics = session.metrics {
                experimentOverviewCard(metrics: metrics)
            }
        }
    }

    private func experimentOverviewCard(metrics: ExperimentMetrics) -> some View {
        VStack(spacing: 14) {
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
            VStack(alignment: .leading, spacing: 3) {
                Text("CHECKOUT TARGET")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(metrics.progressToTarget)")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("/ \(metrics.targetCheckouts) checkouts")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 4.5)
                    .frame(width: 44, height: 44)
                Circle()
                    .trim(from: 0, to: CGFloat(min(progress / target, 1.0)))
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .frame(width: 44, height: 44)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if isMet {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            if let rate {
                Text("\(Int(round(rate * 100)))%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isMet ? .green : .primary)
            } else {
                Text("—")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text("Target: \(target)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - All Purchases Archive Sheet

/// Sheet presenting the complete list of all recent purchases with Category Filtering and Search.
struct AllPurchasesSheetView: View {
    let purchases: [StoredPurchase]
    let cards: [CardProduct]
    let graph: DependencyGraph?
    let knownMerchants: [StoredMerchant]
    var initialCategory: String? = nil
    let onSelectPurchase: (StoredPurchase) -> Void
    var onQuickAmount: ((StoredPurchase) -> Void)? = nil

    @State private var selectedCategory: String?
    @State private var filterNeedsAttention: Bool = false
    @State private var searchQuery: String = ""
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncCoordinator.self) private var sync

    init(
        purchases: [StoredPurchase],
        cards: [CardProduct],
        graph: DependencyGraph?,
        knownMerchants: [StoredMerchant],
        initialCategory: String? = nil,
        onSelectPurchase: @escaping (StoredPurchase) -> Void,
        onQuickAmount: ((StoredPurchase) -> Void)? = nil
    ) {
        self.purchases = purchases
        self.cards = cards
        self.graph = graph
        self.knownMerchants = knownMerchants
        self.initialCategory = initialCategory
        self._selectedCategory = State(initialValue: initialCategory)
        self.onSelectPurchase = onSelectPurchase
        self.onQuickAmount = onQuickAmount
    }

    private var availableCategories: [String] {
        let cats = purchases.compactMap(category)
        var unique: [String] = []
        for cat in cats where !unique.contains(cat) {
            unique.append(cat)
        }
        return unique
    }

    private var needsAttentionPurchases: [StoredPurchase] {
        purchases.filter { item in
            PurchaseAttentionEvaluator.needsAttention(
                item,
                graph: graph,
                knownMerchants: knownMerchants,
                walletFeedback: walletFeedback(for: item)
            )
        }
    }

    private var filteredPurchases: [StoredPurchase] {
        purchases.filter { item in
            let itemCategory = category(for: item)
            let matchesCategory: Bool = {
                if filterNeedsAttention {
                    return PurchaseAttentionEvaluator.needsAttention(
                        item,
                        graph: graph,
                        knownMerchants: knownMerchants,
                        walletFeedback: walletFeedback(for: item)
                    )
                }
                return selectedCategory == nil || itemCategory == selectedCategory
            }()
            let matchesSearch = searchQuery.isEmpty
                || item.displayMerchant.localizedCaseInsensitiveContains(searchQuery)
                || (itemCategory?.localizedCaseInsensitiveContains(searchQuery) ?? false)
                || (item.cardUsedId.map { cardDisplayName(for: $0).localizedCaseInsensitiveContains(searchQuery) } ?? false)
            return matchesCategory && matchesSearch
        }
    }

    private var totalFilteredSpend: Double {
        filteredPurchases.reduce(0.0) { sum, item in
            sum + (item.amountCad ?? item.prediction?.scoredAmountCad ?? 0)
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
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation {
                                    selectedCategory = nil
                                    filterNeedsAttention = false
                                }
                            } label: {
                                Text("All (\(purchases.count))")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(selectedCategory == nil && !filterNeedsAttention ? Color.blue : Color(.secondarySystemGroupedBackground), in: Capsule())
                                    .foregroundStyle(selectedCategory == nil && !filterNeedsAttention ? .white : .primary)
                            }
                            .buttonStyle(.plain)

                            if !needsAttentionPurchases.isEmpty {
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation {
                                        filterNeedsAttention.toggle()
                                        if filterNeedsAttention {
                                            selectedCategory = nil
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(filterNeedsAttention ? .white : .orange)
                                        Text("Needs Attention")
                                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        Text("\(needsAttentionPurchases.count)")
                                            .font(.system(size: 10, weight: .bold, design: .rounded))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(filterNeedsAttention ? Color.white.opacity(0.25) : Color.orange.opacity(0.18), in: Capsule())
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(filterNeedsAttention ? Color.orange : Color(.secondarySystemGroupedBackground), in: Capsule())
                                    .foregroundStyle(filterNeedsAttention ? .white : .primary)
                                }
                                .buttonStyle(.plain)
                            }

                            ForEach(availableCategories, id: \.self) { category in
                                let meta = CategoryVisuals.meta(for: category)
                                let isSelected = selectedCategory == category && !filterNeedsAttention
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation {
                                        filterNeedsAttention = false
                                        selectedCategory = isSelected ? nil : category
                                    }
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
                        .padding(.vertical, 8)
                    }
                    .background(Color(.systemGroupedBackground))
                }

                // Summary bar
                HStack {
                    Text("\(filteredPurchases.count) transactions")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(String(format: "$%.2f Total", totalFilteredSpend))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color(.systemGroupedBackground))

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
            .searchable(text: $searchQuery, prompt: "Search merchants, cards, or categories")
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
                        .font(.system(size: 12, weight: .medium))
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
                } else {
                    Text("—")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if let primary = PurchaseAttentionEvaluator.primaryIssue(for: item, graph: graph, knownMerchants: knownMerchants, walletFeedback: walletFeedback(for: item)), primary.isActionableNow {
                    HStack(spacing: 3) {
                        Image(systemName: primary.icon)
                            .font(.system(size: 9))
                        Text(primary.title)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(primary.tintColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(primary.tintColor.opacity(0.12), in: Capsule())
                } else if let graph {
                    assessmentLabel(PurchaseActivityEvaluator.cardAssessment(
                        for: item, graph: graph, knownMerchants: knownMerchants,
                        walletFeedback: walletFeedback(for: item)))
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button {
                dismiss()
                onSelectPurchase(item)
            } label: {
                Label("Purchase Details", systemImage: "info.circle")
            }
            if let onQuickAmount {
                Button {
                    dismiss()
                    onQuickAmount(item)
                } label: {
                    Label(item.amountCad == nil ? "Add Amount & Currency" : "Edit Amount & Currency", systemImage: "dollarsign.circle")
                }
            }
        }
    }

    @ViewBuilder
    private func assessmentLabel(_ assessment: PurchaseCardAssessment) -> some View {
        switch assessment {
        case .best:
            Label("Best card", systemImage: "checkmark.circle.fill")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.green)
        case .better(let cardId, _):
            Text("Better: \(cardDisplayName(for: cardId))")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.orange)
        case .unavailable:
            Text("Not compared")
                .font(.system(size: 10, weight: .medium, design: .rounded))
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
