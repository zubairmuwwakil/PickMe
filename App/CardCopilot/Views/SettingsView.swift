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
    let syncIssue: SyncStatusIssue?
    let ambientEnabled: Bool
    let onOpenSync: () -> Void
    let onOpenAmbient: () -> Void
    let onOpenLearnedMerchants: () -> Void
    let onOpenBenefits: () -> Void
    let onEditWallet: () -> Void
    let onSignIn: () -> Void
    let onSignOut: () -> Void
    let onEraseLocalHistory: () -> Void
    let onDeleteAccount: (_ eraseLocalHistory: Bool) async throws -> Void
    let onDone: () -> Void

    @State private var deleteIsPresented = false
    @State private var eraseIsPresented = false
    @State private var signOutIsPresented = false
    @State private var didErase = false
    /// Snapshotted rather than observed: these counters change while the owner is out shopping,
    /// not while this screen is open, and a live binding would only add churn.
    @State private var categoryMetrics = CategoryResolutionMetrics()

    /// "3 (12%)" — the count on its own says nothing without the denominator, and the share on its
    /// own hides how little data it is drawn from.
    private static func countAndShare(_ count: Int, of total: Int) -> String {
        guard total > 0 else { return "\(count)" }
        return "\(count) (\(Int((Double(count) / Double(total) * 100).rounded()))%)"
    }

    #if FIELD_DIAGNOSTICS
    /// `MerchantIdentity.MatchRung` raw values, said in words. Not localized, unlike the owner
    /// copy above it: these are instrumentation labels for whoever is reading the measurement, and
    /// registering four developer strings would put them in the catalogue an owner's language is
    /// drawn from and into every translator's queue.
    private static func identityRungLabel(_ rawValue: String) -> String {
        switch rawValue {
        case "placeID": return "Apple place id"
        case "legacyIdentifier": return "Saved id"
        case "nameAndProximity": return "Same name nearby"
        default: return rawValue
        }
    }
    #endif

    /// The published policy, served without authentication so it resolves for a signed-out
    /// reviewer. Same URL as the one given to App Store Connect; keep the two in step.
    private static let privacyPolicyURL = URL(string: "https://moneytalks.zubairmuwwakil.com/privacy")!

    var body: some View {
        List {
            Section("Account") {
                if isSignedIn {
                    LabeledContent("Signed in as", value: accountEmail ?? "your PickMe account")
                    Button("Sync & Wallet Capture", action: onOpenSync)
                    LabeledContent("Caps updated",
                                   value: lastSyncedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never")
                    if let syncIssue {
                        Label(syncIssue.kind == .warning ? "Last sync needs attention" : "Last sync attempt failed",
                              systemImage: syncIssue.kind == .warning ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                            .font(.footnote)
                            .foregroundStyle(syncIssue.kind == .warning ? Color.orange : Color.red)
                    }
                    Button("Sign Out", role: .destructive) { signOutIsPresented = true }
                } else {
                    Text("Checkout works without an account. Sign in only to sync cap usage and capture feedback.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Sign in to PickMe", action: onSignIn)
                }
            }

            Section("Ambient") {
                Button(ambientEnabled ? "Arrival alerts" : "Ambient arrival setup", action: onOpenAmbient)
                LabeledContent("Status", value: ambientEnabled ? "On" : "Off")
                Button("Learned merchants", action: onOpenLearnedMerchants)
            }

            Section("Wallet") {
                Button("Edit cards and rewards", action: onEditWallet)
                Text("Change your cards, account conditions, default card, switch threshold, or point values.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Protection & Perks") {
                Button("Card benefits & documents", action: onOpenBenefits)
                Text("Review issuer sources, import your own certificates, and keep claim instructions close at hand.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            // Counted on this iPhone and shown here rather than reported anywhere. The numbers
            // exist to answer one question with evidence instead of a hunch: when PickMe cannot
            // name what a purchase was, is that because it has never heard of the shop, or
            // because it was never given a location to look one up with? Those need opposite
            // fixes, and guessing between them is how a merchant-database import came to look
            // like the obvious answer.
            Section {
                if categoryMetrics.totalResolutions == 0 {
                    Text("Nothing recorded yet.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    LabeledContent("Purchases seen", value: "\(categoryMetrics.totalResolutions)")
                    LabeledContent("Couldn't be named",
                                   value: Self.countAndShare(categoryMetrics.unresolved,
                                                             of: categoryMetrics.totalResolutions))
                    if categoryMetrics.forkedResolutions > 0 {
                        LabeledContent("Narrowed to more than one",
                                       value: "\(categoryMetrics.forkedResolutions)")
                    }
                }

                if categoryMetrics.walletEnrichmentAttempts > 0
                    || categoryMetrics.walletEnrichmentSkippedWithoutLocation > 0 {
                    LabeledContent("Looked up by location",
                                   value: "\(categoryMetrics.walletEnrichmentMatches) of \(categoryMetrics.walletEnrichmentAttempts)")
                }
                if categoryMetrics.walletEnrichmentSkippedWithoutLocation > 0 {
                    LabeledContent("Arrived with no location",
                                   value: "\(categoryMetrics.walletEnrichmentSkippedWithoutLocation)")
                }
            } header: {
                Text("Category diagnostics")
            } footer: {
                Text("How often PickMe could name what a purchase was. Counted on this iPhone only — no merchant, amount, or place is recorded here, and none of it is sent anywhere. Erasing this iPhone's history clears these too.")
            }

            // Separated from the section above, deliberately. Every row up there answers something
            // the owner can hold — could PickMe name my purchases, and if not, why not — and the
            // footer's privacy promise is credible because a reader can check it against rows they
            // understand. Which rung of the identity ladder answered is a question about Apple's
            // place data and this app's migration, not about the owner's money. Putting it up
            // there would spend their attention on a number they cannot act on and dilute the one
            // property that section has.
            //
            // `FIELD_DIAGNOSTICS` is this app's instrumentation switch and is deliberately active
            // in Release as well as Debug for the current measurement window — verified with
            // `xcodebuild -showBuildSettings`, not assumed from the name. So this is NOT invisible
            // to a TestFlight build, and that is the point: the numbers only accrue where real
            // shopping happens. It does mean the switch is the single lever to flip before an App
            // Store submission, for this section and for every other `FIELD_DIAGNOSTICS` surface.
            //
            // It shares `CategoryResolutionMetricsStore` rather than opening a store of its own:
            // resolution happens in the app, in the Wallet Capture intent, and on a geofence wake,
            // and a fifth counter file split across three processes would answer nothing.
            #if FIELD_DIAGNOSTICS
            if categoryMetrics.totalIdentityLookups > 0 {
                Section {
                    LabeledContent("Merchants looked up",
                                   value: "\(categoryMetrics.totalIdentityLookups)")
                    ForEach(categoryMetrics.identityMatchesByRung.sorted(by: { $0.key < $1.key }),
                            id: \.key) { rung, count in
                        LabeledContent(Self.identityRungLabel(rung), value: "\(count)")
                    }
                    if categoryMetrics.identityMisses > 0 {
                        LabeledContent("Not recognised",
                                       value: "\(categoryMetrics.identityMisses)")
                    }
                } header: {
                    Text("Merchant identity (instrumentation)")
                } footer: {
                    Text("Which rung recognised a merchant already on this iPhone. \"Apple place id\" is the stable one; \"saved id\" is a row written before place ids and not yet re-seen; \"same name nearby\" means the pin moved and proximity rescued it. A rising share of the last two says recognition is drifting.")
                }
            }
            #endif

            // Ahead of the destructive sections so Danger zone stays last for App Review, and
            // outside the isSignedIn branch: the policy describes the on-device store too, which
            // exists whether or not an account does.
            Section {
                Link("Privacy Policy", destination: Self.privacyPolicyURL)
            } header: {
                Text("About")
            } footer: {
                Text("What PickMe keeps on this iPhone, what reaches the server if you have an account, and how to delete either.")
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
        .confirmationDialog("Sign out of In Unity?", isPresented: $signOutIsPresented,
                            titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) {
                onSignOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Signing out stops cap and feedback sync. Checkout will continue to work offline with your on-device history.")
        }
        .confirmationDialog("Erase this iPhone's history?", isPresented: $eraseIsPresented,
                            titleVisibility: .visible) {
            Button("Erase History", role: .destructive) {
                onEraseLocalHistory()
                didErase = true
                // The eraser clears the counters; re-read so the section does not keep showing
                // totals for history the owner just deleted.
                categoryMetrics = CategoryResolutionMetricsStore().snapshot
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your prediction log, confirmations, and saved merchant locations are deleted from this iPhone. This cannot be undone. Your account is not affected.")
        }
        .onAppear { categoryMetrics = CategoryResolutionMetricsStore().snapshot }
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
                    Text("Delete your In Unity account").font(.title2.weight(.bold))
                    if let accountEmail {
                        Text(accountEmail).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("What this deletes").font(.headline)
                    consequence("Everything In Unity stores for you on the server: captured wallet events, cap usage, your saved card setup, and the account record itself.")
                    consequence("Your In Unity sign-in. You will not be able to sign in again, here or on the web.")
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
        .confirmationDialog("Delete your In Unity account permanently?",
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
