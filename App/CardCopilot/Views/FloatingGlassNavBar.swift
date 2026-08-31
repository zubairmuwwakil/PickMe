import SwiftUI

/// The 5 core tabs of PickMe.
enum AppTab: String, CaseIterable, Identifiable {
    case copilot = "Copilot"
    case activity = "Activity"
    case wallet = "Wallet"
    case perks = "Perks"
    case you = "You"

    var id: String { rawValue }

    var selectedIcon: String {
        switch self {
        case .copilot: return "sparkles"
        case .activity: return "tray.full.fill"
        case .wallet: return "creditcard.fill"
        case .perks: return "shield.lefthalf.filled"
        case .you: return "person.crop.circle.fill"
        }
    }

    var unselectedIcon: String {
        switch self {
        case .copilot: return "sparkles"
        case .activity: return "tray.full"
        case .wallet: return "creditcard"
        case .perks: return "shield"
        case .you: return "person.crop.circle"
        }
    }
}

/// A floating glass pill bottom navigation bar inspired by liquid glass UI design.
struct FloatingGlassNavBar: View {
    @Binding var selectedTab: AppTab
    let activityBadgeCount: Int
    let hasYouAlert: Bool
    @Namespace private var animationNamespace
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(for: tab)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            ZStack {
                // 1. Frosted Liquid Glass Material
                Capsule()
                    .fill(.ultraThinMaterial)

                // 2. Adaptive Subtle Glass Tint
                Capsule()
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(0.05)
                            : Color.white.opacity(0.48)
                    )

                // 3. Specular refraction top highlight
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.15 : 0.45),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )

                // 4. Specular Glass Rim / Border
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.35 : 0.75),
                                Color.white.opacity(colorScheme == .dark ? 0.10 : 0.25),
                                Color.black.opacity(colorScheme == .dark ? 0.25 : 0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        // Soft Multi-Layered Elevation Shadows
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.09),
            radius: 16,
            x: 0,
            y: 8
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.20 : 0.04),
            radius: 4,
            x: 0,
            y: 2
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func tabButton(for tab: AppTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            if selectedTab != tab {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    selectedTab = tab
                }
            }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    // Active Background Pill Glow / Indicator
                    if isSelected {
                        Capsule()
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.12)
                                    : Color.black.opacity(0.07)
                            )
                            .matchedGeometryEffect(id: "activeTabPill", in: animationNamespace)
                            .frame(width: 52, height: 32)
                    } else {
                        Capsule()
                            .fill(Color.clear)
                            .frame(width: 52, height: 32)
                    }

                    // Tab Icon
                    Image(systemName: isSelected ? tab.selectedIcon : tab.unselectedIcon)
                        .font(.system(size: isSelected ? 19 : 18, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .symbolRenderingMode(.hierarchical)
                        .scaleEffect(isSelected ? 1.05 : 1.0)

                    // Badges
                    badgeOverlay(for: tab)
                }

                // Tab Title
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainTabButtonStyle())
    }

    @ViewBuilder
    private func badgeOverlay(for tab: AppTab) -> some View {
        switch tab {
        case .activity:
            if activityBadgeCount > 0 {
                VStack {
                    HStack {
                        Spacer()
                        Text(activityBadgeCount > 99 ? "99+" : "\(activityBadgeCount)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                // Vibrant Emerald Green badge matching reference UI
                                Color(red: 0.13, green: 0.77, blue: 0.37),
                                in: Capsule()
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                            )
                            .offset(x: 10, y: -10)
                    }
                    Spacer()
                }
                .frame(width: 52, height: 32)
            }
        case .you:
            if hasYouAlert {
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(Color(red: 0.13, green: 0.77, blue: 0.37))
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.8), lineWidth: 1.5)
                            )
                            .offset(x: 8, y: -8)
                    }
                    Spacer()
                }
                .frame(width: 52, height: 32)
            }
        default:
            EmptyView()
        }
    }
}

/// A button style that provides a subtle press scale effect.
private struct PlainTabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}
