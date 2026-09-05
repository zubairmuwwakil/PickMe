import CardCopilotCapture
import CardCopilotStore
import SwiftUI

struct TesterReportView: View {
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var area = "other"
    @State private var expected = ""
    @State private var actual = ""
    @State private var steps = ""
    @State private var includeCounters = false
    @State private var includeWallet = false
    @State private var includeArrival = false
    @State private var walletRecords: [WalletCaptureDiagnosticRecord] = []
    @State private var walletEventID = ""
    @State private var prepared: TesterReport?
    @State private var reportURL: URL?
    @State private var preview = ""
    @State private var submitted: SubmittedTesterReport?
    @State private var previousReports: [SubmittedTesterReport] = []
    @State private var pendingDelete: SubmittedTesterReport?
    @State private var message: String?
    @State private var working = false

    private let areas = [("other", "Something else"), ("checkout", "Checkout recommendation"),
                         ("walletCapture", "Wallet Capture"), ("arrivals", "Arrival alerts"),
                         ("wallet", "Wallet setup"), ("benefits", "Benefits"), ("sync", "Sync or sign-in")]

    var body: some View {
        Form {
            if prepared == nil {
                Section {
                    Picker("Where did it happen?", selection: $area) {
                        ForEach(areas, id: \.0) { value, label in Text(label).tag(value) }
                    }
                    TextField("What did you expect?", text: $expected, axis: .vertical)
                        .lineLimit(2...5).accessibilityIdentifier("reportExpected")
                    TextField("What actually happened?", text: $actual, axis: .vertical)
                        .lineLimit(2...5).accessibilityIdentifier("reportActual")
                    TextField("Steps to reproduce (optional)", text: $steps, axis: .vertical)
                        .lineLimit(2...6)
                } header: { Text("Describe the problem") }
                footer: { Text("Include the approximate time if relevant. Do not enter card numbers, passwords or other secrets. Each answer can contain up to 4,000 characters.") }

                Section {
                    Toggle("Include category diagnostic counts", isOn: $includeCounters)
                    if !walletRecords.isEmpty {
                        Toggle("Include a Wallet Capture diagnostic", isOn: $includeWallet)
                        if includeWallet {
                            Picker("Capture event", selection: $walletEventID) {
                                ForEach(walletRecords) { record in
                                    Text("\(record.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(record.deliveryState.rawValue)")
                                        .tag(record.eventID)
                                }
                            }
                            Text("Includes delivery stages and errors. Merchant, amount, card and coordinates are excluded.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    #if FIELD_DIAGNOSTICS
                    Toggle("Include detailed arrival log", isOn: $includeArrival)
                    if includeArrival {
                        Text("This log includes precise locations, merchant names, candidate cards and arrival times from recent visits. Only include it if you want the reviewer to see those details.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    #endif
                } header: { Text("Optional evidence") }
                footer: { Text("App, build, iOS and catalogue versions are included automatically. You can review the complete report before sending or sharing it.") }

                Button("Preview report") { Task { await prepare() } }
                    .disabled(working || !validDescription)
                    .accessibilityIdentifier("previewTesterReport")
            } else {
                Section("Review before sharing") {
                    Text(preview).font(.caption.monospaced()).textSelection(.enabled)
                }
                Section {
                    if let submitted {
                        Label("Report received", systemImage: "checkmark.circle")
                        Text("Reference: \(submitted.id)").textSelection(.enabled)
                        Text("Expires \(submitted.expiresAt.formatted(date: .abbreviated, time: .omitted)). Review progress appears below.")
                            .font(.caption)
                    } else if ClerkSession.isSignedIn {
                        Button("Send report") { Task { await send() } }.disabled(working)
                            .accessibilityIdentifier("sendTesterReport")
                    }
                    if let reportURL {
                        ShareLink(item: reportURL) { Label("Share report file", systemImage: "square.and.arrow.up") }
                    }
                    if !ClerkSession.isSignedIn {
                        Text("Share this file privately with the person who invited you to test PickMe. You can also save it to Files and send it later. Preparing or sharing a file does not submit it to the review inbox.")
                            .font(.caption)
                    }
                    Button(submitted == nil ? "Edit report" : "Start another report") {
                        prepared = nil; reportURL = nil; submitted = nil; message = nil
                    }.disabled(working)
                } footer: {
                    Text("Reports sent to In Unity are available to authorized reviewers for 30 days. You can delete a sent report below. Copies shared through other apps must be deleted there separately.")
                }
            }
            if let message { Section { Text(message).font(.callout).accessibilityIdentifier("testerReportMessage") } }
            if working { ProgressView("Working…") }
            if ClerkSession.isSignedIn {
                Section("Your submitted reports") {
                    Button("Refresh review status") { Task { await refreshReports() } }.disabled(working)
                    if previousReports.isEmpty { Text("No submitted reports loaded.").foregroundStyle(.secondary) }
                    ForEach(previousReports) { report in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(report.clientReportId ?? report.id).font(.caption.monospaced()).textSelection(.enabled)
                            Text((report.status ?? "new").replacingOccurrences(of: "-", with: " "))
                            if let build = report.resolvedInBuild, !build.isEmpty { Text("Fixed in \(build)") }
                            Button("Delete submitted report", role: .destructive) { pendingDelete = report }.disabled(working)
                        }
                    }
                }
            }
        }
        .navigationTitle("Report a problem")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(working) } }
        .task {
            do {
                let records = try await diagnosticStore().records()
                walletRecords = records; walletEventID = records.first?.eventID ?? ""
            } catch { message = "Wallet diagnostics could not be loaded. You can still describe and report the problem." }
        }
        .task(id: ClerkSession.currentUserID) {
            previousReports = []; submitted = nil
            if ClerkSession.isSignedIn { await refreshReports() }
        }
        .confirmationDialog("Delete this submitted report?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete report", role: .destructive) {
                if let report = pendingDelete { Task { await delete(report) } }
            }
        } message: { Text("Removes its evidence and review notes from the server. Copies you shared elsewhere are unaffected.") }
    }

    private var validDescription: Bool {
        !expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !actual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && expected.utf16.count <= 4000 && actual.utf16.count <= 4000 && steps.utf16.count <= 4000
    }

    private func diagnosticStore() throws -> WalletCaptureDiagnosticsStore {
        let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.ca.inunity.pickme")
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return try WalletCaptureDiagnosticsStore(root: root)
    }

    private func prepare() async {
        working = true; message = nil
        defer { working = false }
        do {
            let wallet = includeWallet ? try await diagnosticStore().prepareReport(eventID: walletEventID, includeTransactionDetails: false) : nil
            var arrival: String?
            #if FIELD_DIAGNOSTICS
            if includeArrival {
                guard let url = environment.exportAmbientFieldLog() else {
                    message = "The arrival log could not be prepared. Turn off that attachment and try again."; return
                }
                arrival = try String(contentsOf: url, encoding: .utf8)
            }
            #endif
            let metrics = CategoryResolutionMetricsStore().snapshot
            let counters = includeCounters ? ["purchasesSeen": metrics.totalResolutions, "unresolved": metrics.unresolved,
                "locationAttempts": metrics.walletEnrichmentAttempts, "locationMatches": metrics.walletEnrichmentMatches,
                "missingLocation": metrics.walletEnrichmentSkippedWithoutLocation] : nil
            let report = TesterReport(appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                catalogueVersion: environment.graph?.catalogue.catalogueVersion,
                area: area, expected: expected, actual: actual, steps: steps,
                counters: counters, walletCapture: wallet, arrivalLog: arrival)
            let data = try report.encoded()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pickme-tester-report.json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            preview = String(decoding: data, as: UTF8.self); prepared = report; reportURL = url
        } catch { message = error.localizedDescription }
    }

    private func send() async {
        guard let prepared else { return }
        working = true; message = nil
        defer { working = false }
        do { submitted = try await sync.submitTesterReport(prepared); await refreshReports() }
        catch { message = error.localizedDescription }
    }

    private func refreshReports() async {
        let account = ClerkSession.currentUserID
        do {
            let reports = try await sync.listTesterReports()
            guard account == ClerkSession.currentUserID else { return }
            previousReports = reports
        } catch { message = "Review status could not be loaded. \(error.localizedDescription)" }
    }

    private func delete(_ report: SubmittedTesterReport) async {
        working = true; message = nil
        defer { working = false; pendingDelete = nil }
        do {
            try await sync.deleteTesterReport(id: report.id)
            if submitted?.id == report.id { submitted = nil }
            previousReports.removeAll { $0.id == report.id }
            message = "Submitted report deleted."
        } catch { message = "The report was not deleted. \(error.localizedDescription)" }
    }
}
