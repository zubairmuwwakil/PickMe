import SwiftUI
import ClerkKitUI
import CardCopilotStore
import CardCopilotCapture

/// Optional account and capture setup; checkout itself remains entirely offline-capable.
struct SyncCenterView: View {
    let isSignedIn: Bool
    let lastSyncedAt: Date?
    let feedback: [WalletFeedback]
    let installations: [WalletInstallation]
    let syncIssue: SyncStatusIssue?
    let isSyncing: Bool
    let isPreparingAccount: Bool
    let isAccountReady: Bool
    let onSync: () -> Void
    let onCreateInstallation: (String) async throws -> String
    let boundAccountLabel: String?
    let isCaptureBoundToCurrentAccount: Bool
    let onTestCaptureConnection: () async -> Bool
    let onAssignUnassigned: () async throws -> Void
    let onDeleteUnassigned: () async throws -> Void
    let onDisableCapture: (Bool) async throws -> Void
    let onSubmitDiagnostic: (WalletCaptureDiagnosticReport) async throws -> WalletSubmittedDiagnostic
    let onDeleteSubmittedDiagnostic: (String) async throws -> Void
    let onListSubmittedDiagnostics: () async throws -> [WalletSubmittedDiagnostic]
    let onDone: () -> Void

    @State private var authIsPresented = false
    @State private var installationName = "My iPhone"
    @State private var installationWasCreated = false
    @State private var tokenError: String?
    @State private var isCreatingToken = false
    @State private var isShowingCreateForm = false

    private var activeInstallations: [WalletInstallation] {
        installations.filter { $0.revokedAt == nil }
    }

    private var hasLocalCredential: Bool {
        installationWasCreated || WalletCaptureCredentialStore().load() != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !MoneyTalksConfiguration.isConfigured { configurationRequired }
                else if !isSignedIn { signInRequired }
                else if isPreparingAccount { preparingAccount }
                else if !isAccountReady { accountUnavailable }
                else { connectedContent }
            }.padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sync & Capture")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone).font(.headline) } }
        .sheet(isPresented: $authIsPresented) { AuthView() }
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
            Text(syncIssue?.message ?? "PickMe could not safely load this account's wallet.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Retry", action: onSync).buttonStyle(.borderedProminent)
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Sync", systemImage: "checkmark.icloud").font(.title3.weight(.bold))
                Text(lastSyncedAt.map { "Last synced \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Not synced yet — stored cap data remains in use until a sync succeeds.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let syncIssue {
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
                Button(isSyncing ? "Syncing…" : "Sync now", action: onSync).buttonStyle(.borderedProminent).disabled(isSyncing)
            }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            installationSection
            nativeCaptureStatusSection
            if !feedback.isEmpty {
                feedbackSection
            }
        }.task { onSync() }
    }

    private var nativeCaptureStatusSection: some View {
        CaptureStatusView(boundAccountLabel: boundAccountLabel,
            canAssignUnassigned: isCaptureBoundToCurrentAccount,
            onRetry: { onSync() }, onTestConnection: onTestCaptureConnection,
            onAssignUnassigned: onAssignUnassigned, onDeleteUnassigned: onDeleteUnassigned,
            onDisable: onDisableCapture, onSubmitDiagnostic: onSubmitDiagnostic,
            onDeleteSubmittedDiagnostic: onDeleteSubmittedDiagnostic,
            onListSubmittedDiagnostics: onListSubmittedDiagnostics)
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent capture feedback").font(.headline)
            ForEach(feedback.prefix(5)) { item in
                feedbackRow(for: item)
                if item.id != feedback.prefix(5).last?.id {
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
            if isSyncing && activeInstallations.isEmpty && !hasLocalCredential {
                ProgressView("Checking connected tokens…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else if syncIssue != nil && activeInstallations.isEmpty && !hasLocalCredential {
                Text("PickMe could not verify whether this account already has a token. Retry sync before creating another one.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Retry token check", action: onSync).buttonStyle(.bordered)
            } else if hasLocalCredential && isCaptureBoundToCurrentAccount && !isShowingCreateForm {
                Label("Connected securely", systemImage: "checkmark.shield.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.green)
                Text("The write-only installation credential is protected on this iPhone. It is not copied into Shortcuts or displayed on screen.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Open Shortcuts", destination: URL(string: "shortcuts://")!).buttonStyle(.bordered)
            } else if (hasLocalCredential || !activeInstallations.isEmpty) && !isShowingCreateForm {
                VStack(alignment: .leading, spacing: 10) {
                    Label(hasLocalCredential ? "Relink this iPhone" : "Server connection found",
                          systemImage: hasLocalCredential ? "person.crop.circle.badge.exclamationmark" : "icloud")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(hasLocalCredential ? .orange : .secondary)
                    Text(!hasLocalCredential
                         ? "A server installation exists, but this app needs a fresh device-only credential before it can send captures."
                         : "The device credential belongs to another Inunity account. Creating a connection here replaces it safely.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(activeInstallations) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label).font(.subheadline.weight(.semibold))
                            Text("Created \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if item.id != activeInstallations.last?.id { Divider() }
                    }
                    Button(hasLocalCredential ? "Relink to this account" : "Connect this iPhone") {
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
                        .buttonStyle(.bordered).disabled(isCreatingToken || isSyncing || installationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        }.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func createInstallationToken() async {
        isCreatingToken = true; tokenError = nil
        defer { isCreatingToken = false }
        do {
            _ = try await onCreateInstallation(installationName)
            installationWasCreated = true
            isShowingCreateForm = false
            installationName = "My iPhone"
        }
        catch {
            #if DEBUG
            print("❌ createInstallationToken error: \(error)")
            #endif
            tokenError = error.localizedDescription
        }
    }
}
