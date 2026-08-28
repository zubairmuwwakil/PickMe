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
            VStack(alignment: .leading, spacing: 20) {
                if !MoneyTalksConfiguration.isConfigured { configurationRequired }
                else if !isSignedIn { signInRequired }
                else if sync.isPreparingAccount { preparingAccount }
                else if sync.readySyncUserID != Clerk.shared.user?.id { accountUnavailable }
                else { connectedContent }
            }.padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sync & Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: { dismiss() }).font(.headline) } }
        .sheet(isPresented: $authIsPresented) { AuthView() }
        .alert("Revoke this old connection?", isPresented: .init(
            get: { pendingRevocation != nil }, set: { if !$0 { pendingRevocation = nil } }),
            presenting: pendingRevocation) { item in
            Button("Revoke", role: .destructive) { Task { await revokeInstallation(item) } }
            Button("Cancel", role: .cancel) { pendingRevocation = nil }
        } message: { _ in
            Text("Only the selected server credential is revoked. Purchases already saved on this iPhone are not deleted.")
        }
    }

    private var configurationRequired: some View {
        ContentUnavailableView("Sync setup required", systemImage: "key.horizontal",
                               description: Text("Checkout stays available. Add the dedicated Inunity Clerk key and API URL to MoneyTalksConfiguration.swift, then return here to sign in."))
    }

    private var signInRequired: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Keep your caps in sync", systemImage: "arrow.triangle.2.circlepath").font(.title3.weight(.bold))
                Text("Sign in only to sync cap usage, view capture feedback, and create a Wallet Capture connection. Checkout recommendations work without an account or connection.").foregroundStyle(.secondary)
                Button("Sign in to Inunity") { authIsPresented = true }.buttonStyle(.borderedProminent)
            }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            nativeCaptureStatusSection
        }
    }

    private var preparingAccount: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 3) {
                Text("Loading this account's wallet").font(.headline)
                Text("PickMe keeps account wallets separate on this iPhone.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var accountUnavailable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Wallet not loaded", systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.headline)
            Text(sync.syncIssue?.message ?? "PickMe could not safely load this account's wallet.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Retry") { Task { await onSync() } }.buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Sync", systemImage: "checkmark.icloud").font(.title3.weight(.bold))
                Text(sync.lastSyncedAt.map { "Last synced \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Not synced yet — stored cap data remains in use until a sync succeeds.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let syncIssue = sync.syncIssue {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(syncIssue.message)
                            Text("Last attempt \(syncIssue.occurredAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                        }
                    } icon: {
                        Image(systemName: syncIssue.kind == .warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                    }
                    .font(.subheadline)
                    .foregroundStyle(syncIssue.kind == .warning ? .orange : .red)
                }
                Button(sync.isSyncing ? "Syncing…" : "Sync now") { Task { await onSync() } }
                    .buttonStyle(.borderedProminent).disabled(sync.isSyncing)
            }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            installationSection
            nativeCaptureStatusSection
            if !sync.walletFeedback.isEmpty {
                feedbackSection
            }
        }.task { await onSync() }
    }

    private var nativeCaptureStatusSection: some View {
        CaptureStatusView(boundAccountLabel: boundAccountLabel,
            canAssignUnassigned: isCaptureBoundToCurrentAccount,
            onRetry: { await onSync() }, onTestConnection: {
                let result = await sync.testWalletCaptureConnection()
                if result.isConnected { connectionNotice = nil }
                return result
            },
            onAssignUnassigned: { try await sync.assignUnassignedCaptures() },
            onDeleteUnassigned: { try await sync.deleteUnassignedCaptures() },
            onDisable: { delete in try await sync.disableWalletCapture(deleteUnsent: delete) },
            onSubmitDiagnostic: { report in try await sync.submitDiagnostic(report) },
            onDeleteSubmittedDiagnostic: { id in try await sync.deleteSubmittedDiagnostic(id: id) },
            onListSubmittedDiagnostics: { try await sync.listSubmittedDiagnostics() })
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent capture feedback").font(.headline)
            ForEach(sync.walletFeedback.prefix(5)) { item in
                feedbackRow(for: item)
                if item.id != sync.walletFeedback.prefix(5).last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func feedbackRow(for item: WalletFeedback) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                feedbackVerdictLabel(for: item)
                Spacer()
                Text(item.capturedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Text(displayMerchant(for: item))
                    .font(.subheadline.weight(.semibold))

                if let formattedAmount = formattedAmount(for: item) {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(formattedAmount)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let cardText = displayCard(for: item) {
                Text(cardText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func feedbackVerdictLabel(for item: WalletFeedback) -> some View {
        if let warning = item.warning?.trimmingCharacters(in: .whitespacesAndNewlines), !warning.isEmpty {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
        } else {
            switch item.verdict.lowercased() {
            case "best", "optimal":
                Label("Best card used", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            case "suboptimal", "better_card_available":
                Label("Better card available", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            case "unknown":
                Label("Captured", systemImage: "arrow.down.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            default:
                Text(item.verdict.capitalized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private func displayMerchant(for item: WalletFeedback) -> String {
        if let normalized = item.merchantNormalized?.trimmingCharacters(in: .whitespacesAndNewlines), !normalized.isEmpty {
            return normalized
        }
        if let raw = item.merchantRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            return raw
        }
        return "Wallet transaction"
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
            return "Card: \(cardRaw)"
        }
        return nil
    }

    private var installationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Native Wallet Capture", systemImage: "wallet.pass").font(.headline)
            Text("Create one secure connection for this iPhone, then add “Send Wallet Purchase to Inunity” directly to your Wallet Transaction automation and map Merchant, Amount, Name, Currency Code, and Card or Pass. PickMe saves each tap locally before syncing it.").font(.footnote).foregroundStyle(.secondary)
            if sync.isSyncing && activeInstallations.isEmpty && !hasLocalCredential {
                ProgressView("Checking connected tokens…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else if sync.syncIssue != nil && activeInstallations.isEmpty && !hasLocalCredential {
                Text("PickMe could not verify whether this account already has a token. Retry sync before creating another one.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Retry token check") { Task { await onSync() } }.buttonStyle(.bordered)
            } else if hasLocalCredential && isCaptureBoundToCurrentAccount && !isShowingCreateForm {
                Label("Connection saved on this iPhone", systemImage: "lock.shield.fill")
                    .font(.subheadline.weight(.semibold))
                Text("The write-only installation credential is protected on this iPhone. Verification and delivery status appear below.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Open Shortcuts", destination: URL(string: "shortcuts://")!).buttonStyle(.bordered)
                if !otherActiveInstallations.isEmpty {
                    DisclosureGroup("Other active connections (\(otherActiveInstallations.count))") {
                        installationRows(otherActiveInstallations, allowRevocation: true)
                            .padding(.top, 8)
                    }.font(.caption)
                }
            } else if (hasLocalCredential || !activeInstallations.isEmpty) && !isShowingCreateForm {
                VStack(alignment: .leading, spacing: 10) {
                    Label(hasLocalCredential ? "Relink this iPhone" : "Old server connections found",
                          systemImage: hasLocalCredential ? "person.crop.circle.badge.exclamationmark" : "icloud")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(hasLocalCredential ? .orange : .secondary)
                    Text(!hasLocalCredential
                         ? "These records cannot restore their device-only secrets after a reinstall. Create a replacement connection; saved purchases stay on this iPhone until you approve their account."
                         : "The device credential belongs to another Inunity account. Creating a connection here replaces it safely.")
                        .font(.caption).foregroundStyle(.secondary)
                    installationRows(activeInstallations, allowRevocation: false)
                    Button(hasLocalCredential ? "Relink to this account" : "Create replacement connection") {
                        withAnimation { isShowingCreateForm = true }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            } else {
                TextField("Installation name", text: $installationName).textFieldStyle(.roundedBorder)
                HStack {
                    Button(isCreatingToken ? "Connecting…" : "Connect native Wallet Capture") { Task { await createInstallationToken() } }
                        .buttonStyle(.bordered).disabled(isCreatingToken || sync.isSyncing || installationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if !activeInstallations.isEmpty {
                        Button("Cancel") {
                            withAnimation { isShowingCreateForm = false }
                        }
                        .buttonStyle(.borderless)
                        .padding(.leading, 8)
                    }
                }
            }
            if let tokenError { Text(tokenError).font(.caption).foregroundStyle(.red) }
            if let connectionNotice { Text(connectionNotice).font(.caption).foregroundStyle(.orange) }
        }.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func createInstallationToken() async {
        isCreatingToken = true; tokenError = nil; connectionNotice = nil
        defer { isCreatingToken = false }
        do {
            let result = try await sync.createInstallation(label: installationName)
            installationWasCreated = true
            isShowingCreateForm = false
            installationName = "My iPhone"
            if !result.isConnected {
                connectionNotice = "Connection saved, but verification failed. \(result.failureReason ?? "Try the secure connection test again.")"
            }
        }
        catch {
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
                    Text(item.label).font(.subheadline.weight(.semibold))
                    Text("Created \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if allowRevocation {
                    Button("Revoke", role: .destructive) { pendingRevocation = item }
                        .font(.caption).buttonStyle(.borderless)
                }
            }
            if item.id != values.last?.id { Divider() }
        }
    }

    private func revokeInstallation(_ item: WalletInstallation) async {
        pendingRevocation = nil
        do { try await sync.revokeWalletInstallation(id: item.id); tokenError = nil }
        catch { tokenError = error.localizedDescription }
    }
}
