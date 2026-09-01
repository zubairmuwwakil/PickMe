import SwiftUI
import ClerkKit
import ClerkKitUI
import CardCopilotEngine
import CardCopilotStore

/// An Apple ID-inspired Account & Security details sheet.
///
/// Gives signed-in users clear insight into their cloud account, linked identity,
/// multi-device sync status, and provides proper Sign Out and Delete Account management
/// in full compliance with App Store Review Guideline 5.1.1(v).
struct AccountDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CopilotSession.self) private var session
    @Environment(CheckoutRouter.self) private var router
    @Environment(SyncCoordinator.self) private var sync
    @Environment(CopilotEnvironment.self) private var environment

    let accountEmail: String?
    let onSignOut: () -> Void
    let onDeleteAccount: (_ eraseLocalHistory: Bool) async throws -> Void

    @State private var signOutIsPresented = false
    @State private var deleteIsPresented = false
    @State private var isSyncingNow = false

    private var userInitials: String {
        guard let email = accountEmail, !email.isEmpty else { return "U" }
        let prefix = email.split(separator: "@").first ?? ""
        let components = prefix.split(separator: ".")
        if components.count >= 2 {
            let first = components[0].prefix(1).uppercased()
            let second = components[1].prefix(1).uppercased()
            return "\(first)\(second)"
        }
        return String(prefix.prefix(2)).uppercased()
    }

    private var clerkUserID: String? {
        ClerkSession.currentUserID
    }

    var body: some View {
        NavigationStack {
            List {
                // Section 1: User Identity Card
                Section {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color(red: 0.2, green: 0.35, blue: 0.95)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)
                                .shadow(color: Color.blue.opacity(0.25), radius: 6, x: 0, y: 3)

                            Text(userInitials)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(accountEmail ?? "PickMe Account")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(red: 0.13, green: 0.77, blue: 0.37))
                                    .frame(width: 8, height: 8)

                                Text("PickMe Cloud Active")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Section 2: Account Details
                Section("Account Details") {
                    if let email = accountEmail {
                        LabeledContent("Email", value: email)
                    }

                    if let userID = clerkUserID {
                        HStack {
                            Text("Account ID")
                            Spacer()
                            Text(String(userID.prefix(12)) + "…")
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    LabeledContent("Sync Security", value: "Encrypted in Transit")
                }

                // Section 3: Cloud Sync Health
                Section("Sync Status") {
                    HStack {
                        Text("Caps Updated")
                        Spacer()
                        if let last = sync.lastSyncedAt {
                            Text(last.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Never")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let issue = sync.syncIssue {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: issue.kind == .error
                                  ? "exclamationmark.icloud.fill"
                                  : "exclamationmark.triangle.fill")
                                .foregroundStyle(issue.kind == .error ? .red : .orange)
                            Text(issue.message)
                                .font(.footnote)
                                .foregroundStyle(issue.kind == .error ? .red : .orange)
                        }
                    }

                    Button {
                        Task {
                            isSyncingNow = true
                            if let graph = environment.graph,
                               let result = await sync.syncCapsSilently(
                                    ownerState: graph.ownerState,
                                    catalogue: graph.catalogue
                               ) {
                                environment.rebuild(ownerState: result.ownerState)
                                if let refreshed = environment.graph {
                                    session.refresh(using: refreshed)
                                }
                            }
                            isSyncingNow = false
                        }
                    } label: {
                        HStack {
                            Text(isSyncingNow ? "Syncing…" : "Sync Now")
                                .foregroundStyle(.blue)
                            Spacer()
                            if isSyncingNow {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(isSyncingNow)
                }

                // Section 4: Account Actions
                Section {
                    Button(role: .destructive) {
                        signOutIsPresented = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Sign Out")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                        }
                    }
                }

                // Section 5: Danger Zone (App Store 5.1.1(v) Compliant)
                Section {
                    Button(role: .destructive) {
                        deleteIsPresented = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Delete PickMe Account")
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                        }
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("Deletes your PickMe cloud account, saved remote cards, and server sync history. Your on-device data remains intact unless you choose to erase it.")
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.headline)
                }
            }
            .confirmationDialog("Sign out of PickMe?", isPresented: $signOutIsPresented, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    dismiss()
                    onSignOut()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Signing out stops cap and feedback sync. Checkout continues to work offline with your on-device history.")
            }
            .sheet(isPresented: $deleteIsPresented) {
                NavigationStack {
                    DeleteAccountView(
                        accountEmail: accountEmail,
                        onDelete: { erase in
                            dismiss()
                            try await onDeleteAccount(erase)
                        },
                        onCancel: { deleteIsPresented = false }
                    )
                }
            }
        }
    }
}
