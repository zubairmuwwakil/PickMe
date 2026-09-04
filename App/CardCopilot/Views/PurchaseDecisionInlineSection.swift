import SwiftUI
import CardCopilotEngine

/// Checkout-only interaction for the final multi-attribute decision layer.
///
/// The selected purchase type is intentionally a Binding owned by RecommendationView. It is
/// ephemeral checkout state: it survives amount refinements and route refreshes while this answer
/// is on screen, but is not written to purchase history, UserDefaults, account sync, or analytics.
struct PurchaseDecisionInlineSection: View {
    let assessment: PurchaseDecisionAssessment
    @Binding var selectedContextKind: BenefitContextKind?
    let rewardCardName: String
    let protectionLeaderName: String?
    let onCompare: ((BenefitContextKind) -> Void)?

    var body: some View {
        if assessment.verdict != .rewardLeader || selectedContextKind != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(accent)
                        Text(detail)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if assessment.verdict == .purchaseContextNeeded || selectedContextKind != nil {
                    PurchaseContextChoiceRow(selection: $selectedContextKind)
                }

                if let selectedContextKind,
                   selectedContextKind != .other,
                   assessment.verdict != .purchaseContextNeeded,
                   onCompare != nil {
                    Button {
                        onCompare?(selectedContextKind)
                    } label: {
                        Label("Compare protection details", systemImage: "shield.lefthalf.filled")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(accent.opacity(0.26), lineWidth: 1)
                    )
            )
        }
    }

    private var title: String {
        switch assessment.verdict {
        case .rewardLeader:
            return "REWARDS LEAD"
        case .rewardProtectionAligned:
            return "REWARDS + PROTECTION ALIGN"
        case .rewardProtectionTradeoff:
            return "REWARD / PROTECTION TRADE-OFF"
        case .protectionTradeoffUnresolved:
            return "PROTECTION TRADE-OFF"
        case .purchaseContextNeeded:
            return "WHAT ARE YOU BUYING?"
        }
    }

    private var detail: String {
        switch assessment.verdict {
        case .rewardLeader:
            if selectedContextKind == .other {
                return "You marked this as an everyday/other purchase, so the modeled shopping-protection contexts do not change the reward result."
            }
            if let selectedContextKind {
                return "For \(PurchaseContextChoiceRow.label(for: selectedContextKind).lowercased()), PickMe found no material trusted protection conflict with the reward result."
            }
            return "No material trusted protection conflict was identified."
        case .rewardProtectionAligned:
            return "\(rewardCardName) leads on rewards and the verified protection comparison for this purchase type."
        case .rewardProtectionTradeoff:
            let protectionName = protectionLeaderName ?? "another card"
            return "\(rewardCardName) leads on rewards, while \(protectionName) leads on the relevant verified protection facts. PickMe will not invent a dollar value to hide that trade-off."
        case .protectionTradeoffUnresolved:
            return "The verified protections themselves have a genuine trade-off, so there is no single protection winner to silently override the reward result."
        case .purchaseContextNeeded:
            return "This purchase is large enough that verified shopping protections may matter. Merchant category does not tell PickMe what item you are buying, so choose the purchase type to finish the decision."
        }
    }

    private var accent: Color {
        switch assessment.verdict {
        case .rewardProtectionAligned:
            return .green
        case .rewardProtectionTradeoff, .protectionTradeoffUnresolved, .purchaseContextNeeded:
            return .orange
        case .rewardLeader:
            return .blue
        }
    }

    private var icon: String {
        switch assessment.verdict {
        case .rewardProtectionAligned:
            return "checkmark.shield.fill"
        case .rewardProtectionTradeoff, .protectionTradeoffUnresolved:
            return "exclamationmark.shield.fill"
        case .purchaseContextNeeded:
            return "questionmark.circle.fill"
        case .rewardLeader:
            return "checkmark.circle.fill"
        }
    }
}

/// Reusable purchase-type selector shared by direct checkout and alternate-route warnings.
/// Selection changes only the decision context; it never mutates merchant category or MCC.
/// `.other` means the user explicitly says none of the modelled protection-sensitive contexts
/// apply; `nil` remains the separate "purchase type unknown" state.
struct PurchaseContextChoiceRow: View {
    @Binding var selection: BenefitContextKind?

    private static let choices: [BenefitContextKind] = [
        .electronics,
        .mobileDevice,
        .applianceFurniture,
        .other,
    ]

    private let columns = [GridItem(.adaptive(minimum: 105), spacing: 7)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 7) {
            ForEach(Self.choices, id: \.rawValue) { kind in
                Button {
                    selection = kind
                } label: {
                    Text(Self.label(for: kind))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule()
                                .fill(selection == kind
                                      ? Color.accentColor.opacity(0.16)
                                      : Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            Capsule()
                                .stroke(selection == kind
                                        ? Color.accentColor.opacity(0.45)
                                        : Color.secondary.opacity(0.15),
                                        lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == kind ? Color.accentColor : Color.primary)
            }
        }
    }

    static func label(for kind: BenefitContextKind) -> String {
        switch kind {
        case .electronics:
            return "Electronics"
        case .mobileDevice:
            return "Phone"
        case .applianceFurniture:
            return "Appliance"
        case .other:
            return "Everyday / other"
        case .flight:
            return "Flight"
        case .trip:
            return "Trip"
        case .carRental:
            return "Car rental"
        }
    }
}
