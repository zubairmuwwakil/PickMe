import SwiftUI
import CardCopilotStore

/// Branded circular logo / avatar for merchants.
public struct MerchantBrandIconView: View {
    let merchantName: String
    let category: String
    var size: CGFloat = 24

    public static let monogramPalette: [Color] = [
        Color(red: 0.20, green: 0.45, blue: 0.85), // Royal Blue
        Color(red: 0.35, green: 0.30, blue: 0.75), // Indigo
        Color(red: 0.60, green: 0.25, blue: 0.70), // Purple
        Color(red: 0.80, green: 0.25, blue: 0.45), // Berry / Magenta
        Color(red: 0.85, green: 0.35, blue: 0.15), // Rust / Orange
        Color(red: 0.10, green: 0.55, blue: 0.45), // Teal
        Color(red: 0.20, green: 0.55, blue: 0.25), // Forest Green
        Color(red: 0.40, green: 0.50, blue: 0.60), // Slate
    ]

    /// Extracts a clean 1–2 character monogram from a merchant name (e.g. "JRSports" -> "JR", "MugUpCanada" -> "MU").
    public static func monogram(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let words = trimmed.components(separatedBy: CharacterSet.whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
            .filter { !$0.isEmpty }

        if words.count >= 2 {
            let first = words[0].prefix(1).uppercased()
            let second = words[1].prefix(1).uppercased()
            return "\(first)\(second)"
        } else if let singleWord = words.first {
            let uppers = singleWord.filter { $0.isUppercase }
            if uppers.count >= 2 {
                return String(uppers.prefix(2))
            }
            let clean = singleWord.filter { $0.isLetter || $0.isNumber }
            return String(clean.prefix(min(clean.count, 2))).uppercased()
        }
        return ""
    }

    /// Stable deterministic color selection using a djb2 hash.
    public static func deterministicColor(for name: String) -> Color {
        let hash = name.lowercased().utf8.reduce(5381) { ($0 << 5) &+ $0 &+ Int($1) }
        let index = abs(hash) % monogramPalette.count
        return monogramPalette[index]
    }

    private var brandConfig: (color: Color, icon: String, letter: String?) {
        Self.visualConfig(for: merchantName, category: category)
    }

    public static func visualConfig(for merchantName: String, category: String = "") -> (color: Color, icon: String, letter: String?) {
        let lower = merchantName.lowercased()
        if lower.contains("shoppers") {
            return (Color(red: 0.85, green: 0.15, blue: 0.18), "cross.fill", "S")
        } else if lower.contains("loblaw") || lower.contains("no frills") || lower.contains("superstore") || lower.contains("fortinos") || lower.contains("zehrs") || lower.contains("valu-mart") || lower.contains("valumart") || lower.contains("provigo") || lower.contains("maxi") || lower.contains("atlantic superstore") {
            return (Color(red: 0.95, green: 0.42, blue: 0.08), "cart.fill", "L")
        } else if lower.contains("cineplex") {
            return (Color(red: 0.08, green: 0.32, blue: 0.72), "film.fill", "C")
        } else if lower.contains("starbucks") {
            return (Color(red: 0.00, green: 0.40, blue: 0.24), "cup.and.saucer.fill", nil)
        } else if lower.contains("costco") {
            return (Color(red: 0.88, green: 0.12, blue: 0.15), "bag.fill", "C")
        } else if lower.contains("tim hortons") || lower.contains("tims") {
            return (Color(red: 0.78, green: 0.12, blue: 0.16), "cup.and.saucer.fill", nil)
        } else if lower.contains("walmart") {
            return (Color(red: 0.00, green: 0.44, blue: 0.86), "sparkle", nil)
        } else if lower.contains("mcdonald") {
            return (Color(red: 0.85, green: 0.12, blue: 0.12), "fork.knife", "M")
        } else if lower.contains("dollarama") {
            return (Color(red: 0.05, green: 0.50, blue: 0.25), "bag.fill", "D")
        } else if lower.contains("petro-canada") || lower.contains("petro canada") {
            return (Color(red: 0.88, green: 0.12, blue: 0.15), "fuelpump.fill", nil)
        } else if lower.contains("dairy queen") || lower.contains("dq") {
            return (Color(red: 0.85, green: 0.12, blue: 0.15), "cup.and.saucer.fill", "DQ")
        } else if lower.contains("subway") {
            return (Color(red: 0.00, green: 0.52, blue: 0.24), "fork.knife", "S")
        } else if lower.contains("wendy") {
            return (Color(red: 0.85, green: 0.10, blue: 0.18), "fork.knife", "W")
        } else if lower.contains("a&w") || lower.contains("a & w") || lower.contains("a and w") {
            return (Color(red: 0.88, green: 0.45, blue: 0.05), "fork.knife", "A&W")
        } else if lower.contains("bulk barn") {
            return (Color(red: 0.95, green: 0.72, blue: 0.05), "cart.fill", "BB")
        } else if lower.contains("winners") {
            return (Color(red: 0.75, green: 0.08, blue: 0.15), "bag.fill", "W")
        } else if lower.contains("london drugs") {
            return (Color(red: 0.08, green: 0.35, blue: 0.75), "cross.fill", "LD")
        } else if lower.contains("pizza pizza") {
            return (Color(red: 0.95, green: 0.40, blue: 0.05), "fork.knife", nil)
        } else if lower.contains("shell") {
            return (Color(red: 0.95, green: 0.75, blue: 0.08), "fuelpump.fill", nil)
        } else if lower.contains("esso") || lower.contains("mobil") {
            return (Color(red: 0.86, green: 0.14, blue: 0.14), "fuelpump.fill", nil)
        } else if lower.contains("amazon") {
            return (Color(red: 0.95, green: 0.60, blue: 0.05), "shippingbox.fill", nil)
        } else if lower.contains("apple") {
            return (Color.black, "apple.logo", nil)
        } else if lower.contains("lcbo") {
            return (Color(red: 0.45, green: 0.10, blue: 0.20), "wineglass.fill", nil)
        } else if lower.contains("canadian tire") {
            return (Color(red: 0.85, green: 0.15, blue: 0.15), "triangle.fill", nil)
        } else if lower.contains("metro") {
            return (Color(red: 0.88, green: 0.12, blue: 0.15), "cart.fill", "M")
        }

        // Bridge to merchant pack (contracts/merchant-pack.json) via MerchantRecognizer
        if let recognized = MerchantRecognizer.recognise(merchantName) {
            let effectiveCat = (category.isEmpty || category == "other") ? recognized.category : category
            if effectiveCat != "other" {
                let meta = CategoryVisuals.meta(for: effectiveCat)
                return (meta.color, meta.icon, nil)
            }
        }

        let meta = CategoryVisuals.meta(for: category)
        if category != "other" && meta.icon != "tag.fill" {
            return (meta.color, meta.icon, nil)
        }

        // For "other" / general merchandise, display dynamic monogram with stable color
        let initials = Self.monogram(for: merchantName)
        if !initials.isEmpty {
            let color = Self.deterministicColor(for: merchantName)
            return (color, "", initials)
        }

        return (meta.color, meta.icon, nil)
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(brandConfig.color)
                .frame(width: size, height: size)

            if let letter = brandConfig.letter, !letter.isEmpty {
                Text(letter)
                    .font(.system(size: size * (letter.count > 1 ? 0.38 : 0.52), weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                Image(systemName: brandConfig.icon)
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8)
        )
        .shadow(color: brandConfig.color.opacity(0.25), radius: 2, x: 0, y: 1)
    }
}
