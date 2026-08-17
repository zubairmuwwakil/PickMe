import SwiftUI
import ClerkKitUI
import CardCopilotStore

/// Optional account and capture setup; checkout itself remains entirely offline-capable.
struct SyncCenterView: View {
    let isSignedIn: Bool
    let lastSyncedAt: Date?
    let feedback: [WalletFeedback]
    let isSyncing: Bool
    let onSync: () -> Void
    let onCreateInstallation: (String) async throws -> String
    let onDone: () -> Void

    @State private var authIsPresented = false
    @State private var installationName = "My iPhone"
    @State private var installationToken: String?
    @State private var tokenError: String?
    @State private var isCreatingToken = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !MoneyTalksConfiguration.isConfigured { configurationRequired }
                else if !isSignedIn { signInRequired }
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
                               description: Text("Checkout stays available. Add the dedicated PickMe Clerk key and API URL to MoneyTalksConfiguration.swift, then return here to sign in."))
    }

    private var signInRequired: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Keep your caps in sync", systemImage: "arrow.triangle.2.circlepath").font(.title3.weight(.bold))
            Text("Sign in only to sync cap usage, view capture feedback, and create a Wallet Shortcut installation token. Checkout recommendations work without an account or connection.").foregroundStyle(.secondary)
            Button("Sign in to PickMe") { authIsPresented = true }.buttonStyle(.borderedProminent)
        }.padding(18).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private var connectedContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Sync", systemImage: "checkmark.icloud").font(.title3.weight(.bold))
                Text(lastSyncedAt.map { "Last synced \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Not synced yet — stored cap data remains in use until a sync succeeds.")
                    .font(.subheadline).foregroundStyle(.secondary)
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
            if let installationToken {
                Text(installationToken).font(.footnote.monospaced()).textSelection(.enabled).padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                Button("Copy token") { UIPasteboard.general.string = installationToken }.buttonStyle(.bordered)
                Text("This is the only time PickMe displays this token. Store it in the Shortcut, not a note.").font(.caption).foregroundStyle(.secondary)
            } else {
                TextField("Installation name", text: $installationName).textFieldStyle(.roundedBorder)
                Button(isCreatingToken ? "Creating…" : "Create installation token") { Task { await createInstallationToken() } }
                    .buttonStyle(.bordered).disabled(isCreatingToken || installationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let tokenError { Text(tokenError).font(.caption).foregroundStyle(.red) }
        }.padding(16).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func createInstallationToken() async {
        isCreatingToken = true; tokenError = nil
        defer { isCreatingToken = false }
        do { installationToken = try await onCreateInstallation(installationName) }
        catch { tokenError = "Couldn’t create a token. Check your connection and try again." }
    }
}
