import Foundation

public protocol WalletCaptureUploading: Sendable {
    func upload(_ event: WalletCaptureEvent) async -> WalletUploadResult
}

/// The outcome of a connection probe. The failure reason contains only local precondition or
/// transport/HTTP information; it never includes the installation token or a server response body.
public struct WalletCaptureConnectionTestResult: Sendable, Equatable {
    public let isConnected: Bool
    public let failureReason: String?

    public init(isConnected: Bool, failureReason: String? = nil) {
        self.isConnected = isConnected
        self.failureReason = failureReason
    }
}

public struct WalletCaptureHTTPUploader: WalletCaptureUploading, @unchecked Sendable {
    private let baseURL: URL
    private let endpoint: URL
    private let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        endpoint = baseURL.appendingPathComponent("api/v1/wallet-events")
        self.token = token; self.session = session
    }

    public func testConnection() async -> Bool {
        await testConnectionResult().isConnected
    }

    public func testConnectionResult() async -> WalletCaptureConnectionTestResult {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/wallet-installations/test"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                return .init(isConnected: false, failureReason: "The server returned an invalid response.")
            }
            guard 200..<300 ~= response.statusCode else {
                return .init(isConnected: false, failureReason: "The server rejected the installation credential (HTTP \(response.statusCode)).")
            }
            return .init(isConnected: true)
        } catch let error as URLError {
            return .init(isConnected: false, failureReason: "The network request failed (\(error.code.rawValue): \(error.localizedDescription)).")
        } catch {
            return .init(isConnected: false, failureReason: "The request failed: \(error.localizedDescription)")
        }
    }

    public func revokeInstallation() async -> Bool {
        do {
            var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/wallet-installations/revoke"))
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse).map { 200..<300 ~= $0.statusCode } == true
        } catch { return false }
    }

    public func upload(_ event: WalletCaptureEvent) async -> WalletUploadResult {
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(event)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .init(.retry, safeError: "invalidResponse") }
            let decoded = try? JSONDecoder().decode(Response.self, from: data)
            let disposition = decoded?.disposition
            if http.statusCode == 401 || http.statusCode == 403 {
                return .init(.authenticationRequired, safeError: "authenticationRequired", httpStatus: http.statusCode)
            }
            if http.statusCode == 429 {
                return .init(.retry, retryAfter: Self.retryDate(http.value(forHTTPHeaderField: "Retry-After")), safeError: "rateLimited", httpStatus: http.statusCode)
            }
            if (500...).contains(http.statusCode) { return .init(.retry, safeError: "serverUnavailable", httpStatus: http.statusCode) }
            if (400...).contains(http.statusCode) { return .init(disposition == "invalid" ? .invalid : .retry, safeError: "http\(http.statusCode)", httpStatus: http.statusCode) }
            switch disposition {
            case "accepted": return .init(.accepted, httpStatus: http.statusCode, serverEventID: decoded?.eventId, refinementVerdict: decoded?.refinement?.verdict)
            case "duplicate": return .init(.duplicate, httpStatus: http.statusCode, serverEventID: decoded?.eventId)
            case "authenticationRequired": return .init(.authenticationRequired, httpStatus: http.statusCode)
            case "invalid": return .init(.invalid, httpStatus: http.statusCode)
            default: return .init(.retry, safeError: "undecodableResponse", httpStatus: http.statusCode)
            }
        } catch {
            return .init(.retry, safeError: "networkUnavailable")
        }
    }

    private struct Response: Decodable {
        struct Refinement: Decodable { let verdict: String? }
        let disposition: String?
        let eventId: String?
        let refinement: Refinement?
    }
    private static func retryDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value) { return Date().addingTimeInterval(max(0, seconds)) }
        return HTTPDateFormatter.date(from: value)
    }

    private enum HTTPDateFormatter {
        static func date(from value: String) -> Date? {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            return formatter.date(from: value)
        }
    }
}

public actor WalletCaptureCoordinator {
    public typealias LocationProvider = @Sendable () async -> WalletLocationEnrichment
    public typealias VerdictProvider = @Sendable (WalletCaptureEvent) async -> WalletCaptureVerdictEvaluation
    public typealias ReceiptPublisher = @Sendable (WalletCaptureReceipt) async -> Void
    public typealias DrainObserver = @Sendable (WalletCaptureDrainSummary) async -> Void

    private let outbox: WalletOutboxStore
    private let uploader: (any WalletCaptureUploading)?
    private let locationProvider: LocationProvider
    private let verdictProvider: VerdictProvider
    private let receiptPublisher: ReceiptPublisher
    private let drainObserver: DrainObserver
    private let diagnostics: WalletCaptureDiagnosticsStore?
    private let isOffline: @Sendable () -> Bool
    private let now: @Sendable () -> Date

    public init(outbox: WalletOutboxStore, uploader: (any WalletCaptureUploading)?,
                diagnostics: WalletCaptureDiagnosticsStore? = nil,
                locationProvider: @escaping LocationProvider = { .unavailable },
                verdictProvider: @escaping VerdictProvider = { _ in .init() },
                receiptPublisher: @escaping ReceiptPublisher = { _ in },
                drainObserver: @escaping DrainObserver = { _ in },
                isOffline: @escaping @Sendable () -> Bool = { false },
                now: @escaping @Sendable () -> Date = Date.init) {
        self.outbox = outbox; self.uploader = uploader; self.diagnostics = diagnostics
        self.locationProvider = locationProvider; self.verdictProvider = verdictProvider
        self.receiptPublisher = receiptPublisher; self.drainObserver = drainObserver
        self.isOffline = isOffline; self.now = now
    }

    @discardableResult
    public func capture(_ input: WalletCaptureInput, client: WalletCaptureClient,
                        locale: Locale, timezone: TimeZone,
                        unassigned: Bool = false) async throws -> WalletCaptureEvent {
        let decoded = WalletAmountDecoder.decode(input.amount, currencyCode: input.currency, locale: locale)
        let payment = input.paymentMethod == input.transactionName ? nil : input.paymentMethod
        let transaction = WalletCaptureTransaction(
            merchantRaw: input.merchant, transactionNameRaw: input.transactionName,
            amountRaw: input.amount, amountDecimal: decoded.decimal, amountDecodeStatus: decoded.status,
            currencyRaw: input.currency, cardRaw: input.card, paymentMethodRaw: payment)
        let event = WalletCaptureEvent(schemaVersion: 2, captureVersion: 1,
            source: "apple_wallet_automation", transport: "pickme_app_intent",
            eventId: UUID().uuidString, capturedAt: now(), timezone: timezone.identifier,
            transaction: transaction, location: nil, client: client)
        let meaningful = event.isMeaningful
        var queued = WalletQueuedCapture(event: event, deliveryState: meaningful ? .pending : .quarantined, attemptCount: 0,
            lastAttemptAt: nil, nextRetryAt: nil, safeError: nil,
            timeline: [.init(at: now(), stage: "walletFieldsReceived"),
                       .init(at: now(), stage: "amount\(decoded.status.rawValue.capitalized)")])
        if !meaningful {
            queued.safeError = "automationMappingEmpty"
            queued.timeline.append(.init(at: now(), stage: "configurationError", detail: "allWalletFieldsEmpty"))
        }
        let bucket: WalletOutboxBucket = meaningful ? (unassigned ? .unassigned : .pending) : .quarantined
        do {
            try await outbox.persist(queued, to: bucket)
            queued.timeline.append(.init(at: now(), stage: "savedLocally"))
            try? await outbox.appendTimeline(eventID: event.eventId, stage: "savedLocally")
        } catch {
            queued.safeError = "localPersistenceFailed"
            queued.timeline.append(.init(at: now(), stage: "localPersistenceFailed"))
            try? await diagnostics?.begin(queued)
            throw WalletCaptureError.localPersistenceFailed
        }
        try? await diagnostics?.begin(queued)

        let verdict = meaningful ? await verdictProvider(event) : .init(issue: "allWalletFieldsEmpty")
        try? await outbox.appendTimeline(eventID: event.eventId, stage: "verdictComputedOnDevice",
                                         detail: verdict.capDataIsStale ? "capDataStale" : verdict.issue)
        try? await diagnostics?.append(eventID: event.eventId, stage: "verdictComputedOnDevice",
                                       detail: verdict.capDataIsStale ? "capDataStale" : verdict.issue)
        let receiptKind: WalletCaptureReceiptKind = !meaningful ? .configurationError
            : (unassigned ? .savedAwaitingAccount : (isOffline() || uploader == nil ? .savedOffline : .savedSecurely))
        await receiptPublisher(.init(event: event, kind: receiptKind, verdict: verdict))

        guard meaningful else { return event }
        let enrichment = await locationProvider()
        if let location = enrichment.location, abs(now().timeIntervalSince(location.capturedAt)) <= 60 {
            try? await outbox.enrich(eventID: event.eventId, location: location)
            try? await diagnostics?.append(eventID: event.eventId, stage: "locationCaptured", detail: accuracyCategory(location.horizontalAccuracyMeters))
            queued.event.location = location
        } else {
            let outcome: WalletLocationOutcome = enrichment.location == nil ? enrichment.outcome : .staleFix
            try? await outbox.appendTimeline(eventID: event.eventId, stage: "locationUnavailable", detail: outcome.rawValue)
            try? await diagnostics?.append(eventID: event.eventId, stage: "locationUnavailable", detail: outcome.rawValue)
        }
        if !unassigned { await drain(currentEventID: event.eventId) }
        return event
    }

    @discardableResult
    public func drain(currentEventID: String? = nil) async -> WalletCaptureDrainSummary {
        var summary = WalletCaptureDrainSummary()
        guard let uploader else { return summary }
        try? await outbox.recoverStaleInflight(olderThan: now().addingTimeInterval(-300))
        guard var pending = try? await outbox.captures(in: .pending) else { return summary }
        if let currentEventID, let index = pending.firstIndex(where: { $0.event.eventId == currentEventID }) {
            pending.insert(pending.remove(at: index), at: 0)
        }
        for item in pending {
            if item.deliveryState == .authenticationBlocked { summary.authenticationBlocked += 1; continue }
            if let retry = item.nextRetryAt, retry > now() { continue }
            guard var claimed = try? await outbox.claim(item.event.eventId) else { continue }
            claimed.attemptCount += 1; claimed.lastAttemptAt = now()
            claimed.timeline.append(.init(at: now(), stage: "uploadAttempted"))
            try? await outbox.persist(claimed, to: .inflight)
            let result = await uploader.upload(claimed.event)
            switch result.disposition {
            case .accepted:
                summary.accepted += 1
                if claimed.event.eventId != currentEventID { summary.backlogUploaded += 1 }
            case .duplicate:
                summary.duplicates += 1
                if claimed.event.eventId != currentEventID { summary.backlogUploaded += 1 }
            case .authenticationRequired: summary.authenticationBlocked += 1
            case .invalid: summary.quarantined += 1
            case .retry: summary.retainedForRetry += 1
            }
            if result.disposition == .accepted || result.disposition == .duplicate {
                try? await diagnostics?.update(eventID: claimed.event.eventId, capture: claimed, result: result)
                try? await diagnostics?.complete(eventID: claimed.event.eventId, disposition: result.disposition, result: result)
            } else {
                var diagnosticCapture = claimed
                diagnosticCapture.deliveryState = result.disposition == .invalid ? .quarantined :
                    (result.disposition == .authenticationRequired ? .authenticationBlocked : .pending)
                try? await diagnostics?.update(eventID: claimed.event.eventId, capture: diagnosticCapture, result: result)
            }
            try? await outbox.resolve(claimed, result: result)
        }
        await drainObserver(summary)
        return summary
    }

    private func accuracyCategory(_ meters: Double) -> String {
        if meters <= 25 { return "precise" }
        if meters <= 100 { return "nearby" }
        return "coarse"
    }
}
