import AppIntents
@preconcurrency import CoreLocation
import Foundation

/// Disposable Apple-boundary probe for the native Wallet capture design.
///
/// This intentionally performs no production capture work. It records the exact strings
/// Shortcuts coerces into App Intent parameters, samples whether a fresh location can arrive
/// inside the proposed two-second budget, and writes one inspectable JSON file.
struct WalletCaptureProbeIntent: AppIntent {
    static let title: LocalizedStringResource = "Probe Wallet Purchase Fields"
    static let description = IntentDescription(
        "Temporarily records the Wallet Transaction values that Shortcuts passes to PickMe."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Merchant")
    var merchant: String?

    @Parameter(title: "Amount")
    var amount: String?

    @Parameter(title: "Name")
    var transactionName: String?

    @Parameter(title: "Currency")
    var currency: String?

    @Parameter(title: "Card")
    var card: String?

    @Parameter(title: "Payment Method")
    var paymentMethod: String?

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let startedAt = Date()
        let fields = WalletCaptureProbeFields(
            merchant: .init(merchant),
            amount: .init(amount),
            transactionName: .init(transactionName),
            currency: .init(currency),
            card: .init(card),
            paymentMethod: .init(paymentMethod)
        )

        var record = WalletCaptureProbeRecord(
            invocationID: UUID(),
            stage: .inputsPersisted,
            startedAt: startedAt,
            completedAt: nil,
            elapsedMilliseconds: nil,
            fields: fields,
            location: .notAttempted,
            client: .current
        )

        // Persist before the optional location probe. If iOS suspends the intent during the
        // location wait, the parameter-coercion evidence still survives.
        let fileURL = try WalletCaptureProbeWriter.write(record)

        record.location = await WalletCaptureProbeLocationSampler().sample(timeoutSeconds: 2)
        record.stage = .completed
        record.completedAt = Date()
        record.elapsedMilliseconds = record.completedAt.map {
            max(0, Int(($0.timeIntervalSince(startedAt) * 1_000).rounded()))
        }
        try WalletCaptureProbeWriter.write(record, to: fileURL)

        return .result(
            dialog: "Wallet probe saved. Open Files, then On My iPhone, PickMe, WalletCaptureProbe, latest.json."
        )
    }
}

private struct WalletCaptureProbeRecord: Encodable {
    enum Stage: String, Encodable {
        case inputsPersisted
        case completed
    }

    let probeVersion = 1
    let invocationID: UUID
    var stage: Stage
    let startedAt: Date
    var completedAt: Date?
    var elapsedMilliseconds: Int?
    let fields: WalletCaptureProbeFields
    var location: WalletCaptureProbeLocation
    let client: WalletCaptureProbeClient
}

private struct WalletCaptureProbeFields: Encodable {
    let merchant: WalletCaptureProbeString
    let amount: WalletCaptureProbeString
    let transactionName: WalletCaptureProbeString
    let currency: WalletCaptureProbeString
    let card: WalletCaptureProbeString
    let paymentMethod: WalletCaptureProbeString
}

/// Carries both the coerced text and an unambiguous UTF-8 representation. The `state` field
/// distinguishes nil from an empty string; JSON alone otherwise makes that easy to misread.
private struct WalletCaptureProbeString: Encodable {
    enum State: String, Encodable {
        case absent
        case empty
        case value
    }

    let state: State
    let value: String?
    let utf8Base64: String?
    let utf8Hex: String?
    let utf8ByteCount: Int
    let unicodeScalars: [String]

    init(_ value: String?) {
        self.value = value

        guard let value else {
            state = .absent
            utf8Base64 = nil
            utf8Hex = nil
            utf8ByteCount = 0
            unicodeScalars = []
            return
        }

        state = value.isEmpty ? .empty : .value
        let data = Data(value.utf8)
        utf8Base64 = data.base64EncodedString()
        utf8Hex = data.map { String(format: "%02x", $0) }.joined()
        utf8ByteCount = data.count
        unicodeScalars = value.unicodeScalars.map { String(format: "U+%04X", $0.value) }
    }

    private enum CodingKeys: String, CodingKey {
        case state
        case value
        case utf8Base64
        case utf8Hex
        case utf8ByteCount
        case unicodeScalars
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        if let value {
            try container.encode(value, forKey: .value)
        } else {
            try container.encodeNil(forKey: .value)
        }
        if let utf8Base64 {
            try container.encode(utf8Base64, forKey: .utf8Base64)
        } else {
            try container.encodeNil(forKey: .utf8Base64)
        }
        if let utf8Hex {
            try container.encode(utf8Hex, forKey: .utf8Hex)
        } else {
            try container.encodeNil(forKey: .utf8Hex)
        }
        try container.encode(utf8ByteCount, forKey: .utf8ByteCount)
        try container.encode(unicodeScalars, forKey: .unicodeScalars)
    }
}

private struct WalletCaptureProbeClient: Encodable {
    let appVersion: String
    let buildNumber: String
    let osVersion: String
    let locale: String
    let timezone: String

    static var current: Self {
        let info = Bundle.main.infoDictionary ?? [:]
        return .init(
            appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: info["CFBundleVersion"] as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            locale: Locale.current.identifier,
            timezone: TimeZone.current.identifier
        )
    }
}

private struct WalletCaptureProbeLocation: Encodable, Sendable {
    let authorization: String
    let outcome: String
    let sampleElapsedMilliseconds: Int
    let horizontalAccuracyMeters: Double?
    let locationAgeSeconds: Double?

    static let notAttempted = Self(
        authorization: "notChecked",
        outcome: "notAttempted",
        sampleElapsedMilliseconds: 0,
        horizontalAccuracyMeters: nil,
        locationAgeSeconds: nil
    )
}

@MainActor
private final class WalletCaptureProbeLocationSampler: NSObject, @MainActor CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<WalletCaptureProbeLocation, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var sampleStartedAt: Date?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func sample(timeoutSeconds: TimeInterval) async -> WalletCaptureProbeLocation {
        let authorization = Self.authorizationName(manager.authorizationStatus)
        guard manager.authorizationStatus == .authorizedAlways
                || manager.authorizationStatus == .authorizedWhenInUse else {
            return .init(
                authorization: authorization,
                outcome: "notAuthorized",
                sampleElapsedMilliseconds: 0,
                horizontalAccuracyMeters: nil,
                locationAgeSeconds: nil
            )
        }

        sampleStartedAt = Date()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
            timeoutTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                guard !Task.isCancelled else { return }
                self?.finish(
                    outcome: "timedOut",
                    horizontalAccuracyMeters: nil,
                    locationAgeSeconds: nil
                )
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(outcome: "emptyUpdate", horizontalAccuracyMeters: nil, locationAgeSeconds: nil)
            return
        }

        let age = max(0, Date().timeIntervalSince(location.timestamp))
        finish(
            outcome: age <= 60 ? "freshFix" : "staleFix",
            horizontalAccuracyMeters: location.horizontalAccuracy,
            locationAgeSeconds: age
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(
            outcome: "failed:\((error as NSError).code)",
            horizontalAccuracyMeters: nil,
            locationAgeSeconds: nil
        )
    }

    private func finish(
        outcome: String,
        horizontalAccuracyMeters: Double?,
        locationAgeSeconds: Double?
    ) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil

        let elapsed = sampleStartedAt.map {
            max(0, Int((Date().timeIntervalSince($0) * 1_000).rounded()))
        } ?? 0
        continuation.resume(
            returning: .init(
                authorization: Self.authorizationName(manager.authorizationStatus),
                outcome: outcome,
                sampleElapsedMilliseconds: elapsed,
                horizontalAccuracyMeters: horizontalAccuracyMeters,
                locationAgeSeconds: locationAgeSeconds
            )
        )
    }

    private static func authorizationName(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorizedAlways: "authorizedAlways"
        case .authorizedWhenInUse: "authorizedWhenInUse"
        @unknown default: "unknown"
        }
    }
}

private enum WalletCaptureProbeWriter {
    private static let directoryName = "WalletCaptureProbe"
    private static let fileName = "latest.json"

    static func write(_ record: WalletCaptureProbeRecord) throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = documents.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
        try write(record, to: fileURL)
        return fileURL
    }

    static func write(_ record: WalletCaptureProbeRecord, to fileURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(record)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
