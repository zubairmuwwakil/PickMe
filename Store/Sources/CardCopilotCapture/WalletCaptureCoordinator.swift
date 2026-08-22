import Foundation

public protocol WalletCaptureUploading: Sendable {
    func upload(_ event: WalletCaptureEvent) async -> WalletUploadResult
}

public struct WalletCaptureHTTPUploader: WalletCaptureUploading, @unchecked Sendable {
    private let endpoint: URL
    private let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        endpoint = baseURL.appendingPathComponent("api/v1/wallet-events")
        self.token = token; self.session = session
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
            let disposition = (try? JSONDecoder().decode(Response.self, from: data).disposition)
            if http.statusCode == 401 { return .init(.authenticationRequired, safeError: "authenticationRequired") }
            if http.statusCode == 429 {
                return .init(.retry, retryAfter: Self.retryDate(http.value(forHTTPHeaderField: "Retry-After")), safeError: "rateLimited")
            }
            if (500...).contains(http.statusCode) { return .init(.retry, safeError: "serverUnavailable") }
            if (400...).contains(http.statusCode) { return .init(disposition == "invalid" ? .invalid : .retry, safeError: "http\(http.statusCode)") }
            switch disposition {
            case "accepted": return .init(.accepted)
            case "duplicate": return .init(.duplicate)
            case "authenticationRequired": return .init(.authenticationRequired)
            case "invalid": return .init(.invalid)
            default: return .init(.retry, safeError: "undecodableResponse")
            }
        } catch {
            return .init(.retry, safeError: "networkUnavailable")
        }
    }

    private struct Response: Decodable { let disposition: String? }
    private static func retryDate(_ value: String?) -> Date? {
        guard let value, let seconds = TimeInterval(value) else { return nil }
        return Date().addingTimeInterval(max(0, seconds))
    }
}

public actor WalletCaptureCoordinator {
    public typealias LocationProvider = @Sendable () async -> WalletCaptureLocation?
    public typealias ReceiptPublisher = @Sendable (WalletCaptureEvent, Bool) async -> Void

    private let outbox: WalletOutboxStore
    private let uploader: (any WalletCaptureUploading)?
    private let locationProvider: LocationProvider
    private let receiptPublisher: ReceiptPublisher
    private let now: @Sendable () -> Date

    public init(outbox: WalletOutboxStore, uploader: (any WalletCaptureUploading)?,
                locationProvider: @escaping LocationProvider = { nil },
                receiptPublisher: @escaping ReceiptPublisher = { _, _ in },
                now: @escaping @Sendable () -> Date = Date.init) {
        self.outbox = outbox; self.uploader = uploader; self.locationProvider = locationProvider
        self.receiptPublisher = receiptPublisher; self.now = now
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
        guard [input.merchant, input.amount, input.transactionName, input.currency, input.card, payment]
            .contains(where: { $0?.isEmpty == false }) else { throw WalletCaptureError.emptyInput }
        let event = WalletCaptureEvent(schemaVersion: 2, captureVersion: 1,
            source: "apple_wallet_automation", transport: "pickme_app_intent",
            eventId: UUID().uuidString, capturedAt: now(), timezone: timezone.identifier,
            transaction: transaction, location: nil, client: client)
        var queued = WalletQueuedCapture(event: event, deliveryState: .pending, attemptCount: 0,
            lastAttemptAt: nil, nextRetryAt: nil, safeError: nil,
            timeline: [.init(at: now(), stage: "walletFieldsReceived"),
                       .init(at: now(), stage: "amount\(decoded.status.rawValue.capitalized)"),
                       .init(at: now(), stage: "savedLocally")])
        do { try await outbox.persist(queued, to: unassigned ? .unassigned : .pending) }
        catch { throw WalletCaptureError.localPersistenceFailed }

        await receiptPublisher(event, uploader == nil)

        if let location = await locationProvider() {
            try? await outbox.enrich(eventID: event.eventId, location: location)
            queued.event.location = location
        }
        if !unassigned { await drain(currentEventID: event.eventId) }
        return event
    }

    public func drain(currentEventID: String? = nil) async {
        guard let uploader else { return }
        try? await outbox.recoverStaleInflight(olderThan: now().addingTimeInterval(-300))
        guard var pending = try? await outbox.captures(in: .pending) else { return }
        if let currentEventID, let index = pending.firstIndex(where: { $0.event.eventId == currentEventID }) {
            pending.insert(pending.remove(at: index), at: 0)
        }
        for item in pending {
            if let retry = item.nextRetryAt, retry > now() { continue }
            guard var claimed = try? await outbox.claim(item.event.eventId) else { continue }
            claimed.attemptCount += 1; claimed.lastAttemptAt = now()
            let result = await uploader.upload(claimed.event)
            try? await outbox.resolve(claimed, result: result)
        }
    }
}
