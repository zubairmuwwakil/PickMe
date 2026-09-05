import CardCopilotCapture
import CoreLocation
import SwiftUI
import UserNotifications

struct CaptureStatusView: View {
    let boundAccountLabel: String?
    let canAssignUnassigned: Bool
    let onRetry: () async -> Void
    let onTestConnection: () async -> WalletCaptureConnectionTestResult
    let onAssignUnassigned: () async throws -> Void
    let onDeleteUnassigned: () async throws -> Void
    let onDisable: (_ deleteUnsent: Bool) async throws -> Void
    var onEnable: (() async -> Void)? = nil
    let onSubmitDiagnostic: (WalletCaptureDiagnosticReport) async throws -> WalletSubmittedDiagnostic
    let onDeleteSubmittedDiagnostic: (String) async throws -> Void
    let onListSubmittedDiagnostics: () async throws -> [WalletSubmittedDiagnostic]

    @State private var snapshot: WalletCaptureStatusSnapshot?
    @State private var records: [WalletCaptureDiagnosticRecord] = []
    @State private var connection = WalletCaptureSettingsStore().load()
    @State private var notificationState = "Checking…"
    @State private var locationState = "Checking…"
    @State private var isWorking = false
    @State private var isTestingConnection = false
    @State private var actionMessage: String?
    @State private var showingQueue = false
    @State private var showingDisable = false
    @State private var showingShortcutsGuide = false
    @State private var tutorialInitialStep: ShortcutsTutorialStep = .intro
    @State private var latestShortcutLog: WalletCaptureShortcutRunLog?
    @State private var report: WalletCaptureDiagnosticReport?
    @State private var includeTransactionDetails = false
    @State private var submitted: WalletSubmittedDiagnostic?
    @State private var submittedReports: [WalletSubmittedDiagnostic] = []
    @State private var pendingDelete: WalletCaptureDiagnosticRecord?
    @State private var locationManager = CLLocationManager()

    private var isNotificationsAllowed: Bool {
        notificationState == "Allowed"
    }

    private var isLocationAllowed: Bool {
        locationState == "Always allowed" || locationState == "While using app"
    }

    private var isFullySetup: Bool {
        connection.isEnabled && connection.connectionVerifiedAt != nil && isNotificationsAllowed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 1. Header Banner with Live Status Badge
            headerBanner

            // 2. 2x2 Metric & Outbox Activity Grid
            metricsGrid

            // 3. Unassigned Account Decision (if needed)
            if (snapshot?.unassignedCount ?? 0) > 0 {
                accountDecisionCard
            }

            // 4. Interactive Step-by-Step Setup Checklist
            setupChecklistSection

            // 5. Diagnostics & Advanced Tools
            diagnosticsAndActionsSection

            // 6. Action Feedback / Status Message
            if let actionMessage {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                        .font(.caption)
                    Text(actionMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)
                .transition(.opacity)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
        .task { await refresh() }
        .sheet(isPresented: $showingQueue) { queueSheet }
        .sheet(isPresented: $showingShortcutsGuide) { ShortcutsSetupTutorialView(initialStep: tutorialInitialStep) }
        .sheet(item: $report, onDismiss: { Task { await refresh() } }) { report in
            DiagnosticReportPreview(
                report: report,
                submitted: submitted,
                onSend: { try await onSubmitDiagnostic(report) },
                onDeleteSubmission: onDeleteSubmittedDiagnostic
            )
        }
        .confirmationDialog("Disable or Pause Wallet Capture", isPresented: $showingDisable, titleVisibility: .visible) {
            Button("Pause Wallet Capture") { Task { await pause() } }
            Button("Send queued purchases, then disable") { Task { await disable(deleteUnsent: false) } }
            Button("Delete unsent purchases and disable", role: .destructive) { Task { await disable(deleteUnsent: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Queued purchases are saved locally on this iPhone and are never discarded without your choice.")
        }
        .alert("Delete this local capture?", isPresented: .init(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { item in
            Button("Delete", role: .destructive) { Task { await deleteRecord(item) } }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text("This permanently removes the unsent capture and its local diagnostic evidence from this iPhone.")
        }
    }

    // MARK: - 1. Header Banner

    private var headerBanner: some View {
        HStack(alignment: .center, spacing: 14) {
            // Icon Squircle (Tappable)
            Button {
                Task { await toggleEnabled() }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: connection.isEnabled
                                    ? [Color(red: 0.12, green: 0.50, blue: 1.0), Color(red: 0.25, green: 0.35, blue: 0.95)]
                                    : [Color.orange.opacity(0.85), Color.orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: (connection.isEnabled ? Color.blue : Color.orange).opacity(0.25), radius: 5, x: 0, y: 2)

                    Image(systemName: connection.isEnabled ? "wallet.pass.fill" : "pause.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text("Apple Wallet Capture")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Local on-device tap ingestion")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Live Status Pill (Tappable)
            Button {
                Task { await toggleEnabled() }
            } label: {
                statusBadge
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if !connection.isEnabled {
            HStack(spacing: 5) {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                Text("Paused")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(Color.orange.opacity(0.12), in: Capsule())
        } else if connection.connectionVerifiedAt != nil {
            HStack(spacing: 5) {
                Circle().fill(Color(red: 0.13, green: 0.77, blue: 0.37)).frame(width: 6, height: 6)
                Text("Active")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(Color.green.opacity(0.12), in: Capsule())
        } else {
            HStack(spacing: 5) {
                Circle().fill(Color.blue).frame(width: 6, height: 6)
                Text("Setup Ready")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(Color.blue.opacity(0.12), in: Capsule())
        }
    }

    // MARK: - 2. 2x2 Metric & Outbox Activity Grid

    private var metricsGrid: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                metricCard(
                    icon: "icloud.fill",
                    iconColor: .blue,
                    title: "Capture Link",
                    value: connection.connectionVerifiedAt != nil ? "Verified" : "Not Tested",
                    subtitle: connection.connectionVerifiedAt.map { "Tested \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Tap test below"
                )

                metricCard(
                    icon: "bolt.fill",
                    iconColor: .orange,
                    title: "Last Wallet Tap",
                    value: formatted(snapshot?.lastTriggerAt),
                    subtitle: snapshot?.lastTriggerAt != nil ? "Saved to outbox" : "Waiting for tap"
                )
            }

            HStack(spacing: 8) {
                metricCard(
                    icon: "lock.shield.fill",
                    iconColor: .purple,
                    title: "Linked Account",
                    value: boundAccountLabel ?? connection.boundUserID.map { String($0.prefix(10)) + "…" } ?? "Not linked",
                    subtitle: "Protected device credential"
                )

                metricCard(
                    icon: (snapshot?.pendingCount ?? 0) > 0 ? "tray.and.arrow.up.fill" : "tray.fill",
                    iconColor: (snapshot?.pendingCount ?? 0) > 0 ? .blue : .secondary,
                    title: "Purchase Outbox",
                    value: "\(snapshot?.pendingCount ?? 0) waiting",
                    subtitle: (snapshot?.quarantinedCount ?? 0) > 0 ? "\(snapshot?.quarantinedCount ?? 0) in review" : "Up to date"
                )
            }

            if let error = snapshot?.lastSafeError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("\(safeLabel(error)) · \(safeLabel(snapshot?.failingStage ?? "unknownStage"))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func metricCard(icon: String, iconColor: Color, title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(subtitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.tertiarySystemFill))
        )
    }

    // MARK: - 3. Account Decision Card

    private var accountDecisionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Unassigned Captures Pending")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Found \(snapshot?.unassignedCount ?? 0) taps saved before this account was signed in.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                if canAssignUnassigned {
                    Button {
                        Task { await assignUnassigned() }
                    } label: {
                        Text("Assign to This Account")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Button(role: .destructive) {
                    Task { await deleteUnassigned() }
                } label: {
                    Text("Delete Unsent")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.red.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - 4. Interactive Step-by-Step Setup Checklist

    private var setupChecklistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SETUP CHECKLIST")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)

                Spacer()

                if isFullySetup {
                    Label("Complete", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))
                }
            }

            if let latest = latestShortcutLog, latest.outcome == "mappingIncomplete" || !latest.input.merchantPresent {
                incompleteMappingWarningCard(latest)
            }

            VStack(spacing: 0) {
                // Step 1: Notifications
                setupStepRow(
                    stepNumber: "1",
                    icon: "bell.badge.fill",
                    iconColor: .pink,
                    title: "Tap Confirmations",
                    subtitle: "Instant notification when a Wallet tap is saved",
                    isComplete: isNotificationsAllowed
                ) {
                    if isNotificationsAllowed {
                        completePill("Allowed")
                    } else {
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            Task {
                                _ = await WalletCaptureNotificationCoordinator.requestPermission()
                                await refreshPermissions()
                            }
                        } label: {
                            actionButtonLabel("Allow")
                        }
                        .buttonStyle(.plain)
                    }
                }

                stepDivider

                // Step 2: Location
                setupStepRow(
                    stepNumber: "2",
                    icon: "location.fill",
                    iconColor: .blue,
                    title: "Merchant Location Fix",
                    subtitle: "2s GPS check to identify the exact branch",
                    isComplete: isLocationAllowed
                ) {
                    if isLocationAllowed {
                        completePill("Allowed")
                    } else {
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            locationManager.requestAlwaysAuthorization()
                            Task {
                                try? await Task.sleep(for: .milliseconds(500))
                                await refreshPermissions()
                            }
                        } label: {
                            actionButtonLabel("Allow")
                        }
                        .buttonStyle(.plain)
                    }
                }

                stepDivider

                // Step 3: Apple Shortcuts Automation
                setupStepRow(
                    stepNumber: "3",
                    icon: "bolt.horizontal.fill",
                    iconColor: .purple,
                    title: "Shortcuts Automation",
                    subtitle: "Runs automatically on card tap",
                    isComplete: snapshot?.lastTriggerAt != nil
                ) {
                    HStack(spacing: 6) {
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            tutorialInitialStep = .openAutomationTab
                            showingShortcutsGuide = true
                        } label: {
                            Text("Walkthrough")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Link(destination: URL(string: "shortcuts://")!) {
                            HStack(spacing: 3) {
                                Text("Open")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue, in: Capsule())
                        }
                    }
                }

                stepDivider

                // Step 4: End-to-End Connection Test
                setupStepRow(
                    stepNumber: "4",
                    icon: "checkmark.shield.fill",
                    iconColor: .teal,
                    title: "Verify Secure Link",
                    subtitle: connection.connectionVerifiedAt.map { "Tested \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Tests credentials & outbox pipeline",
                    isComplete: connection.connectionVerifiedAt != nil
                ) {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        Task { await testConnection() }
                    } label: {
                        HStack(spacing: 5) {
                            if isTestingConnection {
                                ProgressView()
                                    .controlSize(.mini)
                                    .tint(.white)
                            }
                            Text(isTestingConnection ? "Testing…" : (connection.connectionVerifiedAt != nil ? "Retest" : "Test Link"))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(connection.connectionVerifiedAt != nil ? Color.primary : Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            connection.connectionVerifiedAt != nil
                                ? Color(.tertiarySystemFill)
                                : Color.blue,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isTestingConnection)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
        }
    }

    private func setupStepRow<Trailing: View>(
        stepNumber: String,
        icon: String,
        iconColor: Color,
        title: String,
        subtitle: String,
        isComplete: Bool,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.16))
                    .frame(width: 32, height: 32)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var stepDivider: some View {
        Divider().padding(.leading, 50)
    }

    private func completePill(_ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .bold, design: .rounded))
        }
        .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.12), in: Capsule())
    }

    private func actionButtonLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Color.blue, in: Capsule())
    }

    // MARK: - 5. Diagnostics & Advanced Tools

    private var diagnosticsAndActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MANAGEMENT & TOOLS")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.8)

            VStack(spacing: 0) {
                // Review Queued Events
                Button {
                    showingQueue = true
                } label: {
                    toolRow(
                        icon: "tray.2.fill",
                        iconColor: .blue,
                        title: "Review Queued Events",
                        trailingBadge: "\(records.filter { $0.completedAt == nil }.count)"
                    )
                }
                .buttonStyle(RowPressStyle())

                toolDivider

                // Diagnostic Report
                Button {
                    Task { await prepareReport(records.first) }
                } label: {
                    toolRow(
                        icon: "stethoscope",
                        iconColor: .indigo,
                        title: "Prepare Diagnostic Report",
                        trailingBadge: records.isEmpty ? "No data" : nil
                    )
                }
                .buttonStyle(RowPressStyle())
                .disabled(records.isEmpty)

                toolDivider

                // Include transaction details toggle
                Toggle(isOn: $includeTransactionDetails) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: 26, height: 26)
                            Image(systemName: "eye.slash.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Include Transaction Metadata")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Text("Merchant & amount for diagnosing parse issues")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                toolDivider

                // External Link to Web Dashboard
                Link(destination: URL(string: "https://inunity.ca/purchases")!) {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.blue.opacity(0.12))
                                .frame(width: 26, height: 26)
                            Image(systemName: "safari.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.blue)
                        }
                        Text("Open Purchases in In Unity")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.blue)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }

                toolDivider

                // Pause / Enable / Disconnect
                Button {
                    Task { await toggleEnabled() }
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(connection.isEnabled ? Color.orange.opacity(0.12) : Color.green.opacity(0.12))
                                .frame(width: 26, height: 26)
                            Image(systemName: connection.isEnabled ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(connection.isEnabled ? Color.orange : Color(red: 0.13, green: 0.77, blue: 0.37))
                        }
                        Text(connection.isEnabled ? "Pause Wallet Capture" : "Enable Wallet Capture")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(connection.isEnabled ? Color.orange : Color(red: 0.13, green: 0.77, blue: 0.37))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(RowPressStyle())
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )

            // Submitted Diagnostic History (if any)
            if !submittedReports.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("SUBMITTED DIAGNOSTIC PACKETS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                        .padding(.top, 4)

                    ForEach(submittedReports) { item in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text("Expires \(item.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Delete", role: .destructive) {
                                Task {
                                    try? await onDeleteSubmittedDiagnostic(item.id)
                                    await refresh()
                                }
                            }
                            .font(.caption.weight(.bold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func toolRow(icon: String, iconColor: Color, title: String, trailingBadge: String? = nil) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)

            Spacer()

            if let trailingBadge {
                Text(trailingBadge)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemBackground), in: Capsule())
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var toolDivider: some View {
        Divider().padding(.leading, 48)
    }

    // MARK: - Queue Sheet

    private var queueSheet: some View {
        NavigationStack {
            List {
                let pending = records.filter { $0.completedAt == nil }
                if pending.isEmpty {
                    ContentUnavailableView("Outbox Up to Date", systemImage: "checkmark.circle.fill",
                                           description: Text("All recorded Wallet tap events have synced successfully."))
                } else {
                    ForEach(pending) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(String(item.eventID.prefix(8)))
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                Spacer()
                                Text(item.deliveryState.rawValue.capitalized)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.blue)
                            }

                            Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !item.missingFields.isEmpty {
                                Text("Missing: \(item.missingFields.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            if let error = item.safeError {
                                Text(safeLabel(error))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            HStack(spacing: 12) {
                                Button("Diagnostic Preview") {
                                    Task {
                                        showingQueue = false
                                        await prepareReport(item)
                                    }
                                }
                                .font(.caption.weight(.semibold))

                                Spacer()

                                Button("Delete", role: .destructive) {
                                    showingQueue = false
                                    pendingDelete = item
                                }
                                .font(.caption.weight(.semibold))
                            }
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Queued Captures")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingQueue = false }
                        .font(.headline)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let mins = max(1, seconds / 60)
            return "\(mins)m ago"
        } else if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
    }

    private func safeLabel(_ value: String) -> String {
        value.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
    }

    private func refresh() async {
        let root = captureRoot()
        guard let outbox = try? WalletOutboxStore(root: root),
              let diagnostics = try? WalletCaptureDiagnosticsStore(root: root) else { return }
        snapshot = await diagnostics.status(outbox: outbox)
        records = (try? await diagnostics.records()) ?? []
        submittedReports = (try? await onListSubmittedDiagnostics()) ?? []
        connection = WalletCaptureSettingsStore().load()
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let runLogs = try? WalletCaptureShortcutRunLogStore(documentsDirectory: documents),
           let allLogs = try? await runLogs.records() {
            latestShortcutLog = allLogs.first
        }
        await refreshPermissions()
    }

    private func refreshPermissions() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationState = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "Allowed"
        case .denied: "Denied — in-app status remains available"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }

        locationState = switch locationManager.authorizationStatus {
        case .authorizedAlways: "Always allowed"
        case .authorizedWhenInUse: "While using app"
        case .denied: "Denied — capture continues"
        case .restricted: "Restricted — capture continues"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private func testConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }
        let result = await onTestConnection()
        if result.isConnected {
            actionMessage = "Connection verified! Ready for your first Apple Wallet card tap."
        } else {
            actionMessage = "Secure test failed: \(result.failureReason ?? "Please retry or reconnect installation.")"
        }
        await refresh()
    }

    private func assignUnassigned() async {
        do {
            try await onAssignUnassigned()
            actionMessage = "Captures assigned to this account and queued for sync."
        } catch {
            actionMessage = error.localizedDescription
        }
        await refresh()
    }

    private func deleteUnassigned() async {
        do {
            try await onDeleteUnassigned()
            actionMessage = "Unassigned captures removed."
        } catch {
            actionMessage = error.localizedDescription
        }
        await refresh()
    }

    private func enable() async {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        if let onEnable {
            await onEnable()
        } else {
            WalletCaptureSettingsStore().setEnabled(true)
        }
        actionMessage = "Wallet Capture enabled."
        await refresh()
    }

    private func pause() async {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        WalletCaptureSettingsStore().setEnabled(false)
        actionMessage = "Wallet Capture paused."
        await refresh()
    }

    private func toggleEnabled() async {
        if connection.isEnabled {
            if (snapshot?.pendingCount ?? 0) > 0 {
                showingDisable = true
            } else {
                await pause()
            }
        } else {
            await enable()
        }
    }

    private func disable(deleteUnsent: Bool) async {
        do {
            try await onDisable(deleteUnsent)
            actionMessage = "Wallet Capture disabled."
        } catch {
            actionMessage = deleteUnsent ? error.localizedDescription : "Queued purchases could not all be sent; capture remains active."
        }
        await refresh()
    }

    private func prepareReport(_ item: WalletCaptureDiagnosticRecord?) async {
        guard let item, let diagnostics = try? WalletCaptureDiagnosticsStore(root: captureRoot()) else { return }
        report = try? await diagnostics.prepareReport(eventID: item.eventID, includeTransactionDetails: includeTransactionDetails)
        submitted = nil
    }

    private func deleteRecord(_ item: WalletCaptureDiagnosticRecord) async {
        pendingDelete = nil
        let root = captureRoot()
        if let outbox = try? WalletOutboxStore(root: root) {
            for bucket in [WalletOutboxBucket.pending, .inflight, .unassigned, .quarantined] {
                try? await outbox.delete(eventID: item.eventID, from: bucket)
            }
        }
        if let diagnostics = try? WalletCaptureDiagnosticsStore(root: root) {
            try? await diagnostics.delete(eventID: item.eventID)
        }
        await refresh()
    }

    private func captureRoot() -> URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ca.inunity.pickme")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // MARK: - Incomplete Mapping Warning Card

    private func incompleteMappingWarningCard(_ log: WalletCaptureShortcutRunLog) -> some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            tutorialInitialStep = .mapParameters
            showingShortcutsGuide = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 16, weight: .bold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Shortcut Missing Parameters")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.orange)
                        Spacer()
                        Text("Fix Setup")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange, in: Capsule())
                    }
                    Text("Your last tap arrived without merchant info. Tap to view the variable mapping guide.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Diagnostic Report Preview

private struct DiagnosticReportPreview: View {
    let report: WalletCaptureDiagnosticReport
    let submitted: WalletSubmittedDiagnostic?
    let onSend: () async throws -> WalletSubmittedDiagnostic
    let onDeleteSubmission: (String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var sent: WalletSubmittedDiagnostic?
    @State private var message: String?
    @State private var working = false

    var body: some View {
        NavigationStack {
            List {
                Section("Redacted by Default (Privacy Shield)") {
                    LabeledContent("Event ID", value: report.eventID)
                    LabeledContent("Delivery State", value: report.deliveryState.capitalized)
                    LabeledContent("Attempt Count", value: "\(report.attemptCount)")
                    if let error = report.safeError {
                        LabeledContent("Safe Error", value: error)
                    }
                    Text("Secrets, authorization tokens, device identifiers, and precise location coordinates are never included.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Timeline") {
                    ForEach(Array(report.timeline.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(entry.stage)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                            Spacer()
                            Text(entry.at.formatted(date: .omitted, time: .standard))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if report.includedTransactionDetails, let details = report.transactionDetails {
                    Section("Included by User Choice") {
                        ForEach(details.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: (details[key] ?? nil) ?? "Missing")
                        }
                    }
                }

                Section {
                    if let sent = sent ?? submitted {
                        Label("Sent securely; expires \(sent.expiresAt.formatted(date: .abbreviated, time: .omitted))",
                              systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.subheadline.weight(.semibold))

                        Button("Delete Submitted Report", role: .destructive) {
                            Task {
                                do {
                                    try await onDeleteSubmission(sent.id)
                                    self.sent = nil
                                    message = "Diagnostic report deleted from server."
                                } catch {
                                    message = "The report was not deleted. \(error.localizedDescription)"
                                }
                            }
                        }
                    } else {
                        Button {
                            Task {
                                working = true
                                defer { working = false }
                                do {
                                    sent = try await onSend()
                                } catch {
                                    message = error.localizedDescription
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                if working {
                                    ProgressView().tint(.white).padding(.trailing, 6)
                                }
                                Text(working ? "Transmitting…" : "Send Diagnostic Report")
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                Spacer()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(working)
                    }

                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Diagnostic Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.headline)
                }
            }
        }
    }
}

private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color(.systemFill) : Color.clear)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
