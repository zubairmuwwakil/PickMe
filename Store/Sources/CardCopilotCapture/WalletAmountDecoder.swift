import Foundation

public struct WalletAmountDecodeResult: Sendable, Equatable {
    public let raw: String?
    public let decimal: String?
    public let status: WalletAmountDecodeStatus
}

public enum WalletAmountDecoder {
    public static func decode(_ raw: String?, currencyCode: String?, locale: Locale) -> WalletAmountDecodeResult {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .init(raw: raw, decimal: nil, status: .absent)
        }

        // Decimal(string:locale:) silently decodes "EC$17.49" as zero under en_CA.
        // Currency parsing understands the captured ISO code and is therefore the primary path.
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        if let code = currencyCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), code.count == 3 {
            formatter.currencyCode = code
        }
        formatter.generatesDecimalNumbers = true

        if let number = formatter.number(from: raw), containsDigit(raw), let canonical = canonical(number) {
            return .init(raw: raw, decimal: canonical, status: .decoded)
        }

        // Plain numeric values remain valid even when Apple omits a currency symbol.
        let decimalFormatter = NumberFormatter()
        decimalFormatter.locale = locale
        decimalFormatter.numberStyle = .decimal
        decimalFormatter.generatesDecimalNumbers = true
        if isPlainLocalizedNumber(raw, formatter: decimalFormatter),
           let number = decimalFormatter.number(from: raw), let canonical = canonical(number) {
            return .init(raw: raw, decimal: canonical, status: .decoded)
        }
        if let canonical = strictCurrencyFallback(raw) {
            return .init(raw: raw, decimal: canonical, status: .decoded)
        }
        return .init(raw: raw, decimal: nil, status: .undecodable)
    }

    private static func containsDigit(_ value: String) -> Bool { value.unicodeScalars.contains { CharacterSet.decimalDigits.contains($0) } }

    private static func isPlainLocalizedNumber(_ value: String, formatter: NumberFormatter) -> Bool {
        var allowed = CharacterSet.decimalDigits
        allowed.formUnion(.whitespaces)
        allowed.insert(charactersIn: "+-\(formatter.decimalSeparator ?? ".")\(formatter.groupingSeparator ?? ",")  '")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func canonical(_ number: NSNumber) -> String? {
        let decimal = number.decimalValue
        guard decimal.isFinite else { return nil }
        var value = decimal
        return NSDecimalString(&value, Locale(identifier: "en_US_POSIX"))
    }

    /// Handles currency symbols that NumberFormatter does not recognize for the device locale.
    /// Only a fully validated numeric core is accepted; symbols/letters may occur only outside it.
    private static func strictCurrencyFallback(_ raw: String) -> String? {
        guard let first = raw.firstIndex(where: { $0.isNumber || $0 == "-" }),
              let last = raw.lastIndex(where: { $0.isNumber }) else { return nil }
        let core = String(raw[first...last]).replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: " ", with: "").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "'", with: "")
        guard core.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }),
              core.filter({ $0 == "-" }).count <= 1, !core.dropFirst().contains("-") else { return nil }
        let dot = core.lastIndex(of: "."), comma = core.lastIndex(of: ",")
        let decimalSeparator: Character?
        if let dot, let comma { decimalSeparator = dot > comma ? "." : "," }
        else if let separator = dot ?? comma {
            let fractionCount = core.distance(from: core.index(after: separator), to: core.endIndex)
            decimalSeparator = (1...2).contains(fractionCount) ? core[separator] : nil
        } else { decimalSeparator = nil }
        var normalized = ""
        for character in core {
            if character.isNumber || character == "-" { normalized.append(character) }
            else if character == decimalSeparator { normalized.append(".") }
        }
        guard normalized.range(of: #"^-?\d+(\.\d+)?$"#, options: .regularExpression) != nil,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var value = decimal
        return NSDecimalString(&value, Locale(identifier: "en_US_POSIX"))
    }
}
