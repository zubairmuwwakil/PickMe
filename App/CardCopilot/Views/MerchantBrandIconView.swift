import SwiftUI
import CardCopilotStore

/// Branded circular logo / avatar for merchants.
public struct MerchantBrandIconView: View {
    let merchantName: String
    let category: String
    var size: CGFloat = 24

    private var brandConfig: (color: Color, icon: String, letter: String?) {
        let lower = merchantName.lowercased()
        if lower.contains("shoppers") {
            return (Color(red: 0.85, green: 0.15, blue: 0.18), "cross.fill", "S")
        } else if lower.contains("loblaw") || lower.contains("no frills") || lower.contains("superstore") || lower.contains("fortinos") {
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
        } else {
            let meta = CategoryVisuals.meta(for: category)
            return (meta.color, meta.icon, nil)
        }
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(brandConfig.color)
                .frame(width: size, height: size)

            if let letter = brandConfig.letter {
                Text(letter)
                    .font(.system(size: size * 0.52, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
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
