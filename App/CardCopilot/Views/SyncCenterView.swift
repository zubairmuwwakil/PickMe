import SwiftUI
import ClerkKitUI
import ClerkKit
import CardCopilotStore
import CardCopilotCapture

/// Optional account and capture setup; checkout itself remains entirely offline-capable.
struct SyncCenterView: View {
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss

    let isSignedIn: Bool
    let onSync: () async -> Void
    let boundAccountLabel: String?
    let isCaptureBoundToCurrentAccount: Bool

    @State private var authIsPresented = false
    @State private var installationName = "My iPhone"
    @State private var installationWasCreated = false
    @State private var tokenError: String?
    @State private var connectionNotice: String?
    @State private var isCreatingToken = false
    @State private var isShowingCreateForm = false
    @State private var pendingRevocation: WalletInstallation?
    @State private var showingShortcutsTutorial = false

    private var activeInstallations: [WalletInstallation] {
        sync.walletInstallations.filter { $0.revokedAt == nil }
    }

    private var hasLocalCredential: Bool {
        installationWasCreated || WalletCaptureCredentialStore().load() != nil
    }

    private var localInstallationID: String? { WalletCaptureCredentialStore().load()?.installationID }
    private var otherActiveInstallations: [WalletInstallation] {
        activeInstallations.filter { $0.id != localInstallationID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !MoneyTalksConfiguration.isConfigured {
                    configurationRequired
                } else if !isSignedIn {
                    signInRequired
                } else if sync.isPreparingAccount {
                    preparingAccount
                } else if sync.readySyncUserID != ClerkSession.currentUserID {
                    accountUnavailable
                } else {
                    connectedContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sync & Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: { dismiss() })
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }
        }
        .sheet(isPresented: $authIsPresented) {
            PickMeAuthSheet()
        }
        .sheet(isPresented: $showingShortcutsTutorial) {
            ShortcutsSetupTutorialView()
        }
        .alert("Revoke this connection?", isPresented: .init(
            get: { pendingRevocation != nil },
            set: { if !$0 { pendingRevocation = nil } }
        ), presenting: pendingRevocation) { item in
            Button("Revoke Connection", role: .destructive) { Task { await revokeInstallation(item) } }
            Button("Cancel", role: .cancel) { pendingRevocation = nil }
        } message: { _ in
            Text("Only the selected server credential is revoked. Purchases already saved on this iPhone are never deleted.")
        }
    }

    // MARK: - Configuration Required

    private var configurationRequired: some View {
        ContentUnavailableView(
            "Sync Setup Required",
            systemImage: "key.horizontal",
            description: Text("Checkout stays fully offline-capable. Add the In Unity Clerk key and API URL in configuration to enable cross-device cloud sync.")
        )
    }

    // MARK: - Sign In Required (Hero Presentation)

    private var signInRequired: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Apple-grade Promotional & Educational Hero Card
            VStack(alignment: .leading, spacing: 18) {
                // Header with Gradient Squircle
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color(red: 0.2, green: 0.35, blue: 0.95)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)

                        Image(systemName: "arrow.triangle.2.circlepath.icloud.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cloud Sync & Capture")
                            .font(.system(size: 19, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Optional multi-device power tools")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                // Value Propositions
                VStack(alignment: .leading, spacing: 12) {
                    valuePropRow(
                        icon: "chart.bar.xaxis",
                        iconColor: .blue,
                        title: "Spend Cap Tracking",
                        subtitle: "Keep monthly category limits synchronized across all your devices."
                    )

                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        showingShortcutsTutorial = true
                    } label: {
                        valuePropRow(
                            icon: "wallet.pass.fill",
                            iconColor: .purple,
                            title: "Apple Wallet Shortcuts",
                            subtitle: "Instantly capture transactions when you tap your card at payment terminals."
                        )
                    }
                    .buttonStyle(.plain)

                    valuePropRow(
                        icon: "lock.shield.fill",
                        iconColor: .green,
                        title: "Privacy by Design",
                        subtitle: "100% on-device matching. Checkout always works offline without an account."
                    )
                }
                .padding(.vertical, 4)

                // Action Button
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    authIsPresented = true
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "person.crop.circle.fill")
                        Text("Sign In with PickMe")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Spacer()
                    }
                    .padding(.vertical, 14)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
                    .shadow(color: Color.blue.opacity(0.25), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
            )

            // Live On-Device Status
            nativeCaptureStatusSection
        }
    }

    private func valuePropRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
            }
        }
    }

    // MARK: - Preparing Account

    private var preparingAccount: some View {
        HStack(spacing: 14) {
            ProgressView()
                .controlSize(.regular)

            VStack(alignment: .leading, spacing: 3) {
                Text("Loading Account Wallet…")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("PickMe isolates account wallets on this iPhone.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Account Unavailable

    private var accountUnavailable: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.exclamationmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.orange)
                Text("Wallet Not Loaded")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
            }

            Text(sync.syncIssue?.message ?? "PickMe could not safely load this account's wallet.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Button {
                Task { await onSync() }
            } label: {
                Text("Retry Loading")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 2)
        )
    }

    // MARK: - Connected Content

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 1. Cloud Sync Hero Card
            cloudSyncHeroCard

            // 2. Installation & Shortcuts Credential Section
            installationSection

            // 3. Native Wallet Capture Dashboard
            nativeCaptureStatusSection

            // 4. Recent Capture Feedback Receipts
            if !sync.walletFeedback.isEmpty {
                feedbackSection
            }
        }
        .task { await onSync() }
    }

    private var cloudSyncHeroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color(red: 0.15, green: 0.45, blue: 0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 42, height: 42)
                        .shadow(color: Color.blue.opacity(0.25), radius: 5, x: 0, y: 2)

                    Image(systemName: "checkmark.icloud.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Cloud Sync Engine")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text(sync.lastSyncedAt.map { "Caps updated \($0.formatted(date: .abbreviated, time: .shortened))" }
                         ?? "Stored cap data remains active until sync completes")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    Task { await onSync() }
                } label: {
                    HStack(spacing: 5) {
                        if sync.isSyncing {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        }
                        Text(sync.isSyncing ? "Syncing…" : "Sync Now")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.blue, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(sync.isSyncing)
            }

            if sync.hasPendingWalletChanges(forUserID: ClerkSession.currentUserID) {
                Label("Wallet changes saved on this iPhone are waiting to upload", systemImage: "tray.and.arrow.up.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let syncIssue = sync.syncIssue {
                HStack(spacing: 8) {
                    Image(systemName: syncIssue.kind == .warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(syncIssue.kind == .warning ? .orange : .red)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(syncIssue.message)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(syncIssue.kind == .warning ? .orange : .red)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Last attempt \(syncIssue.occurredAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    (syncIssue.kind == .warning ? Color.orange : Color.red).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }

    private var nativeCaptureStatusSection: some View {
        CaptureStatusView(
            boundAccountLabel: boundAccountLabel,
            canAssignUnassigned: isCaptureBoundToCurrentAccount,
            onRetry: { await onSync() },
            onTestConnection: {
                let result = await sync.testWalletCaptureConnection()
                if result.isConnected { connectionNotice = nil }
                return result
            },
            onAssignUnassigned: { try await sync.assignUnassignedCaptures() },
            onDeleteUnassigned: { try await sync.deleteUnassignedCaptures() },
            onDisable: { delete in try await sync.disableWalletCapture(deleteUnsent: delete) },
            onEnable: { await sync.enableWalletCapture() },
            onSubmitDiagnostic: { report in try await sync.submitDiagnostic(report) },
            onDeleteSubmittedDiagnostic: { id in try await sync.deleteSubmittedDiagnostic(id: id) },
            onListSubmittedDiagnostics: { try await sync.listSubmittedDiagnostics() }
        )
    }

    // MARK: - Installation Section

    private var installationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.purple)
                Text("DEVICE CREDENTIAL")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.8)
            }

            if sync.isSyncing && activeInstallations.isEmpty && !hasLocalCredential {
                ProgressView("Checking active credentials…")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else if sync.syncIssue != nil && activeInstallations.isEmpty && !hasLocalCredential {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Could not verify active credentials. Retry sync before creating a new token.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("Retry Token Check") { Task { await onSync() } }
                        .font(.caption.weight(.bold))
                }
            } else if hasLocalCredential && isCaptureBoundToCurrentAccount && !isShowingCreateForm {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))
                            .font(.system(size: 16))

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Connection Active on This iPhone")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text("Device secret secured in Keychain")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            showingShortcutsTutorial = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "book.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Tutorial")
                            }
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Link(destination: URL(string: "shortcuts://")!) {
                            HStack(spacing: 3) {
                                Text("Shortcuts")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color.purple.opacity(0.12), in: Capsule())
                        }
                    }

                    if !otherActiveInstallations.isEmpty {
                        Divider().padding(.top, 4)
                        DisclosureGroup("Other Active Connections (\(otherActiveInstallations.count))") {
                            installationRows(otherActiveInstallations, allowRevocation: true)
                                .padding(.top, 6)
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if (hasLocalCredential || !activeInstallations.isEmpty) && !isShowingCreateForm {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: hasLocalCredential ? "person.crop.circle.badge.exclamationmark" : "icloud")
                            .foregroundStyle(hasLocalCredential ? .orange : .secondary)
                            .font(.system(size: 16))

                        Text(hasLocalCredential ? "Relink This iPhone" : "Old Server Connections Found")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                    }

                    Text(!hasLocalCredential
                         ? "These records cannot restore secrets after reinstall. Create a replacement connection; saved taps remain on this iPhone."
                         : "The device credential belongs to another PickMe account. Creating a connection here replaces it safely.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    installationRows(activeInstallations, allowRevocation: false)

                    Button {
                        withAnimation(.spring(response: 0.3)) { isShowingCreateForm = true }
                    } label: {
                        Text(hasLocalCredential ? "Relink to This Account" : "Create Replacement Connection")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.blue, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Installation Name (e.g. My iPhone)", text: $installationName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 14))

                    HStack(spacing: 8) {
                        Button {
                            Task { await createInstallationToken() }
                        } label: {
                            HStack(spacing: 5) {
                                if isCreatingToken {
                                    ProgressView().controlSize(.mini).tint(.white)
                                }
                                Text(isCreatingToken ? "Connecting…" : "Connect Wallet Capture")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.blue, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isCreatingToken || sync.isSyncing || installationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if !activeInstallations.isEmpty {
                            Button("Cancel") {
                                withAnimation { isShowingCreateForm = false }
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                        }
                    }
                }
            }

            if let tokenError {
                Text(tokenError).font(.caption).foregroundStyle(.red)
            }
            if let connectionNotice {
                Text(connectionNotice).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }

    private func createInstallationToken() async {
        isCreatingToken = true
        tokenError = nil
        connectionNotice = nil
        defer { isCreatingToken = false }
        do {
            let result = try await sync.createInstallation(label: installationName)
            installationWasCreated = true
            isShowingCreateForm = false
            installationName = "My iPhone"
            if !result.isConnected {
                connectionNotice = "Connection saved, but test failed: \(result.failureReason ?? "Try the connection test below.")"
            }
        } catch {
            #if DEBUG
            print("❌ createInstallationToken error: \(error)")
            #endif
            tokenError = error.localizedDescription
        }
    }

    @ViewBuilder
    private func installationRows(_ values: [WalletInstallation], allowRevocation: Bool) -> some View {
        ForEach(values) { item in
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    Text("Created \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if allowRevocation {
                    Button("Revoke", role: .destructive) {
                        pendingRevocation = item
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
                }
            }
            if item.id != values.last?.id {
                Divider()
            }
        }
    }

    private func revokeInstallation(_ item: WalletInstallation) async {
        pendingRevocation = nil
        do {
            try await sync.revokeWalletInstallation(id: item.id)
            tokenError = nil
        } catch {
            tokenError = error.localizedDescription
        }
    }

    // MARK: - Recent Capture Feedback Section (Apple Pay Style)

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.blue)
                    Text("RECENT CAPTURE FEEDBACK")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .tracking(0.8)
                }

                Spacer()

                Text("\(sync.walletFeedback.count) recorded")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                let items = Array(sync.walletFeedback.prefix(5))
                ForEach(items) { item in
                    feedbackRow(for: item)
                    if item.id != items.last?.id {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.tertiarySystemFill))
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
        )
    }

    private func feedbackRow(for item: WalletFeedback) -> some View {
        HStack(spacing: 12) {
            // Receipt / Merchant Squircle
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(feedbackIconColor(for: item).opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: feedbackIconName(for: item))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(feedbackIconColor(for: item))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(displayMerchant(for: item))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer()

                    if let formattedAmount = formattedAmount(for: item) {
                        Text(formattedAmount)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                    }
                }

                HStack(spacing: 6) {
                    feedbackVerdictLabel(for: item)

                    if let cardText = displayCard(for: item) {
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(cardText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(item.capturedAt.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func feedbackVerdictLabel(for item: WalletFeedback) -> some View {
        if let warning = item.warning?.trimmingCharacters(in: .whitespacesAndNewlines), !warning.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                Text(warning)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.orange)
        } else {
            switch item.verdict.lowercased() {
            case "best", "optimal":
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                    Text("Optimal Card")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(Color(red: 0.13, green: 0.77, blue: 0.37))
            case "suboptimal", "better_card_available":
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9))
                    Text("Better Available")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.orange)
            default:
                Text("Captured")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
            }
        }
    }

    private func feedbackIconName(for item: WalletFeedback) -> String {
        if item.warning?.isEmpty == false {
            return "exclamationmark.triangle.fill"
        }
        switch item.verdict.lowercased() {
        case "best", "optimal": return "checkmark.seal.fill"
        case "suboptimal", "better_card_available": return "arrow.triangle.2.circlepath"
        default: return "wallet.pass.fill"
        }
    }

    private func feedbackIconColor(for item: WalletFeedback) -> Color {
        if item.warning?.isEmpty == false {
            return .orange
        }
        switch item.verdict.lowercased() {
        case "best", "optimal": return Color(red: 0.13, green: 0.77, blue: 0.37)
        case "suboptimal", "better_card_available": return .orange
        default: return .blue
        }
    }

    private func displayMerchant(for item: WalletFeedback) -> String {
        if let normalized = item.merchantNormalized?.trimmingCharacters(in: .whitespacesAndNewlines), !normalized.isEmpty {
            return normalized
        }
        if let raw = item.merchantRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw
        }
        return "Wallet Transaction"
    }

    private func formattedAmount(for item: WalletFeedback) -> String? {
        guard let minor = item.amountMinor else { return nil }
        let amount = Double(minor) / 100.0
        let currency = item.currency?.uppercased()
        if let currency, currency != "CAD" {
            return String(format: "$%.2f %@", amount, currency)
        }
        return String(format: "$%.2f", amount)
    }

    private func displayCard(for item: WalletFeedback) -> String? {
        if let cardRaw = item.cardRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !cardRaw.isEmpty {
            return cardRaw
        }
        return nil
    }
}
