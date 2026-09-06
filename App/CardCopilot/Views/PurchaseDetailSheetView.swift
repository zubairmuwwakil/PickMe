import SwiftUI
import MapKit
import CardCopilotEngine
import CardCopilotStore

// MARK: - Supported Transaction Currencies

public struct TransactionCurrency: Identifiable, Hashable, Sendable {
    public let code: String
    public let symbol: String
    public let flag: String
    public let name: String
    public let defaultCadRate: Double

    public var id: String { code }

    public static let all: [TransactionCurrency] = [
        TransactionCurrency(code: "CAD", symbol: "$", flag: "🇨🇦", name: "Canadian Dollar", defaultCadRate: 1.0),
        TransactionCurrency(code: "USD", symbol: "$", flag: "🇺🇸", name: "US Dollar", defaultCadRate: 1.36),
        TransactionCurrency(code: "EUR", symbol: "€", flag: "🇪🇺", name: "Euro", defaultCadRate: 1.48),
        TransactionCurrency(code: "GBP", symbol: "£", flag: "🇬🇧", name: "British Pound", defaultCadRate: 1.75),
        TransactionCurrency(code: "JPY", symbol: "¥", flag: "🇯🇵", name: "Japanese Yen", defaultCadRate: 0.0092),
        TransactionCurrency(code: "MXN", symbol: "$", flag: "🇲🇽", name: "Mexican Peso", defaultCadRate: 0.070),
        TransactionCurrency(code: "AUD", symbol: "$", flag: "🇦🇺", name: "Australian Dollar", defaultCadRate: 0.89)
    ]

    public static let cad = all[0]
}

/// Inspection sheet showing the comprehensive purchase breakdown, card optimization scorecard,
/// recommendation advice, location context, and 1-tap correction controls.
struct PurchaseDetailSheetView: View {
    let purchase: StoredPurchase
    let cards: [CardProduct]
    var graph: DependencyGraph? = nil
    let onFinish: () -> Void
    let onReconcile: () -> Void
    let onUpdateCategory: (StoredPurchase, String) -> Void
    let onUpdateAmount: (StoredPurchase, Double) -> Void
    var onUpdateCard: ((StoredPurchase, String?) -> Void)? = nil
    var onDeletePurchase: ((StoredPurchase) -> Void)? = nil

    @State private var currentCategory: String
    @State private var isChangingCategory = false
    @State private var isChangingCard = false
    @State private var isEnteringAmount = false
    @State private var isShowingDeleteConfirmation = false
    @State private var showCopiedToast = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(SyncCoordinator.self) private var sync

    init(
        purchase: StoredPurchase,
        cards: [CardProduct],
        graph: DependencyGraph? = nil,
        onFinish: @escaping () -> Void,
        onReconcile: @escaping () -> Void,
        onUpdateCategory: @escaping (StoredPurchase, String) -> Void,
        onUpdateAmount: @escaping (StoredPurchase, Double) -> Void,
        onUpdateCard: ((StoredPurchase, String?) -> Void)? = nil,
        onDeletePurchase: ((StoredPurchase) -> Void)? = nil
    ) {
        self.purchase = purchase
        self.cards = cards
        self.graph = graph
        self.onFinish = onFinish
        self.onReconcile = onReconcile
        self.onUpdateCategory = onUpdateCategory
        self.onUpdateAmount = onUpdateAmount
        self.onUpdateCard = onUpdateCard
        self.onDeletePurchase = onDeletePurchase
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
        let categories = Set(catalogueCategories)
            .union(CategoryTaxonomy.purchaseCategoryIDs)
            .subtracting(CategoryTaxonomy.ruleSideCategoryIDs)
        return Array(categories)
            .sorted { CategoryVisuals.meta(for: $0).displayName < CategoryVisuals.meta(for: $1).displayName }
    }

    private var cardAssessment: PurchaseCardAssessment {
        if let graph {
            return PurchaseActivityEvaluator.cardAssessment(
                for: purchase,
                graph: graph,
                knownMerchants: [],
                walletFeedback: walletFeedback(for: purchase)
            )
        }
        if let used = purchase.cardUsedId, let rec = recommendedCardId {
            if used == rec {
                return .best
            } else {
                return .better(cardId: rec, advantageCad: purchase.advantageCad)
            }
        }
        return .unavailable(reason: purchase.cardUsedId == nil ? "Card not recorded" : "Comparison pending")
    }

    private var attentionIssues: [PurchaseAttentionIssue] {
        PurchaseAttentionEvaluator.issues(
            for: purchase,
            graph: graph,
            walletFeedback: walletFeedback(for: purchase)
        )
    }

    private func walletFeedback(for item: StoredPurchase) -> WalletFeedback? {
        guard let eventId = item.walletEventId else { return nil }
        return sync.walletFeedback.first { $0.eventId == eventId }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // 0. Proactive Attention Banner (if items need resolution)
                    if !attentionIssues.filter(\.isActionableNow).isEmpty {
                        attentionResolutionCard
                    }

                    // 1. Hero Header & Amount Summary
                    heroHeaderCard

                    // 2. Card Optimization Scorecard (Core Value Proposition)
                    optimizationScorecard

                    // 3. Recommendation Intelligence & Advice
                    if let prediction, !prediction.headline.isEmpty {
                        recommendationAdviceCard(prediction: prediction)
                    }

                    // 4. Grouped Transaction Details
                    transactionDetailsSection

                    // 5. Merchant & Location Context
                    locationSection

                    // 6. Primary Action Buttons
                    primaryActionSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Purchase Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                }

                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ShareLink(item: shareSummaryText) {
                            Label("Share Transaction", systemImage: "square.and.arrow.up")
                        }

                        if onUpdateCard != nil {
                            Button {
                                isChangingCard = true
                            } label: {
                                Label("Change Card Tapped", systemImage: "creditcard")
                            }
                        }

                        Button {
                            isChangingCategory = true
                        } label: {
                            Label("Reclassify Category", systemImage: "tag")
                        }

                        Button {
                            isEnteringAmount = true
                        } label: {
                            Label(purchase.amountCad == nil ? "Add Amount & Currency" : "Edit Amount & Currency", systemImage: "dollarsign.circle")
                        }

                        if onDeletePurchase != nil {
                            Divider()
                            Button(role: .destructive) {
                                isShowingDeleteConfirmation = true
                            } label: {
                                Label("Delete Purchase", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(.primary)
                    }
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
            .sheet(isPresented: $isChangingCard) {
                if let onUpdateCard {
                    CardChangeSheetView(
                        currentCardId: purchase.cardUsedId,
                        recommendedCardId: recommendedCardId,
                        cards: cards,
                        onSelectCard: { newCardId in
                            onUpdateCard(purchase, newCardId)
                            isChangingCard = false
                        }
                    )
                }
            }
            .sheet(isPresented: $isEnteringAmount) {
                PurchaseAmountEntrySheetView(
                    merchantName: purchase.displayMerchant,
                    initialAmountCad: purchase.amountCad,
                    onSave: { amount in
                        onUpdateAmount(purchase, amount)
                        isEnteringAmount = false
                    },
                    onCancel: { isEnteringAmount = false }
                )
            }
            .confirmationDialog(
                "Delete this purchase?",
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Purchase", role: .destructive) {
                    onDeletePurchase?(purchase)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the record from your purchase history. Reconcile calculations will update accordingly.")
            }
        }
    }

    // MARK: - 0. Proactive Attention Banner

    private var attentionResolutionCard: some View {
        let actionable = attentionIssues.filter(\.isActionableNow)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.orange)
                Text("NEEDS ATTENTION")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.orange)

                Spacer()

                Text("\(actionable.count) action\(actionable.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(Color.orange.opacity(0.14), in: Capsule())
            }

            ForEach(actionable) { issue in
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(issue.tintColor.opacity(0.15))
                            .frame(width: 32, height: 32)
                        Image(systemName: issue.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(issue.tintColor)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(issue.title)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text(issue.subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        switch issue {
                        case .missingAmount:
                            isEnteringAmount = true
                        case .missingCard:
                            isChangingCard = true
                        case .uncertainCategory:
                            isChangingCategory = true
                        default:
                            break
                        }
                    } label: {
                        Text("Fix")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(issue.tintColor, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1.5)
                )
        )
    }

    // MARK: - 1. Hero Header Card

    private var heroHeaderCard: some View {
        let meta = CategoryVisuals.meta(for: currentCategory)
        return VStack(spacing: 16) {
            ZStack {
                // Ambient Glow
                Circle()
                    .fill(meta.color.opacity(0.18))
                    .frame(width: 80, height: 80)
                    .blur(radius: 12)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [meta.color.opacity(0.22), meta.color.opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .strokeBorder(meta.color.opacity(0.35), lineWidth: 1.5)
                    )

                Image(systemName: meta.icon)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(meta.color)
            }

            VStack(spacing: 6) {
                Text(purchase.displayMerchant)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                // Interactive Amount & Currency Display
                Button {
                    isEnteringAmount = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        if let amount = purchase.amountCad {
                            Text(String(format: "$%.2f CAD", amount))
                                .font(.system(size: 30, weight: .black, design: .rounded))
                                .foregroundStyle(.primary)
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                        } else if let scored = prediction?.scoredAmountCad {
                            VStack(spacing: 2) {
                                Text(String(format: "~$%.2f CAD", scored))
                                    .font(.system(size: 26, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text("Estimated · Tap to enter exact amount & currency")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.blue)
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Add Amount & Currency")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Category Pill (Tap to change)
                Button {
                    isChangingCategory = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: meta.icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(meta.color)
                        Text(meta.displayName)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.tertiarySystemGroupedBackground), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(meta.color.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 3)
        )
    }

    // MARK: - 2. Card Optimization Scorecard

    private var optimizationScorecard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("CARD OPTIMIZATION")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)

                Spacer()

                scorecardVerdictBadge
            }
            .padding(.horizontal, 4)

            VStack(spacing: 12) {
                switch cardAssessment {
                case .best:
                    optimalCardBody
                case .better(let betterCardId, let advantageCad):
                    opportunityMissedBody(betterCardId: betterCardId, advantageCad: advantageCad)
                case .unavailable(let reason):
                    unavailableCardBody(reason: reason)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(scorecardBorderColor, lineWidth: 1.5)
                    )
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            )
        }
    }

    @ViewBuilder
    private var scorecardVerdictBadge: some View {
        switch cardAssessment {
        case .best:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                Text("OPTIMAL CARD")
                    .font(.system(size: 11, weight: .black, design: .rounded))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.14), in: Capsule())
            .foregroundStyle(.green)

        case .better(_, let advantage):
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
                Text(advantage.map { String(format: "+$%.2f MISSED", $0) } ?? "BETTER CARD AVAILABLE")
                    .font(.system(size: 11, weight: .black, design: .rounded))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.14), in: Capsule())
            .foregroundStyle(.orange)

        case .unavailable:
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11))
                Text("UNRECORDED")
                    .font(.system(size: 11, weight: .black, design: .rounded))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(.secondary)
        }
    }

    private var scorecardBorderColor: Color {
        switch cardAssessment {
        case .best: return Color.green.opacity(0.25)
        case .better: return Color.orange.opacity(0.3)
        case .unavailable: return Color.clear
        }
    }

    private var optimalCardBody: some View {
        let usedCardId = purchase.cardUsedId ?? recommendedCardId ?? ""
        let style = CardVisualTheme.style(for: usedCardId)

        return VStack(spacing: 14) {
            HStack(spacing: 14) {
                cardArtThumbnail(cardId: usedCardId)

                VStack(alignment: .leading, spacing: 3) {
                    Text(cardDisplayName(for: usedCardId))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("\(style.issuer) · \(style.network.rawValue)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                        Text("Maximized rewards on this purchase")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.green)
                    }
                    .padding(.top, 2)
                }

                Spacer()
            }

            if onUpdateCard != nil {
                Divider()
                Button {
                    isChangingCard = true
                } label: {
                    HStack {
                        Text("Tapped a different card?")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("Change")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func opportunityMissedBody(betterCardId: String, advantageCad: Double?) -> some View {
        let tappedCardId = purchase.cardUsedId ?? ""
        let tappedStyle = CardVisualTheme.style(for: tappedCardId)
        let betterStyle = CardVisualTheme.style(for: betterCardId)

        return VStack(spacing: 12) {
            // Card Tapped Row
            HStack(spacing: 12) {
                cardArtThumbnail(cardId: tappedCardId)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Tapped")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.12), in: Capsule())

                        Text(cardDisplayName(for: tappedCardId))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Text("\(tappedStyle.issuer)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if onUpdateCard != nil {
                    Button {
                        isChangingCard = true
                    } label: {
                        Text("Edit")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Delta separator
            HStack(spacing: 8) {
                VStack { Divider() }
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 10, weight: .bold))
                    Text(advantageCad.map { String(format: "+$%.2f Potential Value", $0) } ?? "Higher Return Card")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.10), in: Capsule())
                VStack { Divider() }
            }

            // Recommended Card Row
            HStack(spacing: 12) {
                cardArtThumbnail(cardId: betterCardId)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Recommended")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.14), in: Capsule())

                        Text(cardDisplayName(for: betterCardId))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }

                    Text("\(betterStyle.issuer) · Top earn rate for \(CategoryVisuals.meta(for: currentCategory).displayName)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
    }

    private func unavailableCardBody(reason: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.blue.opacity(0.12))
                        .frame(width: 44, height: 32)
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(purchase.cardUsedId.map { cardDisplayName(for: $0) } ?? "No Card Recorded")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if onUpdateCard != nil {
                    Button {
                        isChangingCard = true
                    } label: {
                        Text(purchase.cardUsedId == nil ? "Select Card" : "Change")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func cardArtThumbnail(cardId: String) -> some View {
        let style = CardVisualTheme.style(for: cardId)
        return ZStack {
            LinearGradient(
                colors: style.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "creditcard.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(style.textColor.opacity(0.85))
        }
        .frame(width: 52, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: style.gradientColors.first?.opacity(0.3) ?? Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }

    // MARK: - 3. Recommendation Advice Card

    private func recommendationAdviceCard(prediction: StoredPrediction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SMART ADVICE")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.yellow.opacity(0.16))
                        .frame(width: 38, height: 38)
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.yellow)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(prediction.headline)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let points = prediction.predictedRewardUnits,
                       let kind = prediction.predictedRewardUnitKind {
                        Text(String(format: "Expected return: %.1f %@", points, kind))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            )
        }
    }

    // MARK: - 4. Grouped Transaction Details

    private var transactionDetailsSection: some View {
        let meta = CategoryVisuals.meta(for: currentCategory)

        return VStack(alignment: .leading, spacing: 8) {
            Text("TRANSACTION DETAILS")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                // Category Row
                Button {
                    isChangingCategory = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 12) {
                        rowIcon("tag.fill", color: meta.color)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Category")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.secondary)
                            if let conf = purchase.categoryConfidence {
                                Text(confidenceLabel(conf))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(conf == .fallback ? Color.orange : Color.secondary)
                            }
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            Text(meta.displayName)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)

                Divider().padding(.leading, 52)

                // Date & Time Row
                HStack(spacing: 12) {
                    rowIcon("clock.fill", color: .purple)

                    Text("Date & Time")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(purchase.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                Divider().padding(.leading, 52)

                // Captured Via Row
                HStack(spacing: 12) {
                    rowIcon(activitySourceIcon, color: .teal)

                    Text("Captured Via")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack(spacing: 5) {
                        Text(activitySourceLabel)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)

                Divider().padding(.leading, 52)

                // Status Row
                HStack(spacing: 12) {
                    rowIcon(statusIcon, color: statusColor)

                    Text("Status")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text(statusLabel)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(statusColor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            )
        }
    }

    // MARK: - 5. Location Section

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LOCATION & MERCHANT")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                if let lat = purchase.merchantLatitude, let lon = purchase.merchantLongitude, lat != 0 || lon != 0 {
                    let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                    ))) {
                        Marker(purchase.displayMerchant, coordinate: coordinate)
                            .tint(.blue)
                    }
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(purchase.displayMerchant)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(String(format: "%.4f, %.4f", lat, lon))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if let locationURL {
                            Button {
                                openURL(locationURL)
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Open in Maps")
                                    Image(systemName: "arrow.up.right.square")
                                }
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        rowIcon("location.slash.fill", color: .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Location Not Captured")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("Captured automatically during arrival geofence alerts or live checkouts.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
            )
        }
    }

    // MARK: - 6. Primary Action Buttons

    @ViewBuilder
    private var primaryActionSection: some View {
        if prediction != nil, purchase.missingFacts.contains(.card) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onFinish()
            } label: {
                Label("Finish This Purchase", systemImage: "pencil.and.list.clipboard")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                    .shadow(color: Color.blue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        } else if prediction != nil, purchase.isComplete, purchase.observation == nil {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onReconcile()
            } label: {
                Label("Reconcile in Statement Queue", systemImage: "tray.full.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                    .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 4)
            }
        }
    }

    // MARK: - Helper Views & Properties

    private func rowIcon(_ name: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.14))
                .frame(width: 30, height: 30)
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
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
        case .pickMeCheckout: return "PickMe Checkout"
        case .walletCapture: return "Apple Wallet Tap"
        case .arrivalAlert: return "Arrival Alert"
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
        if !purchase.isComplete { return "Needs Info" }
        guard prediction != nil else { return "Captured" }
        return purchase.observation == nil ? "Finished" : "Reconciled"
    }

    private var statusIcon: String {
        if !purchase.isComplete { return "exclamationmark.circle.fill" }
        guard prediction != nil else { return "tray.and.arrow.down.fill" }
        return purchase.observation == nil ? "checkmark.circle.fill" : "checkmark.shield.fill"
    }

    private var statusColor: Color {
        if !purchase.isComplete { return .orange }
        guard prediction != nil else { return .teal }
        return purchase.observation == nil ? .blue : .green
    }

    private func confidenceLabel(_ conf: ConfidenceSource) -> String {
        switch conf {
        case .ownerConfirmedTerminal: return "Owner confirmed terminal"
        case .repeatedTerminal: return "Verified repeat merchant"
        case .issuerOverride: return "Issuer specific rule"
        case .observedMcc: return "Observed MCC from statement"
        case .brandPrior: return "Brand prior match"
        case .mapKitCategory: return "MapKit POI category"
        case .fallback: return "Estimated fallback"
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

    private var shareSummaryText: String {
        let amountText = purchase.amountCad.map { String(format: "$%.2f CAD", $0) } ?? "Amount not recorded"
        let cardText = purchase.cardUsedId.map { cardDisplayName(for: $0) } ?? "Card not recorded"
        let catText = CategoryVisuals.meta(for: currentCategory).displayName
        return "PickMe Purchase: \(purchase.displayMerchant)\nTotal: \(amountText)\nCard: \(cardText)\nCategory: \(catText)\nDate: \(purchase.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

// MARK: - Enhanced Card Switcher Sheet Modal

struct CardChangeSheetView: View {
    let currentCardId: String?
    var recommendedCardId: String? = nil
    let cards: [CardProduct]
    let onSelectCard: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // 1. Recommended Card (if known)
                if let recommendedCardId,
                   let recProduct = cards.first(where: { $0.cardId == recommendedCardId }) {
                    Section {
                        cardRow(
                            card: recProduct,
                            isRecommended: true,
                            isSelected: recProduct.cardId == currentCardId
                        )
                    } header: {
                        Label("Recommended Winner", systemImage: "sparkles")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                    } footer: {
                        Text("PickMe's highest earning card advised for this purchase.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 2. All Wallet Cards
                Section {
                    ForEach(cards, id: \.cardId) { card in
                        if card.cardId != recommendedCardId {
                            cardRow(
                                card: card,
                                isRecommended: false,
                                isSelected: card.cardId == currentCardId
                            )
                        }
                    }
                } header: {
                    Text("Your Wallet Cards")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                } footer: {
                    Text("Select which card you tapped at checkout. Rewards calculations update automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 3. Clear option
                if currentCardId != nil {
                    Section {
                        Button(role: .destructive) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onSelectCard(nil)
                        } label: {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text("Clear Recorded Card")
                            }
                            .font(.system(size: 14, weight: .medium))
                        }
                    } footer: {
                        Text("Resets this purchase to card unrecorded status.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Change Card Tapped")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func cardRow(card: CardProduct, isRecommended: Bool, isSelected: Bool) -> some View {
        let style = CardVisualTheme.style(for: card.cardId)

        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onSelectCard(card.cardId)
        } label: {
            HStack(spacing: 14) {
                // Card Artwork Thumbnail
                ZStack {
                    LinearGradient(
                        colors: style.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(style.textColor.opacity(0.9))
                }
                .frame(width: 48, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(card.officialName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)

                        if isRecommended {
                            Text("Best")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Color.green.opacity(0.14), in: Capsule())
                        }
                    }

                    Text("\(style.issuer) · \(style.network.rawValue)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Multi-Currency Amount Entry Sheet Modal

struct PurchaseAmountEntrySheetView: View {
    let merchantName: String
    var initialAmountCad: Double? = nil
    let onSave: (Double) -> Void
    let onCancel: () -> Void

    @State private var selectedCurrency: TransactionCurrency = .cad
    @State private var amountText: String = ""
    @State private var customFxRateText: String = ""
    @State private var isEnteringExactCad: Bool = false
    @State private var exactCadText: String = ""
    @FocusState private var isAmountFocused: Bool

    init(
        merchantName: String,
        initialAmountCad: Double? = nil,
        onSave: @escaping (Double) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.merchantName = merchantName
        self.initialAmountCad = initialAmountCad
        self.onSave = onSave
        self.onCancel = onCancel
        if let initialAmountCad, initialAmountCad > 0 {
            _amountText = State(initialValue: String(format: "%.2f", initialAmountCad))
        }
    }

    private var presets: [Double] {
        if selectedCurrency.code == "JPY" {
            return [1000, 2500, 5000, 10000, 20000]
        }
        return [10, 25, 50, 100, 200]
    }

    private var parsedEnteredAmount: Double? {
        let cleaned = amountText
            .replacingOccurrences(of: ",", with: ".")
            .filter { $0.isNumber || $0 == "." }
        guard let value = Double(cleaned), value > 0 else { return nil }
        return value
    }

    private var parsedFxRate: Double {
        if let custom = Double(customFxRateText.trimmingCharacters(in: .whitespaces)), custom > 0 {
            return custom
        }
        return selectedCurrency.defaultCadRate
    }

    private var effectiveCadAmount: Double? {
        if isEnteringExactCad {
            let cleaned = exactCadText
                .replacingOccurrences(of: ",", with: ".")
                .filter { $0.isNumber || $0 == "." }
            guard let val = Double(cleaned), val > 0 else { return nil }
            return val
        }
        guard let entered = parsedEnteredAmount else { return nil }
        if selectedCurrency.code == "CAD" {
            return entered
        }
        return (entered * parsedFxRate * 100).rounded() / 100.0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Currency Selector Carousel
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TRANSACTION CURRENCY")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(TransactionCurrency.all) { currency in
                                    let isSelected = currency.code == selectedCurrency.code
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            selectedCurrency = currency
                                            customFxRateText = String(format: "%.4f", currency.defaultCadRate)
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            Text(currency.flag)
                                                .font(.system(size: 15))
                                            Text(currency.code)
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                            Text(currency.symbol)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            isSelected ? Color.blue : Color(.secondarySystemGroupedBackground),
                                            in: Capsule()
                                        )
                                        .foregroundStyle(isSelected ? .white : .primary)
                                        .overlay(
                                            Capsule()
                                                .strokeBorder(isSelected ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Preset Quick Chips
                    VStack(alignment: .leading, spacing: 8) {
                        Text("QUICK PRESETS (\(selectedCurrency.code))")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            ForEach(presets, id: \.self) { amount in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    if selectedCurrency.code == "JPY" {
                                        amountText = String(format: "%.0f", amount)
                                    } else {
                                        amountText = String(format: "%.2f", amount)
                                    }
                                } label: {
                                    Text(formatPreset(amount))
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .foregroundStyle(.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // Custom Amount Input Card
                    VStack(spacing: 10) {
                        HStack {
                            Text("CHARGE (\(selectedCurrency.code))")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(0.6)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(selectedCurrency.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 6) {
                            Text(selectedCurrency.symbol)
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)

                            TextField(selectedCurrency.code == "JPY" ? "0" : "0.00", text: $amountText)
                                .font(.system(size: 38, weight: .bold, design: .rounded))
                                .keyboardType(.decimalPad)
                                .focused($isAmountFocused)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(Color.blue.opacity(0.4), lineWidth: 1.5)
                                )
                        )

                        // Foreign Currency Conversion Box (if not CAD)
                        if selectedCurrency.code != "CAD" {
                            VStack(spacing: 8) {
                                HStack {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("ESTIMATED HOME CONVERSION")
                                            .font(.system(size: 11, weight: .bold, design: .rounded))
                                    }
                                    .foregroundStyle(.blue)

                                    Spacer()

                                    if let effective = effectiveCadAmount {
                                        Text(String(format: "$%.2f CAD", effective))
                                            .font(.system(size: 15, weight: .black, design: .rounded))
                                            .foregroundStyle(.primary)
                                    }
                                }

                                Text("1 \(selectedCurrency.code) ≈ \(String(format: "%.4f", parsedFxRate)) CAD benchmark exchange rate.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 16)

                    Text("Enter the charge amount from your receipt, terminal, or card statement.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    // Final Converted CAD Summary Banner (when amount is entered)
                    if let cad = effectiveCadAmount {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.green.opacity(0.15))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.green)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Recorded in PickMe")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(.secondary)
                                Text(String(format: "$%.2f CAD", cad))
                                    .font(.system(size: 17, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary)
                            }

                            Spacer()

                            if selectedCurrency.code != "CAD" {
                                Text(String(format: "%@ %.2f", selectedCurrency.symbol, parsedEnteredAmount ?? 0))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, 16)
                    }

                    // Save CTA Button
                    Button {
                        if let cad = effectiveCadAmount {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onSave(cad)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                            Text(effectiveCadAmount != nil ? "Save Amount (\(String(format: "$%.2f CAD", effectiveCadAmount!)))" : "Save Amount")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(effectiveCadAmount != nil ? Color.blue : Color.secondary.opacity(0.3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.white)
                    }
                    .disabled(effectiveCadAmount == nil)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Purchase Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .onAppear {
                isAmountFocused = true
            }
        }
    }

    private func formatPreset(_ amount: Double) -> String {
        if selectedCurrency.code == "JPY" {
            return String(format: "¥%.0f", amount)
        }
        return String(format: "%@%.0f", selectedCurrency.symbol, amount)
    }
}

// MARK: - Category Reclassification Sheet Modal

struct CategoryChangeSheetView: View {
    let currentCategory: String
    let categories: [String]
    let onSelectCategory: (String) -> Void
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredCategories: [String] {
        if searchText.isEmpty { return categories }
        return categories.filter {
            CategoryVisuals.meta(for: $0).displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                    ForEach(filteredCategories, id: \.self) { category in
                        let meta = CategoryVisuals.meta(for: category)
                        let isSelected = category == currentCategory

                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onSelectCategory(category)
                        } label: {
                            VStack(spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(meta.color.opacity(isSelected ? 0.25 : 0.12))
                                        .frame(width: 48, height: 48)
                                    Image(systemName: meta.icon)
                                        .font(.system(size: 22, weight: .semibold))
                                        .foregroundStyle(meta.color)
                                }

                                Text(meta.displayName)
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(.secondarySystemGroupedBackground))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(isSelected ? meta.color : Color.clear, lineWidth: 2)
                                    )
                                    .shadow(color: Color.black.opacity(0.02), radius: 4, x: 0, y: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .searchable(text: $searchText, prompt: "Search categories")
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
