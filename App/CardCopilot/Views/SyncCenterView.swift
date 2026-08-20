import SwiftUI
import ClerkKitUI
import CardCopilotStore

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
    let onDone: () -> Void

    @State private var authIsPresented = false
    @State private var installationName = "My iPhone"
    @State private var installationToken: String?
    @State private var tokenError: String?
    @State private var isCreatingToken = false
    @State private var isShowingCreateForm = false

    private var activeInstallations: [WalletInstallation] {
        installations.filter { $0.revokedAt == nil }
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
            Label("Keep your caps in sync", systemImage: "arrow.triangle.2.circlepath").font(.title3.weight(.bold))
            Text("Sign in only to sync cap usage, view capture feedback, and create a Wallet Shortcut installation token. Checkout recommendations work without an account or connection.").foregroundStyle(.secondary)
            Button("Sign in to Inunity") { authIsPresented = true }.buttonStyle(.borderedProminent)
        }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
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
            if !feedback.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent capture feedback").font(.headline)
                    ForEach(feedback.prefix(5)) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.warning ?? item.verdict.capitalized).font(.subheadline.weight(.semibold))
                            Text(item.merchantRaw ?? "Unknown merchant").font(.footnote).foregroundStyle(.secondary)
                        }
                        if item.id != feedback.prefix(5).last?.id { Divider() }
                    }
                }.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            }
        }.task { onSync() }
    }

    private var installationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Wallet Shortcut token", systemImage: "wallet.pass").font(.headline)
            Text("Create one token for this device, copy it once, then paste it into the shared Wallet Capture Shortcut. The Shortcut’s assembly contract is in MoneyTalks/docs/plans/2026-08-16-wallet-capture-spec.md.").font(.footnote).foregroundStyle(.secondary)
            if isSyncing && activeInstallations.isEmpty && installationToken == nil {
                ProgressView("Checking connected tokens…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else if syncIssue != nil && activeInstallations.isEmpty && installationToken == nil {
                Text("PickMe could not verify whether this account already has a token. Retry sync before creating another one.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Retry token check", action: onSync).buttonStyle(.bordered)
            } else if let installationToken {
                Text(installationToken).font(.footnote.monospaced()).textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                Button("Copy token") { UIPasteboard.general.string = installationToken }.buttonStyle(.bordered)
                Text("This is the only time PickMe displays this token. Store it in the Shortcut, not a note.").font(.caption).foregroundStyle(.secondary)
            } else if !activeInstallations.isEmpty && !isShowingCreateForm {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                    ForEach(activeInstallations) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.label).font(.subheadline.weight(.semibold))
                            Text("Created \(item.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if item.id != activeInstallations.last?.id { Divider() }
                    }
                    Button("Create another token") {
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
                    Button(isCreatingToken ? "Creating…" : "Create installation token") { Task { await createInstallationToken() } }
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
            installationToken = try await onCreateInstallation(installationName)
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
