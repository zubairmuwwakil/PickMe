import CardCopilotCapture
import CoreLocation
import SwiftUI
import UserNotifications

struct CaptureStatusView: View {
    let boundAccountLabel: String?
    let canAssignUnassigned: Bool
    let onRetry: () async -> Void
    let onTestConnection: () async -> Bool
    let onAssignUnassigned: () async throws -> Void
    let onDeleteUnassigned: () async throws -> Void
    let onDisable: (_ deleteUnsent: Bool) async throws -> Void
    let onSubmitDiagnostic: (WalletCaptureDiagnosticReport) async throws -> WalletSubmittedDiagnostic
    let onDeleteSubmittedDiagnostic: (String) async throws -> Void
    let onListSubmittedDiagnostics: () async throws -> [WalletSubmittedDiagnostic]

    @State private var snapshot: WalletCaptureStatusSnapshot?
    @State private var records: [WalletCaptureDiagnosticRecord] = []
    @State private var connection = WalletCaptureSettingsStore().load()
    @State private var notificationState = "Checking…"
    @State private var locationState = "Checking…"
    @State private var isWorking = false
    @State private var actionMessage: String?
    @State private var showingQueue = false
    @State private var showingDisable = false
    @State private var report: WalletCaptureDiagnosticReport?
    @State private var includeTransactionDetails = false
    @State private var submitted: WalletSubmittedDiagnostic?
    @State private var submittedReports: [WalletSubmittedDiagnostic] = []
    @State private var pendingDelete: WalletCaptureDiagnosticRecord?
    @State private var locationManager = CLLocationManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            evidence
            if connection.connectionVerifiedAt == nil { setup }
            if (snapshot?.unassignedCount ?? 0) > 0 { accountDecision }
            actions
            if !submittedReports.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Submitted diagnostics").font(.caption.weight(.semibold))
                    ForEach(submittedReports) { item in
                        HStack {
                            Text("Expires \(item.expiresAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Delete", role: .destructive) { Task { try? await onDeleteSubmittedDiagnostic(item.id); await refresh() } }.font(.caption)
                        }
                    }
                }
            }
            if let actionMessage { Text(actionMessage).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .task { await refresh() }
        .sheet(isPresented: $showingQueue) { queueSheet }
        .sheet(item: $report, onDismiss: { Task { await refresh() } }) { report in
            DiagnosticReportPreview(report: report, submitted: submitted,
                onSend: { try await onSubmitDiagnostic(report) },
                onDeleteSubmission: onDeleteSubmittedDiagnostic)
        }
        .confirmationDialog("Disable Wallet Capture", isPresented: $showingDisable, titleVisibility: .visible) {
            Button("Send queued purchases, then disable") { Task { await disable(deleteUnsent: false) } }
            Button("Delete unsent purchases and disable", role: .destructive) { Task { await disable(deleteUnsent: true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Queued purchases are never discarded without your choice.")
        }
        .alert("Delete this local capture?", isPresented: .init(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete) { item in
            Button("Delete", role: .destructive) { Task { await deleteRecord(item) } }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { _ in Text("This removes the unsent capture and its local diagnostic evidence.") }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Wallet Capture status", systemImage: connection.isEnabled ? "checkmark.shield" : "pause.circle")
                .font(.headline)
            Text("Inunity owns purchase history; PickMe saves each Wallet tap locally before syncing it.")
                .font(.footnote).foregroundStyle(.secondary)
            if !connection.isEnabled { Label("Capture is disabled", systemImage: "pause.fill").foregroundStyle(.orange) }
        }
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusRow("Connection", connection.connectionVerifiedAt.map { "Tested \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Not tested")
            statusRow("Bound account", boundAccountLabel ?? connection.boundUserID.map { String($0.prefix(12)) } ?? "Not connected")
            statusRow("Last Wallet trigger", formatted(snapshot?.lastTriggerAt))
            statusRow("Last accepted upload", formatted(snapshot?.lastAcceptedAt))
            statusRow("Waiting to sync", "\(snapshot?.pendingCount ?? 0)")
            statusRow("Needs account choice", "\(snapshot?.unassignedCount ?? 0)")
            statusRow("Needs review", "\(snapshot?.quarantinedCount ?? 0)")
            statusRow("Oldest pending", formatted(snapshot?.oldestPendingAt))
            statusRow("Notifications", notificationState)
            statusRow("Optional location", locationState)
            if let error = snapshot?.lastSafeError {
                Label("\(safeLabel(error)) · \(safeLabel(snapshot?.failingStage ?? "unknownStage"))",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .font(.subheadline)
    }

    private var isNotificationsAllowed: Bool {
        notificationState == "Allowed"
    }

    private var isLocationAllowed: Bool {
        locationState == "Always allowed" || locationState == "While using app"
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Finish setup").font(.subheadline.weight(.semibold))
            Text("1. Allow notifications so a background Wallet tap can confirm it was saved.")
            if isNotificationsAllowed {
                Label("Notifications allowed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow notifications") { Task { _ = await WalletCaptureNotificationCoordinator.requestPermission(); await refreshPermissions() } }
                    .buttonStyle(.bordered)
            }
            Text("2. Location is optional. When allowed, PickMe tries for a fresh fix for at most two seconds.")
            if isLocationAllowed {
                Label("Location allowed (\(locationState.lowercased()))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow optional location") { locationManager.requestAlwaysAuthorization(); Task { try? await Task.sleep(for: .milliseconds(500)); await refreshPermissions() } }
                    .buttonStyle(.bordered)
            }
            Text("3. In Shortcuts, create a Wallet Transaction automation that runs immediately. Add “Send Wallet Purchase to Inunity” and map Merchant, Amount, Name, Currency Code, and Card or Pass.")
            Link("Open Shortcuts", destination: URL(string: "shortcuts://")!).buttonStyle(.bordered)
            Text("Replace the old Dictionary + Run Wallet Capture V2 actions only after the first native capture succeeds.")
                .font(.caption).foregroundStyle(.secondary)
            Button(isWorking ? "Testing…" : "Test secure connection") { Task { await testConnection() } }
                .buttonStyle(.borderedProminent).disabled(isWorking)
        }
        .font(.footnote)
    }

    private var accountDecision: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Label("Choose where saved captures go", systemImage: "person.crop.circle.badge.questionmark")
                .font(.subheadline.weight(.semibold))
            Text("These captures arrived while no account was connected or a different account was signed in. They will not be sent until you choose.")
                .font(.caption).foregroundStyle(.secondary)
            if canAssignUnassigned {
                Button("Send them to this account") { Task { await assignUnassigned() } }.buttonStyle(.borderedProminent)
            } else {
                Text("Relink Wallet Capture to the signed-in account before assigning these captures.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Button("Delete these unsent captures", role: .destructive) { Task { await deleteUnassigned() } }.buttonStyle(.bordered)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Button("Retry now") { Task { isWorking = true; await onRetry(); isWorking = false; await refresh() } }
                    .buttonStyle(.bordered).disabled(isWorking)
                Button("Review queued events") { showingQueue = true }.buttonStyle(.bordered)
            }
            Toggle("Include transaction details in report", isOn: $includeTransactionDetails)
                .font(.caption)
            Button("Prepare diagnostic report") { Task { await prepareReport(records.first) } }.buttonStyle(.bordered)
                .disabled(records.isEmpty)
            Link("Open transactions in Inunity", destination: URL(string: "https://inunity.ca/purchases")!)
            Button("Disable Wallet Capture", role: .destructive) { showingDisable = true }
        }
        .font(.footnote)
    }

    private var queueSheet: some View {
        NavigationStack {
            List(records.filter { $0.completedAt == nil }) { item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(String(item.eventID.prefix(8))).font(.caption.monospaced()); Spacer(); Text(item.deliveryState.rawValue).font(.caption) }
                    Text(item.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    if !item.missingFields.isEmpty { Text("Missing: \(item.missingFields.joined(separator: ", "))").font(.caption).foregroundStyle(.orange) }
                    if let error = item.safeError { Text(safeLabel(error)).font(.caption).foregroundStyle(.orange) }
                    HStack {
                        Button("Diagnostic") { Task { showingQueue = false; await prepareReport(item) } }
                        Button("Delete", role: .destructive) { showingQueue = false; pendingDelete = item }
                    }.buttonStyle(.borderless)
                }.padding(.vertical, 4)
            }
            .navigationTitle("Queued captures")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingQueue = false } } }
            .overlay { if records.allSatisfy({ $0.completedAt != nil }) { ContentUnavailableView("No queued captures", systemImage: "checkmark.circle") } }
        }
    }

    @ViewBuilder private func statusRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).multilineTextAlignment(.trailing) }
    }
    private func formatted(_ date: Date?) -> String { date?.formatted(date: .abbreviated, time: .shortened) ?? "Never" }
    private func safeLabel(_ value: String) -> String {
        value.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression).capitalized
    }

    private func refresh() async {
        let root = captureRoot()
        guard let outbox = try? WalletOutboxStore(root: root), let diagnostics = try? WalletCaptureDiagnosticsStore(root: root) else { return }
        snapshot = await diagnostics.status(outbox: outbox)
        records = (try? await diagnostics.records()) ?? []
        submittedReports = (try? await onListSubmittedDiagnostics()) ?? []
        connection = WalletCaptureSettingsStore().load()
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
        isWorking = true; defer { isWorking = false }
        if await onTestConnection() { actionMessage = "Connection tested — waiting for your first Wallet tap." }
        else { actionMessage = "The secure connection test failed. Reconnect the installation and try again." }
        await refresh()
    }
    private func assignUnassigned() async {
        do { try await onAssignUnassigned(); actionMessage = "Saved captures assigned to this account." }
        catch { actionMessage = error.localizedDescription }
        await refresh()
    }
    private func deleteUnassigned() async {
        do { try await onDeleteUnassigned(); actionMessage = "Unassigned captures deleted by your request." }
        catch { actionMessage = error.localizedDescription }
        await refresh()
    }
    private func disable(deleteUnsent: Bool) async {
        do { try await onDisable(deleteUnsent); actionMessage = "Wallet Capture disabled." }
        catch { actionMessage = deleteUnsent ? error.localizedDescription : "Queued purchases could not all be sent, so capture remains enabled." }
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
        if let diagnostics = try? WalletCaptureDiagnosticsStore(root: root) { try? await diagnostics.delete(eventID: item.eventID) }
        await refresh()
    }
    private func captureRoot() -> URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ca.inunity.pickme")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

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
                Section("Redacted by default") {
                    LabeledContent("Event", value: report.eventID)
                    LabeledContent("State", value: report.deliveryState)
                    LabeledContent("Attempts", value: "\(report.attemptCount)")
                    if let error = report.safeError { LabeledContent("Safe error", value: error) }
                    Text("Credentials, authorization headers, device identifiers, network names, and precise coordinates are never included.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Timeline") {
                    ForEach(Array(report.timeline.enumerated()), id: \.offset) { _, entry in
                        VStack(alignment: .leading) { Text(entry.stage); Text(entry.at.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if report.includedTransactionDetails, let details = report.transactionDetails {
                    Section("Included by your choice") {
                        ForEach(details.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: (details[key] ?? nil) ?? "Missing")
                        }
                    }
                }
                Section {
                    if let sent = sent ?? submitted {
                        Label("Sent securely; expires \(sent.expiresAt.formatted(date: .abbreviated, time: .omitted))", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        Button("Delete submitted report now", role: .destructive) { Task { try? await onDeleteSubmission(sent.id); self.sent = nil; message = "Submitted report deleted." } }
                    } else {
                        Button(working ? "Sending…" : "Send diagnostic report") {
                            Task { working = true; defer { working = false }; do { sent = try await onSend() } catch { message = error.localizedDescription } }
                        }.disabled(working)
                    }
                    if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Diagnostic preview")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
