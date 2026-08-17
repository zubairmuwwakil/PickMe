import SwiftUI
import ClerkKit
import ClerkKitUI
import CardCopilotStore

/// The account and privacy surface.
///
/// App Review guideline 5.1.1(v) requires account deletion to be findable inside the app rather
/// than through support, so it sits one tap from the main screen under the standard gear, in the
/// last section, where a reviewer looks first. It is shown only while signed in: there is no
/// account to delete otherwise, and checkout never required one.
struct SettingsView: View {
    let isSignedIn: Bool
    let accountEmail: String?
    let lastSyncedAt: Date?
    let ambientEnabled: Bool
    let onOpenSync: () -> Void
    let onOpenAmbient: () -> Void
    let onSignIn: () -> Void
    let onEraseLocalHistory: () -> Void
    let onDeleteAccount: (_ eraseLocalHistory: Bool) async throws -> Void
    let onDone: () -> Void

    @State private var deleteIsPresented = false
    @State private var eraseIsPresented = false
    @State private var didErase = false

    var body: some View {
        List {
            Section("Account") {
                if isSignedIn {
                    LabeledContent("Signed in as", value: accountEmail ?? "your PickMe account")
                    Button("Sync & Wallet Capture", action: onOpenSync)
                    LabeledContent("Last synced",
                                   value: lastSyncedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                } else {
                    Text("Checkout works without an account. Sign in only to sync cap usage and capture feedback.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Sign in to PickMe", action: onSignIn)
                }
            }

            Section("Ambient") {
                Button("Ambient arrival setup", action: onOpenAmbient)
                LabeledContent("Status", value: ambientEnabled ? "On" : "Off")
            }

            // Deliberately NOT gated on being signed in. The prediction log exists whether or not
            // an account does — checkout never required one — so the control that erases it must
            // not be reachable only through account deletion.
            Section {
                Button("Erase This iPhone's History", role: .destructive) { eraseIsPresented = true }
                if didErase {
                    Text("Erased.").font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("This iPhone")
            } footer: {
                Text("Erases your prediction log, your confirmations, and saved merchant locations from this iPhone. Your account and anything already synced to PickMe are not affected.")
            }

            if isSignedIn {
                Section {
                    Button("Delete Account", role: .destructive) { deleteIsPresented = true }
                } header: {
                    Text("Danger zone")
                } footer: {
                    Text("Deletes your PickMe account and everything stored for it on the server. You choose separately what happens to this iPhone's history.")
                }
            }
        }
        .confirmationDialog("Erase this iPhone's history?", isPresented: $eraseIsPresented,
                            titleVisibility: .visible) {
            Button("Erase History", role: .destructive) {
                onEraseLocalHistory()
                didErase = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your prediction log, confirmations, and saved merchant locations are deleted from this iPhone. This cannot be undone. Your account is not affected.")
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone).font(.headline) } }
        .sheet(isPresented: $deleteIsPresented) {
            NavigationStack {
                DeleteAccountView(accountEmail: accountEmail,
                                  onDelete: onDeleteAccount,
                                  onCancel: { deleteIsPresented = false })
            }
        }
    }
}

/// Step one of two. This screen states the consequences and takes the local-data decision; the
/// irreversible action itself needs a second, separate confirmation below it. Nothing here calls
/// the server — a user who opened this screen by accident can leave with nothing changed.
struct DeleteAccountView: View {
    let accountEmail: String?
    let onDelete: (_ eraseLocalHistory: Bool) async throws -> Void
    let onCancel: () -> Void

    /// Keep-or-erase, not a toggle with a quiet default. The local log is the owner's own record
    /// of what the app advised and what actually happened; it never left the phone, so account
    /// deletion has no claim on it either way. Defaulting to Keep means an accidental deletion
    /// loses the account, never the evidence.
    enum LocalHistoryChoice: String, CaseIterable, Identifiable {
        case keep = "Keep"
        case erase = "Erase"
        var id: String { rawValue }
    }

    @State private var localHistory: LocalHistoryChoice = .keep
    @State private var confirmationIsPresented = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Delete your PickMe account").font(.title2.weight(.bold))
                    if let accountEmail {
                        Text(accountEmail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("What this deletes").font(.headline)
                    consequence("Everything PickMe stores for you on the server: captured wallet events, cap usage, your saved card setup, and the account record itself.")
                    consequence("Your PickMe sign-in. You will not be able to sign in again, here or on the web.")
                    consequence("Any Wallet Shortcut tokens you created. They stop working immediately.")
                    consequence("This cannot be undone, and it cannot be restored for you.")
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 10) {
                    Text("This iPhone's history").font(.headline)
                    Text("Your prediction log, your confirmations, and saved merchant locations are stored only on this iPhone — they were never uploaded, so deleting your account does not touch them. Choose what happens to them.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Picker("This iPhone's history", selection: $localHistory) {
                        ForEach(LocalHistoryChoice.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(localHistory == .keep
                         ? "Kept. Checkout keeps working offline with your history intact."
                         : "Erased from this iPhone along with the account. This cannot be undone either.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }

                Button(role: .destructive) {
                    confirmationIsPresented = true
                } label: {
                    Text(isDeleting ? "Deleting…" : "Delete Account")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(isDeleting)
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Delete Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onCancel).disabled(isDeleting) } }
        // Step two. Separate surface, separate tap, and the destructive verb repeated.
        .confirmationDialog("Delete your PickMe account permanently?",
                            isPresented: $confirmationIsPresented, titleVisibility: .visible) {
            Button(localHistory == .erase ? "Delete Account and Erase History" : "Delete Account",
                   role: .destructive) {
                Task { await performDeletion() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(localHistory == .erase
                 ? "Your account, your server data, and this iPhone's history will be deleted. This cannot be undone."
                 : "Your account and your server data will be deleted. This iPhone's history is kept. This cannot be undone.")
        }
    }

    private func consequence(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "minus.circle.fill").foregroundStyle(.red).font(.footnote)
            Text(text).font(.subheadline)
        }
    }

    private func performDeletion() async {
        isDeleting = true
        errorMessage = nil
        do {
            try await onDelete(localHistory == .erase)
        } catch {
            // Nothing local is touched unless the server confirmed the deletion, so the account
            // and this iPhone are both exactly as they were.
            isDeleting = false
            errorMessage = "Couldn't delete your account. Nothing was changed — your account and this iPhone's history are as they were. (\(error.localizedDescription))"
        }
    }
}
