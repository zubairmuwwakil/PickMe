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
    /// Distinct canonical merchants receiving their first retained issuer-MCC observation.
    /// This is intentionally not a claim that PickMe had no seed/category prior for the merchant.
    public let newlyResolvedMerchants: Int
    /// Distinct accepted merchant/MCC pairs whose literal MCC differs from the shipped seed prior.
    /// A seed is an editorial guess, so this is useful correction feedback, not an error count.
    public let correctedSeedMCCs: Int
    public let locationJoinedRows: Int
    public let duplicateRows: Int
    public let missingMCCRows: Int
    public let invalidMCCRows: Int
    public let missingDateRows: Int
    public let unrecognizedMerchantRows: Int

    public var skippedRows: Int {
        duplicateRows + missingMCCRows + invalidMCCRows + missingDateRows + unrecognizedMerchantRows
    }

    public init(totalRows: Int, importedRows: Int, newlyResolvedMerchants: Int = 0,
                correctedSeedMCCs: Int = 0, locationJoinedRows: Int = 0,
                duplicateRows: Int, missingMCCRows: Int, invalidMCCRows: Int,
                missingDateRows: Int, unrecognizedMerchantRows: Int) {
        self.totalRows = totalRows
        self.importedRows = importedRows
        self.newlyResolvedMerchants = newlyResolvedMerchants
        self.correctedSeedMCCs = correctedSeedMCCs
        self.locationJoinedRows = locationJoinedRows
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

    private enum DateKind { case transaction, posting }

    private static let maximumRows = 5_000
    private let defaults: UserDefaults
    private let storageKey: String
    private let lastSuccessfulImportKey: String
    private let metrics: CategoryResolutionMetricsStore
    private let lock = NSLock()
    private var evidenceRows: [MerchantMCCEvidence]

    public init(defaults: UserDefaults = UserDefaults(suiteName: "group.ca.inunity.pickme") ?? .standard,
                storageKey: String = "merchant-mcc-exact-import-v1",
                metrics: CategoryResolutionMetricsStore = CategoryResolutionMetricsStore()) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.lastSuccessfulImportKey = "\(storageKey).last-successful-import"
        self.metrics = metrics
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([MerchantMCCEvidence].self, from: data) {
            // Direct rows in this ledger are not arbitrary direct evidence: they are issuer-file
            // rows that this store itself safely joined to one local, located purchase.
            self.evidenceRows = decoded.filter {
                $0.kind == .ownerImportedMcc || $0.kind == .directOwnerMcc
            }
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

    /// The only import-habit metadata retained. It is not tied to a file, statement, merchant,
    /// account, or amount, and local-history deletion removes it with the evidence ledger.
    public var lastSuccessfulImportAt: Date? {
        lock.lock(); defer { lock.unlock() }
        return defaults.object(forKey: lastSuccessfulImportKey) as? Date
    }

    /// Statements are usually monthly. This deliberately supports a passive Settings reminder
    /// rather than a notification or a background check against an issuer account.
    public func isMonthlyImportDue(asOf date: Date = Date()) -> Bool {
        guard let lastSuccessfulImportAt else { return false }
        return date.timeIntervalSince(lastSuccessfulImportAt) >= 25 * 24 * 60 * 60
    }

    /// Imports only normalized evidence. Raw CSV rows, amounts, account/card numbers and filenames
    /// are never persisted.
    ///
    /// When `localPurchases` is supplied, amount/currency/card-network values are used only while
    /// this call is executing to attempt a conservative location join. A row becomes
    /// `directOwnerMcc` only when exactly one located purchase matches the same deterministic
    /// merchant, date window, CAD amount, and (when the import knows it) card network. Zero or
    /// multiple matches fail closed to brand-level `ownerImportedMcc` evidence.
    ///
    /// `StoredPurchase.amountCad` is explicitly CAD. Therefore numeric equality is never enough to
    /// join an amount: the issuer row must explicitly identify its billing/transaction currency as
    /// CAD. Unknown or non-CAD currency keeps the literal MCC useful but unlocated.
    ///
    /// Brand-level idempotency is scoped to non-sensitive facts already retained by the graph
    /// (source + canonical merchant + UTC day + MCC + network). Safely joined rows instead dedupe on
    /// the opaque local purchase UUID. If that purchase already has the same literal MCC in its
    /// StoredObservation, both paths intentionally share the observation evidence ID so composing
    /// history + imports cannot turn one transaction into two independent direct observations.
    @discardableResult
    public func importCSV(_ data: Data,
                          source: MerchantMCCExactImportSource = .genericCSV,
                          localPurchases: [StoredPurchase] = [],
                          cardNetworksByID: [String: String] = [:]) throws
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
        let amountIndex = Self.firstIndex(in: normalizedHeader,
                                          aliases: ["billingamount", "transactionamount", "purchaseamount", "amount"])
        let currencyIndex = Self.firstIndex(in: normalizedHeader,
                                            aliases: ["billingcurrencycode", "billingcurrency",
                                                      "transactioncurrencycode", "transactioncurrency", "currency"])
        let dateKind: DateKind = ["postingdate", "posteddate"].contains(normalizedHeader[dateIndex])
            ? .posting : .transaction
        let normalizedCardNetworks = cardNetworksByID.reduce(into: [String: String]()) { result, item in
            if let network = Self.normalizedNetwork(item.value) { result[item.key] = network }
        }

        var imported: [MerchantMCCEvidence] = []
        // Used only during this call. Once a safely joined row is accepted, the metrics store
        // receives a Boolean outcome—not this purchase, MCC, or import row.
        var joinedOutcomeCandidates: [(evidenceID: String, purchase: StoredPurchase, mcc: Int)] = []
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
            let amount = amountIndex.flatMap { Self.parseAmount(Self.value(row, at: $0)) }
            let currency = currencyIndex.flatMap { Self.normalizedCurrency(Self.value(row, at: $0)) }

            if currency == "CAD",
               let purchase = Self.uniqueLocatedPurchaseMatch(
                    importedMerchantRaw: merchantRaw,
                    canonicalMerchantID: match.merchant.id,
                    observedAt: observedAt,
                    dateKind: dateKind,
                    amount: amount,
                    network: network,
                    localPurchases: localPurchases,
                    cardNetworksByID: normalizedCardNetworks) {
                let joinedNetwork = network
                    ?? purchase.cardUsedId.flatMap { normalizedCardNetworks[$0] }
                let joinReference = "issuerJoin:\(source.rawValue):\(purchase.id.uuidString.lowercased()):\(mcc):\(joinedNetwork ?? "unknown")"
                let evidenceID: String
                if let observation = purchase.observation,
                   observation.observedMerchantCategoryCode == mcc {
                    // Same transaction + same literal MCC is corroboration, not a second independent
                    // observation. Share the existing evidence-builder ID so graph composition
                    // dedupes it even though the importer keeps its own local ledger.
                    evidenceID = "observation:\(observation.id.uuidString)"
                } else {
                    // A conflicting literal MCC remains distinct so the graph sees the conflict
                    // rather than silently overwriting either source.
                    evidenceID = joinReference
                }
                imported.append(MerchantMCCEvidence(
                    id: evidenceID,
                    merchantKey: match.merchant.name,
                    latitude: purchase.merchantLatitude,
                    longitude: purchase.merchantLongitude,
                    channel: .inStore,
                    network: joinedNetwork,
                    mcc: mcc,
                    kind: .directOwnerMcc,
                    sourceConfidence: 1,
                    observedAt: purchase.createdAt,
                    sourceReference: joinReference))
                joinedOutcomeCandidates.append((evidenceID, purchase, mcc))
                continue
            }

            let canonicalKey = MerchantMCCQuery(merchantKey: match.merchant.name).merchantKey
            let day = Self.utcDay(observedAt)
            let reference = "issuerFile:\(source.rawValue):\(canonicalKey):\(day):\(mcc):\(network ?? "unknown")"
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
        let existingMerchantKeys = Set(evidenceRows.map(\.merchantKey))
        var duplicates = 0
        var accepted = 0
        var acceptedJoined = 0
        var acceptedEvidenceIDs = Set<String>()
        var newlyResolvedMerchantKeys = Set<String>()
        var correctedSeedPairs = Set<String>()
        for evidence in imported {
            guard existingIDs.insert(evidence.id).inserted else { duplicates += 1; continue }
            evidenceRows.append(evidence)
            accepted += 1
            acceptedEvidenceIDs.insert(evidence.id)
            if evidence.kind == .directOwnerMcc { acceptedJoined += 1 }
            if !existingMerchantKeys.contains(evidence.merchantKey) {
                newlyResolvedMerchantKeys.insert(evidence.merchantKey)
            }
            if let mcc = evidence.mcc,
               let seedMCC = MerchantMCCSeedCatalogue.seedMCC(for: evidence.merchantKey),
               seedMCC != mcc {
                correctedSeedPairs.insert("\(evidence.merchantKey):\(mcc)")
            }
        }
        if evidenceRows.count > Self.maximumRows {
            evidenceRows = Array(evidenceRows.sorted { $0.observedAt > $1.observedAt }
                .prefix(Self.maximumRows))
        }
        persistLocked()
        if accepted > 0 { defaults.set(Date(), forKey: lastSuccessfulImportKey) }

        for candidate in joinedOutcomeCandidates where acceptedEvidenceIDs.contains(candidate.evidenceID) {
            // A reconciled literal MCC already supplied this outcome. An import that corroborates
            // it is not a second independent result.
            guard candidate.purchase.observation?.observedMerchantCategoryCode != candidate.mcc,
                  let prediction = candidate.purchase.prediction,
                  let matchesLearnedMCC = MerchantMCCDecisionQuality.runtimeEvidenceWinnerWasValidated(
                    prediction: prediction,
                    observedMerchantCategoryCode: candidate.mcc)
            else { continue }
            metrics.record(.mccRuntimeEvidenceWinnerExactMCCValidated(
                matchesLearnedMCC: matchesLearnedMCC))
        }

        return MerchantMCCExactImportSummary(
            totalRows: bodyRows.count,
            importedRows: accepted,
            newlyResolvedMerchants: newlyResolvedMerchantKeys.count,
            correctedSeedMCCs: correctedSeedPairs.count,
            locationJoinedRows: acceptedJoined,
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
        defaults.removeObject(forKey: lastSuccessfulImportKey)
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(evidenceRows) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func uniqueLocatedPurchaseMatch(
        importedMerchantRaw: String,
        canonicalMerchantID: String,
        observedAt: Date,
        dateKind: DateKind,
        amount: Double?,
        network: String?,
        localPurchases: [StoredPurchase],
        cardNetworksByID: [String: String]
    ) -> StoredPurchase? {
        // Amount is the strongest non-identity transaction join available in today's local model.
        // Without it, one merchant visit on a date is too easy to mis-bind to a statement row.
        guard let amount, amount.isFinite else { return nil }
        guard MerchantMCCSeedCatalogue.canonicalMatch(merchantName: importedMerchantRaw)?.merchant.id
                == canonicalMerchantID else { return nil }

        let maxDayDistance = dateKind == .posting ? 4 : 1
        let candidates = localPurchases.filter { purchase in
            guard let latitude = purchase.merchantLatitude, latitude.isFinite,
                  let longitude = purchase.merchantLongitude, longitude.isFinite
            else { return false }
            guard canonicalMerchantIDForPurchase(purchase) == canonicalMerchantID else { return false }
            guard dayDistance(purchase.createdAt, observedAt) <= maxDayDistance else { return false }
            guard let localAmount = purchase.amountCad, localAmount.isFinite,
                  abs(localAmount - amount) <= 0.01 else { return false }

            if let network {
                guard let cardID = purchase.cardUsedId,
                      cardNetworksByID[cardID] == network else { return false }
            }
            return true
        }

        return candidates.count == 1 ? candidates[0] : nil
    }

    private static func canonicalMerchantIDForPurchase(_ purchase: StoredPurchase) -> String? {
        for value in [purchase.merchantKey, purchase.merchantLabel, purchase.prediction?.merchantName] {
            guard let value else { continue }
            if let canonical = MerchantMCCSeedCatalogue.canonicalMatch(merchantName: value) {
                return canonical.merchant.id
            }
        }
        return nil
    }

    private static func dayDistance(_ lhs: Date, _ rhs: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.startOfDay(for: lhs)
        let end = calendar.startOfDay(for: rhs)
        return abs(calendar.dateComponents([.day], from: start, to: end).day ?? Int.max)
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
        if normalized.contains("mastercard") { return "mastercard" }
        if normalized.contains("amex") || normalized.contains("americanexpress") { return "amex" }
        if normalized.contains("discover") { return "discover" }
        return nil
    }

    private static func normalizedCurrency(_ value: String) -> String? {
        let normalized = value.uppercased().filter(\.isLetter)
        return normalized.isEmpty ? nil : normalized
    }

    private static func parseAmount(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let negativeByParentheses = trimmed.contains("(") && trimmed.contains(")")
        let numeric = trimmed.filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard !numeric.isEmpty, var amount = Double(numeric) else { return nil }
        if negativeByParentheses { amount = -abs(amount) }
        return amount
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

    private static func utcDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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
}
