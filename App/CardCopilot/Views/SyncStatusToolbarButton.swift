import SwiftUI
import CardCopilotStore

/// A dynamic navigation bar button displaying real-time sync status indicators.
/// Replaces the bulky in-body sync row with an unobtrusive, multi-state status cue.
public struct SyncStatusToolbarButton: View {
    public let isSyncing: Bool
    public let lastSyncedAt: Date?
    public let syncIssue: SyncStatusIssue?
    public let action: () -> Void

    public init(
        isSyncing: Bool,
        lastSyncedAt: Date?,
        syncIssue: SyncStatusIssue?,
        action: @escaping () -> Void
    ) {
        self.isSyncing = isSyncing
        self.lastSyncedAt = lastSyncedAt
        self.syncIssue = syncIssue
        self.action = action
    }

    private var isStale: Bool {
        guard let lastSyncedAt else { return false }
        return Date().timeIntervalSince(lastSyncedAt) > 3600
    }

    private var statusIcon: String {
        if isSyncing {
            return "arrow.triangle.2.circlepath"
        } else if let syncIssue {
            return syncIssue.kind == .error ? "exclamationmark.icloud.fill" : "exclamationmark.triangle.fill"
        } else if lastSyncedAt != nil {
            return isStale ? "arrow.triangle.2.circlepath.icloud" : "checkmark.icloud.fill"
        } else {
            return "icloud"
        }
    }

    private var statusColor: Color {
        if isSyncing {
            return .blue
        } else if let syncIssue {
            return syncIssue.kind == .error ? .red : .orange
        } else if lastSyncedAt != nil {
            return isStale ? .orange : .primary
        } else {
            return .secondary
        }
    }

    private var badgeDotColor: Color? {
        if isSyncing {
            return .blue
        } else if let syncIssue {
            return syncIssue.kind == .error ? .red : .orange
        } else if lastSyncedAt != nil {
            return isStale ? .orange : .green
        } else {
            return nil
        }
    }

    private var accessibilityText: String {
        if isSyncing {
            return "Syncing in progress"
        } else if let syncIssue {
            return "Sync issue: \(syncIssue.message)"
        } else if let lastSyncedAt {
            let seconds = Int(Date().timeIntervalSince(lastSyncedAt))
            if seconds < 60 {
                return "Spending caps updated just now"
            } else if seconds < 3600 {
                let mins = max(1, seconds / 60)
                return "Spending caps updated \(mins) minute\(mins == 1 ? "" : "s") ago"
            } else {
                let hours = seconds / 3600
                return "Spending caps updated \(hours) hour\(hours == 1 ? "" : "s") ago"
            }
        } else {
            return "Sync & Wallet Capture"
        }
    }

    public var body: some View {
        Button {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        } label: {
            ZStack(alignment: .topTrailing) {
                // Main Icon with subtle circular background
                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemGroupedBackground))
                        .frame(width: 36, height: 36)
                        .shadow(color: Color.black.opacity(0.06), radius: 4, x: 0, y: 1)

                    if isSyncing {
                        Image(systemName: statusIcon)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(statusColor)
                            .symbolEffect(.rotate, isActive: true)
                    } else {
                        Image(systemName: statusIcon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(statusColor)
                    }
                }

                // Status Badge Dot
                if let dotColor = badgeDotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(Color(.systemBackground), lineWidth: 1.5)
                        )
                        .offset(x: 1, y: -1)
                }
            }
            .contentShape(Circle())
        }
        .buttonStyle(SyncToolbarPressStyle())
        .accessibilityLabel(accessibilityText)
    }
}

private struct SyncToolbarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}
