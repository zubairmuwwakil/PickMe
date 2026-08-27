import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// The Activity hub: Pending queues (Finish Purchases, Reconcile Statements), Recent Purchases with Category Intelligence & Experiment Scoreboard.
struct ActivityHubView: View {
    @Environment(CopilotSession.self) private var session
    @Environment(CheckoutRouter.self) private var router
    @Environment(CopilotEnvironment.self) private var environment

    @State private var selectedCategory: String? = nil
    @State private var isShowingAllPurchases = false
    @State private var inspectingPurchase: StoredPrediction? = nil

    private var availableCategories: [String] {
        let cats = session.recentPurchases.map {
            $0.purchase?.observation?.observedCategory ?? $0.predictedCategory
        }.filter { !$0.isEmpty }
        var unique: [String] = []
        for cat in cats where !unique.contains(cat) {
            unique.append(cat)
        }
        return unique
    }

    private var filteredPurchases: [StoredPrediction] {
        if let selectedCategory {
            return session.recentPurchases.filter {
                ($0.purchase?.observation?.observedCategory ?? $0.predictedCategory) == selectedCategory
            }
        }
        return session.recentPurchases
    }

    private var displayedPurchases: [StoredPrediction] {
        if selectedCategory != nil {
            return filteredPurchases
        }
        return Array(session.recentPurchases.prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Section: Action Queues
                VStack(alignment: .leading, spacing: 12) {
                    Text("Action Queues")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    VStack(spacing: 10) {
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

                // Section: Recent Purchases & Category Intelligence
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recent Purchases")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)
                            if !session.recentPurchases.isEmpty {
                                Text("\(session.recentPurchases.count) total • \(availableCategories.count) categories")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if session.recentPurchases.count > 5 {
                            Button {
                                isShowingAllPurchases = true
                            } label: {
                                Text("See All (\(session.recentPurchases.count))")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    if session.recentPurchases.isEmpty {
                        emptyPurchasesCard
                    } else {
                        // Horizontal Category Filter Pills
                        categoryFilterBar

                        // Category Insight & Cap Card (when filtering or aggregate)
                        if let selectedCategory {
                            categoryInsightCard(category: selectedCategory, purchases: filteredPurchases)
                        }

                        // Purchase rows
                        VStack(spacing: 10) {
                            ForEach(displayedPurchases) { prediction in
                                Button {
                                    inspectingPurchase = prediction
                                    openPurchase(prediction)
                                } label: {
                                    purchaseRow(prediction: prediction)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // Section: Experiment Validation & Scoreboard
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Experiment Scoreboard")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
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
            .padding(.top, 12)
            .padding(.bottom, 90) // Inset for floating glass nav
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $isShowingAllPurchases) {
            AllPurchasesSheetView(
                purchases: session.recentPurchases,
                cards: environment.graph?.walletCards ?? [],
                onSelectPurchase: { prediction in
                    inspectingPurchase = prediction
                    openPurchase(prediction)
                },
                onUpdateCategory: updateCategory
            )
        }
        .sheet(item: $inspectingPurchase) { prediction in
            PurchaseDetailSheetView(
                prediction: prediction,
                cards: environment.graph?.walletCards ?? [],
                onFinish: {
                    inspectingPurchase = nil
                    router.push(.finish)
                },
                onReconcile: {
                    inspectingPurchase = nil
                    router.push(.reconcile)
                },
                onUpdateCategory: { updatedPrediction, newCategory in
                    updateCategory(updatedPrediction, newCategory)
                }
            )
        }
    }

    private func openPurchase(_ prediction: StoredPrediction) {
        if prediction.purchase?.isComplete == false {
            router.push(.finish)
        }
    }

    private func updateCategory(_ prediction: StoredPrediction, _ category: String) {
        if let graph = environment.graph {
            session.updateCategory(for: prediction, to: category, using: graph)
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
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("All")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("(\(session.recentPurchases.count))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(selectedCategory == nil ? .white.opacity(0.8) : .secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
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
                    let count = session.recentPurchases.filter {
                        ($0.purchase?.observation?.observedCategory ?? $0.predictedCategory) == category
                    }.count
                    let isSelected = selectedCategory == category

                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            selectedCategory = isSelected ? nil : category
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: meta.icon)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isSelected ? .white : meta.color)
                            Text(meta.displayName)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                            Text("(\(count))")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
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
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(iconColor.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(badgeColor, in: Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
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

                Text("Pick a card or log spend at checkout, and your past transactions with category breakdown will appear here.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
    }

    private func purchaseRow(prediction: StoredPrediction) -> some View {
        let category = prediction.purchase?.observation?.observedCategory ?? prediction.predictedCategory
        let meta = CategoryVisuals.meta(for: category)
        let cardId = prediction.purchase?.cardUsedId ?? prediction.winnerCardId
        let cardName = cardDisplayName(for: cardId)
        let date = prediction.purchase?.createdAt ?? prediction.recordedAt
        let timeLabel = CategoryVisuals.relativeTime(from: date)

        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(meta.color.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: meta.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(meta.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(prediction.merchantName.isEmpty ? "Purchase" : prediction.merchantName)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(cardName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(meta.displayName)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(timeLabel)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let amount = prediction.purchase?.amountCad {
                    Text(String(format: "$%.2f", amount))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                } else if let scored = prediction.scoredAmountCad {
                    Text(String(format: "~$%.2f", scored))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text("—")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                statusTag(for: prediction)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
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
    let purchases: [StoredPrediction]
    let cards: [CardProduct]
    let onSelectPurchase: (StoredPrediction) -> Void
    var onUpdateCategory: ((StoredPrediction, String) -> Void)? = nil

    @State private var selectedCategory: String? = nil
    @State private var searchQuery: String = ""
    @Environment(\.dismiss) private var dismiss

    private var availableCategories: [String] {
        let cats = purchases.map {
            $0.purchase?.observation?.observedCategory ?? $0.predictedCategory
        }.filter { !$0.isEmpty }
        var unique: [String] = []
        for cat in cats where !unique.contains(cat) {
            unique.append(cat)
        }
        return unique
    }

    private var filteredPurchases: [StoredPrediction] {
        purchases.filter { p in
            let category = p.purchase?.observation?.observedCategory ?? p.predictedCategory
            let matchesCategory = selectedCategory == nil || category == selectedCategory
            let matchesSearch = searchQuery.isEmpty
                || p.merchantName.localizedCaseInsensitiveContains(searchQuery)
                || category.localizedCaseInsensitiveContains(searchQuery)
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
                    ForEach(filteredPurchases) { prediction in
                        Button {
                            dismiss()
                            onSelectPurchase(prediction)
                        } label: {
                            allPurchasesRow(prediction: prediction)
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

    private func allPurchasesRow(prediction: StoredPrediction) -> some View {
        let category = prediction.purchase?.observation?.observedCategory ?? prediction.predictedCategory
        let meta = CategoryVisuals.meta(for: category)
        let cardId = prediction.purchase?.cardUsedId ?? prediction.winnerCardId
        let cardName = cardDisplayName(for: cardId)
        let date = prediction.purchase?.createdAt ?? prediction.recordedAt

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(meta.color.opacity(0.14))
                    .frame(width: 40, height: 40)
                Image(systemName: meta.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(meta.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(prediction.merchantName.isEmpty ? "Purchase" : prediction.merchantName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                HStack(spacing: 4) {
                    Text(cardName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(meta.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                if let amount = prediction.purchase?.amountCad {
                    Text(String(format: "$%.2f", amount))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                } else if let scored = prediction.scoredAmountCad {
                    Text(String(format: "~$%.2f", scored))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if prediction.purchase?.observation != nil {
                    Text("Reconciled")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                } else if prediction.purchase?.isComplete == true {
                    Text("Finished")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                } else {
                    Text("Needs info")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
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
    let prediction: StoredPrediction
    let cards: [CardProduct]
    let onFinish: () -> Void
    let onReconcile: () -> Void
    var onUpdateCategory: ((StoredPrediction, String) -> Void)? = nil

    @State private var currentCategory: String
    @State private var isChangingCategory = false
    @Environment(\.dismiss) private var dismiss

    init(
        prediction: StoredPrediction,
        cards: [CardProduct],
        onFinish: @escaping () -> Void,
        onReconcile: @escaping () -> Void,
        onUpdateCategory: ((StoredPrediction, String) -> Void)? = nil
    ) {
        self.prediction = prediction
        self.cards = cards
        self.onFinish = onFinish
        self.onReconcile = onReconcile
        self.onUpdateCategory = onUpdateCategory
        _currentCategory = State(initialValue: prediction.purchase?.observation?.observedCategory ?? prediction.predictedCategory)
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
                            Text(prediction.merchantName.isEmpty ? "Purchase" : prediction.merchantName)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary)

                            if let amount = prediction.purchase?.amountCad {
                                Text(String(format: "$%.2f CAD", amount))
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                            } else if let scored = prediction.scoredAmountCad {
                                Text(String(format: "~$%.2f CAD (Estimated)", scored))
                                    .font(.system(size: 20, weight: .semibold, design: .rounded))
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
                                value: cardDisplayName(for: prediction.purchase?.cardUsedId ?? prediction.winnerCardId),
                                icon: "creditcard.fill",
                                color: .blue
                            )
                            Divider()
                            detailRow(
                                title: "Recommended Card",
                                value: cardDisplayName(for: prediction.winnerCardId),
                                icon: "star.fill",
                                color: .yellow
                            )
                            Divider()

                            // Interactive 1-Tap Category Reclassification Row
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
                                        Text(meta.displayName)
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(.primary)
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
                                value: (prediction.purchase?.createdAt ?? prediction.recordedAt).formatted(date: .abbreviated, time: .shortened),
                                icon: "clock.fill",
                                color: .purple
                            )
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }

                    // Advice Headline
                    if !prediction.headline.isEmpty {
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
                    if prediction.purchase?.isComplete == false {
                        Button(action: onFinish) {
                            Label("Finish This Purchase", systemImage: "pencil.and.list.clipboard")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .foregroundStyle(.white)
                        }
                        .padding(.top, 8)
                    } else if prediction.purchase?.observation == nil {
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
                    onSelectCategory: { newCategory in
                        currentCategory = newCategory
                        onUpdateCategory?(prediction, newCategory)
                        isChangingCategory = false
                    }
                )
            }
        }
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

/// 1-Tap Category picker modal for fast transaction reclassification.
struct CategoryChangeSheetView: View {
    let currentCategory: String
    let onSelectCategory: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let standardCategories = [
        "grocery", "dining", "travel", "gas", "transit",
        "recurring_bills", "drugstore", "entertainment", "general"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(standardCategories, id: \.self) { category in
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
