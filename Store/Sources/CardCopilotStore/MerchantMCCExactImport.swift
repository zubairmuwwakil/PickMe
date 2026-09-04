import Foundation

/// Free/local exact-MCC acquisition from issuer-owned transaction exports.
///
/// The importer is intentionally strict: a row must contain an explicit MCC field, a merchant,
/// and a transaction/posting date. Category labels, SIC, NAICS, inferred categories and generic
/// descriptions are never converted into MCC evidence.
public enum MerchantMCCExactImportSource: String, Codable, Sendable, CaseIterable {
    case genericCSV
    case visaBusinessReporting

    var defaultNetwork: String? {
        switch self {
        case .genericCSV: return nil
        case .visaBusinessReporting: return "visa"
        }
    }
}

public struct MerchantMCCExactImportSummary: Equatable, Sendable {
    public let totalRows: Int
    public let importedRows: Int
    public let duplicateRows: Int
    public let missingMCCRows: Int
    public let invalidMCCRows: Int
    public let missingDateRows: Int
    public let unrecognizedMerchantRows: Int

    public var skippedRows: Int {
        duplicateRows + missingMCCRows + invalidMCCRows + missingDateRows + unrecognizedMerchantRows
    }

    public init(totalRows: Int, importedRows: Int, duplicateRows: Int,
                missingMCCRows: Int, invalidMCCRows: Int, missingDateRows: Int,
                unrecognizedMerchantRows: Int) {
        self.totalRows = totalRows
        self.importedRows = importedRows
        self.duplicateRows = duplicateRows
        self.missingMCCRows = missingMCCRows
        self.invalidMCCRows = invalidMCCRows
        self.missingDateRows = missingDateRows
        self.unrecognizedMerchantRows = unrecognizedMerchantRows
    }
}

public enum MerchantMCCExactImportError: Error, Equatable, LocalizedError {
    case emptyFile
    case invalidUTF8
    case missingRequiredColumns

    public var errorDescription: String? {
        switch self {
        case .emptyFile: return "The CSV is empty."
        case .invalidUTF8: return "The CSV is not valid UTF-8 text."
        case .missingRequiredColumns:
            return "The CSV needs merchant, MCC, and transaction/posting date columns."
        }
    }
}

public final class MerchantMCCImportedEvidenceStore: @unchecked Sendable {
    public static let shared = MerchantMCCImportedEvidenceStore()

    private static let maximumRows = 5_000
    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()
    private var evidenceRows: [MerchantMCCEvidence]

    public init(defaults: UserDefaults = UserDefaults(suiteName: "group.ca.inunity.pickme") ?? .standard,
                storageKey: String = "merchant-mcc-exact-import-v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([MerchantMCCEvidence].self, from: data) {
            self.evidenceRows = decoded.filter { $0.kind == .ownerImportedMcc }
        } else {
            self.evidenceRows = []
        }
    }

    public func evidence() -> [MerchantMCCEvidence] {
        lock.lock(); defer { lock.unlock() }
        return evidenceRows
    }

    public func evidence(for merchantName: String) -> [MerchantMCCEvidence] {
        guard let match = MerchantMCCSeedCatalogue.match(merchantName: merchantName) else { return [] }
        let key = MerchantMCCQuery(merchantKey: match.merchant.name).merchantKey
        lock.lock(); defer { lock.unlock() }
        return evidenceRows.filter { $0.merchantKey == key }
    }

    /// Imports only normalized evidence. Raw CSV rows, amounts, account/card numbers and filenames
    /// are never persisted. A stable one-way row fingerprint is retained solely for idempotency.
    @discardableResult
    public func importCSV(_ data: Data,
                          source: MerchantMCCExactImportSource = .genericCSV) throws
        -> MerchantMCCExactImportSummary {
        guard !data.isEmpty else { throw MerchantMCCExactImportError.emptyFile }
        guard var text = String(data: data, encoding: .utf8) else {
            throw MerchantMCCExactImportError.invalidUTF8
        }
        if text.first == "\u{feff}" { text.removeFirst() }

        let rows = Self.parseCSV(text)
        guard let header = rows.first, !header.isEmpty else {
            throw MerchantMCCExactImportError.emptyFile
        }
        let normalizedHeader = header.map(Self.normalizedHeader)
        guard let merchantIndex = Self.firstIndex(in: normalizedHeader,
                                                  aliases: ["merchantname", "merchant", "suppliername", "supplier"]),
              let mccIndex = Self.firstIndex(in: normalizedHeader,
                                             aliases: ["mcc", "mcccode", "merchantcategorycode"]),
              let dateIndex = Self.firstIndex(in: normalizedHeader,
                                              aliases: ["transactiondate", "postingdate", "posteddate", "date"])
        else { throw MerchantMCCExactImportError.missingRequiredColumns }

        let networkIndex = Self.firstIndex(in: normalizedHeader,
                                           aliases: ["network", "cardnetwork", "paymentnetwork"])

        var imported: [MerchantMCCEvidence] = []
        var missingMCC = 0
        var invalidMCC = 0
        var missingDate = 0
        var unrecognized = 0
        let bodyRows = Array(rows.dropFirst()).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }

        for row in bodyRows {
            let merchantRaw = Self.value(row, at: merchantIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let mccRaw = Self.value(row, at: mccIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            let dateRaw = Self.value(row, at: dateIndex).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !mccRaw.isEmpty else { missingMCC += 1; continue }
            let digits = mccRaw.filter(\.isNumber)
            guard digits.count == 4, digits.count == mccRaw.count, let mcc = Int(digits) else {
                invalidMCC += 1
                continue
            }
            guard let observedAt = Self.parseDate(dateRaw) else { missingDate += 1; continue }
            guard !merchantRaw.isEmpty,
                  let match = MerchantMCCSeedCatalogue.match(merchantName: merchantRaw)
            else { unrecognized += 1; continue }

            let networkRaw = networkIndex.map { Self.value(row, at: $0) }
            let network = Self.normalizedNetwork(networkRaw) ?? source.defaultNetwork
            let rowDigest = Self.fnv1a64(row.joined(separator: "\u{1f}"))
            let reference = "issuerFile:\(source.rawValue):\(rowDigest)"
            imported.append(MerchantMCCEvidence(
                id: reference,
                merchantKey: match.merchant.name,
                channel: .unknown,
                network: network,
                mcc: mcc,
                kind: .ownerImportedMcc,
                sourceConfidence: 1,
                observedAt: observedAt,
                sourceReference: reference))
        }

        lock.lock(); defer { lock.unlock() }
        var existingIDs = Set(evidenceRows.map(\.id))
        var duplicates = 0
        var accepted = 0
        for evidence in imported {
            guard existingIDs.insert(evidence.id).inserted else { duplicates += 1; continue }
            evidenceRows.append(evidence)
            accepted += 1
        }
        if evidenceRows.count > Self.maximumRows {
            evidenceRows = Array(evidenceRows.sorted { $0.observedAt > $1.observedAt }
                .prefix(Self.maximumRows))
        }
        persistLocked()

        return MerchantMCCExactImportSummary(
            totalRows: bodyRows.count,
            importedRows: accepted,
            duplicateRows: duplicates,
            missingMCCRows: missingMCC,
            invalidMCCRows: invalidMCC,
            missingDateRows: missingDate,
            unrecognizedMerchantRows: unrecognized)
    }

    public func forgetAll() {
        lock.lock(); defer { lock.unlock() }
        evidenceRows.removeAll()
        defaults.removeObject(forKey: storageKey)
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(evidenceRows) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func value(_ row: [String], at index: Int) -> String {
        index < row.count ? row[index] : ""
    }

    private static func firstIndex(in header: [String], aliases: Set<String>) -> Int? {
        header.firstIndex { aliases.contains($0) }
    }

    private static func normalizedHeader(_ value: String) -> String {
        value.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map(String.init).joined()
    }

    private static func normalizedNetwork(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.lowercased().filter(\.isLetter)
        if normalized.contains("visa") { return "visa" }
        if normalized.contains("mastercard") || normalized.contains("mastercard") { return "mastercard" }
        if normalized.contains("amex") || normalized.contains("americanexpress") { return "amex" }
        if normalized.contains("discover") { return "discover" }
        return nil
    }

    private static func parseDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: trimmed) { return date }

        // Visa Business Reporting documents MM/DD/YYYY. ISO and common Canadian export forms are
        // accepted too, but ambiguous numeric dates deliberately prefer the documented VBR order.
        for format in ["MM/dd/yyyy", "M/d/yyyy", "yyyy-MM-dd", "yyyy/MM/dd", "yyyy-MM-dd HH:mm:ss"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_CA_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            formatter.isLenient = false
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    /// RFC-4180-sized parser: commas, CRLF/LF and doubled quotes inside quoted fields.
    private static func parseCSV(_ text: String) -> [[String]] {
        let chars = Array(text)
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var index = 0

        func finishField() {
            row.append(field)
            field = ""
        }
        func finishRow() {
            finishField()
            rows.append(row)
            row = []
        }

        while index < chars.count {
            let char = chars[index]
            if char == "\"" {
                if quoted, index + 1 < chars.count, chars[index + 1] == "\"" {
                    field.append("\"")
                    index += 1
                } else {
                    quoted.toggle()
                }
            } else if char == ",", !quoted {
                finishField()
            } else if (char == "\n" || char == "\r"), !quoted {
                finishRow()
                if char == "\r", index + 1 < chars.count, chars[index + 1] == "\n" { index += 1 }
            } else {
                field.append(char)
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty { finishRow() }
        return rows
    }

    private static func fnv1a64(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
