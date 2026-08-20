import SwiftUI

/// Visual theme and branding metadata for cards in the user's wallet.
enum CardVisualTheme {
    struct CardStyle: Equatable {
        let cardId: String
        let shortName: String
        let issuer: String
        let network: CardNetwork
        let gradientColors: [Color]
        let textColor: Color
        let accentColor: Color
        let isDark: Bool
    }

    enum CardNetwork: String, Equatable {
        case amex = "AMEX"
        case visaInfinitePrivilege = "VISA INFINITE PRIVILEGE"
        case visaInfinite = "VISA INFINITE"
        case visa = "VISA"
        case mastercardWorldElite = "WORLD ELITE"
        case mastercard = "MASTERCARD"
        case prepaid = "PREPAID"
    }

    /// All card IDs that have explicit, dedicated branding themes defined.
    /// All card IDs that have explicit, dedicated branding themes defined in the canonical catalogue.
    static let definedCardIds: Set<String> = [
        "amex-cobalt",
        "amex-platinum",
        "amex-bonvoy",
        "amex-simplycash",
        "mbna-rewards-we",
        "scotia-momentum-vi-plus",
        "tangerine-moneyback-world",
        "triangle-we",
        "wealthsimple-vip",
        "rogers-red-we",
        "cryptocom-royal-indigo",
        "scotia-gold-amex",
        "td-aeroplan-visa-infinite",
        "rbc-avion-visa-infinite",
        "cibc-dividend-visa-infinite",
        "scotia-passport-visa-infinite-plus",
        "td-first-class-travel-visa-infinite",
        "bmo-eclipse-visa-infinite",
        "cibc-aventura-visa-infinite",
        "national-bank-world-elite",
        "pc-insiders-world-elite",
        "rbc-ion-plus-visa",
        "td-cash-back-visa-infinite",
        "bmo-ascend-world-elite",
        "westjet-rbc-world-elite",
        "amazon-ca-rewards-mastercard",
        "cibc-aventura-visa",
    ]

    static func style(for cardId: String) -> CardStyle {
        switch cardId {
        // MARK: - American Express Cards
        case "amex-cobalt":
            return CardStyle(
                cardId: cardId,
                shortName: "Cobalt",
                issuer: "American Express",
                network: .amex,
                gradientColors: [Color(red: 0.08, green: 0.22, blue: 0.45), Color(red: 0.12, green: 0.38, blue: 0.72)],
                textColor: .white,
                accentColor: Color(red: 0.45, green: 0.82, blue: 1.0),
                isDark: true
            )
        case "amex-platinum":
            return CardStyle(
                cardId: cardId,
                shortName: "Platinum",
                issuer: "American Express",
                network: .amex,
                gradientColors: [Color(red: 0.82, green: 0.85, blue: 0.88), Color(red: 0.58, green: 0.63, blue: 0.68)],
                textColor: Color(red: 0.12, green: 0.15, blue: 0.18),
                accentColor: Color(red: 0.2, green: 0.25, blue: 0.3),
                isDark: false
            )
        case "amex-bonvoy":
            return CardStyle(
                cardId: cardId,
                shortName: "Bonvoy",
                issuer: "Marriott / Amex",
                network: .amex,
                gradientColors: [Color(red: 0.11, green: 0.16, blue: 0.28), Color(red: 0.2, green: 0.14, blue: 0.32)],
                textColor: .white,
                accentColor: Color(red: 0.95, green: 0.78, blue: 0.45),
                isDark: true
            )
        case "amex-simplycash":
            return CardStyle(
                cardId: cardId,
                shortName: "SimplyCash",
                issuer: "American Express",
                network: .amex,
                gradientColors: [Color(red: 0.06, green: 0.26, blue: 0.52), Color(red: 0.02, green: 0.14, blue: 0.32)],
                textColor: .white,
                accentColor: Color(red: 0.75, green: 0.90, blue: 1.0),
                isDark: true
            )
        case "amex-simplycash-preferred":
            return CardStyle(
                cardId: cardId,
                shortName: "SimplyCash Preferred",
                issuer: "American Express",
                network: .amex,
                gradientColors: [Color(red: 0.04, green: 0.16, blue: 0.36), Color(red: 0.01, green: 0.08, blue: 0.20)],
                textColor: .white,
                accentColor: Color(red: 0.50, green: 0.82, blue: 1.0),
                isDark: true
            )
        case "scotia-gold-amex":
            return CardStyle(
                cardId: cardId,
                shortName: "Scotia Gold",
                issuer: "Scotiabank",
                network: .amex,
                gradientColors: [Color(red: 0.72, green: 0.56, blue: 0.22), Color(red: 0.42, green: 0.30, blue: 0.10)],
                textColor: .white,
                accentColor: Color(red: 1.0, green: 0.90, blue: 0.55),
                isDark: true
            )

        // MARK: - Visa Cards
        case "scotia-momentum-vi-plus":
            return CardStyle(
                cardId: cardId,
                shortName: "Momentum",
                issuer: "Scotiabank",
                network: .visaInfinite,
                gradientColors: [Color(red: 0.65, green: 0.08, blue: 0.12), Color(red: 0.38, green: 0.03, blue: 0.06)],
                textColor: .white,
                accentColor: Color(red: 1.0, green: 0.82, blue: 0.4),
                isDark: true
            )
        case "scotia-passport-visa-infinite-plus":
            return CardStyle(
                cardId: cardId,
                shortName: "Scotia Passport",
                issuer: "Scotiabank",
                network: .visaInfinite,
                gradientColors: [Color(red: 0.08, green: 0.26, blue: 0.35), Color(red: 0.03, green: 0.10, blue: 0.18)],
                textColor: .white,
                accentColor: Color(red: 0.35, green: 0.85, blue: 0.95),
                isDark: true
            )
        case "td-aeroplan-visa-infinite":
            return CardStyle(
                cardId: cardId,
                shortName: "TD Aeroplan",
                issuer: "TD",
                network: .visaInfinite,
                gradientColors: [Color(red: 0.08, green: 0.22, blue: 0.15), Color(red: 0.03, green: 0.08, blue: 0.05)],
                textColor: .white,
                accentColor: Color(red: 0.25, green: 0.85, blue: 0.42),
                isDark: true
            )
        case "td-first-class-travel-visa-infinite":
            return CardStyle(
                cardId: cardId,
                shortName: "TD First Class",
                issuer: "TD",
                network: .visaInfinite,
                gradientColors: [Color(red: 0.04, green: 0.30, blue: 0.18), Color(red: 0.01, green: 0.12, blue: 0.07)],
                textColor: .white,
                accentColor: Color(red: 1.0, green: 0.84, blue: 0.40),
                isDark: true
            )
        case "td-cash-back-visa-infinite":
            return CardStyle(
                cardId: cardId,
                shortName: "TD Cash Back",
                issuer: "TD",
                network: .visaInfinite,
                gradientColors: [Color(red: 0.10, green: 0.24, blue: 0.18), Color(red: 0.04, green: 0.10, blue: 0.08)],
                textColor: .white,
                accentColor: Color(red: 0.30, green: 0.90, blue: 0.50),
                isDark: true
            )
        case "rbc-avion-visa-infinite":
            return CardStyle(
                cardId: cardId,
                shortName: "RBC Avion",
                issuer: "RBC",
                network: .visaInfinite,
                gradientColors: [Color(red: 0.06, green: 0.20, blue: 0.48), Color(red: 0.02, green: 0.08, blue: 0.25)],
                textColor: .white,
                accentColor: Color(red: 1.0, green: 0.82, blue: 0.15),
                isDark: true
            )
        case "rbc-ion-plus-visa":
            return CardStyle(
                cardId: cardId,
                shortName: "RBC ION+",
                issuer: "RBC",
                network: .visa,
                gradientColors: [Color(red: 0.72, green: 0.10, blue: 0.38), Color(red: 0.38, green: 0.04, blue: 0.20)],
                textColor: .white,
                accentColor: Color(red: 1.0, green: 0.45, blue: 0.60),
                isDark: true
            )
        case "cibc-dividend-visa-infinite":
            return CardStyle(
                cardId: cardId,
                shortName: "CIBC Dividend",
                issuer: "CIBC",
                network: .visaInfinite,
                gradientColors: [Color(red: 0.58, green: 0.06, blue: 0.15), Color(red: 0.28, green: 0.02, blue: 0.08)],
                textColor: .white,
                accentColor: Color(red: 0.95, green: 0.75, blue: 0.80),
                isDark: true
            )
        case "cibc-aventura-visa":
            return CardStyle(
                cardId: cardId,
                shortName: "CIBC Aventura",
                issuer: "CIBC",
                network: .visa,
                gradientColors: [Color(red: 0.45, green: 0.08, blue: 0.16), Color(red: 0.10, green: 0.12, blue: 0.28)],
                textColor: .white,
                accentColor: Color(red: 0.85, green: 0.90, blue: 0.98),
                isDark: true
            )
        case "cibc-aventura-visa-infinite":
            return CardStyle(
                cardId: cardId,
                shortName: "CIBC Aventura VI",
                issuer: "CIBC",
                network: .visaInfinite,
                gradientColors: [Color(red: 0.52, green: 0.05, blue: 0.14), Color(red: 0.15, green: 0.05, blue: 0.18)],
                textColor: .white,
                accentColor: Color(red: 1.0, green: 0.82, blue: 0.45),
                isDark: true
            )
        case "bmo-eclipse-visa-infinite":
            return CardStyle(
                cardId: cardId,
                shortName: "BMO eclipse",
                issuer: "BMO",
                network: .visaInfinite,
                gradientColors: [Color(red: 0.14, green: 0.12, blue: 0.35), Color(red: 0.06, green: 0.04, blue: 0.18)],
                textColor: .white,
                accentColor: Color(red: 0.75, green: 0.55, blue: 1.0),
                isDark: true
            )
        case "wealthsimple-vip":
            return CardStyle(
                cardId: cardId,
                shortName: "Wealthsimple VIP",
                issuer: "Wealthsimple",
                network: .visaInfinitePrivilege,
                gradientColors: [Color(red: 0.12, green: 0.13, blue: 0.15), Color(red: 0.04, green: 0.04, blue: 0.05)],
                textColor: .white,
                accentColor: Color(red: 0.75, green: 0.78, blue: 0.82),
                isDark: true
            )
        case "cryptocom-royal-indigo":
            return CardStyle(
                cardId: cardId,
                shortName: "Royal Indigo",
                issuer: "Crypto.com",
                network: .prepaid,
                gradientColors: [Color(red: 0.18, green: 0.14, blue: 0.44), Color(red: 0.08, green: 0.06, blue: 0.22)],
                textColor: .white,
                accentColor: Color(red: 0.7, green: 0.65, blue: 0.95),
                isDark: true
            )
        case "simplii-cash-back-visa":
            return CardStyle(
                cardId: cardId,
                shortName: "Simplii Cash Back",
                issuer: "Simplii Financial",
                network: .visa,
                gradientColors: [Color(red: 0.82, green: 0.12, blue: 0.36), Color(red: 0.50, green: 0.04, blue: 0.22)],
                textColor: .white,
                accentColor: Color(red: 1.0, green: 0.85, blue: 0.90),
                isDark: true
            )
        case "home-trust-preferred-visa":
            return CardStyle(
                cardId: cardId,
                shortName: "Home Trust Preferred",
                issuer: "Home Trust",
                network: .visa,
                gradientColors: [Color(red: 0.08, green: 0.16, blue: 0.32), Color(red: 0.04, green: 0.08, blue: 0.18)],
                textColor: .white,
                accentColor: Color(red: 0.95, green: 0.78, blue: 0.35),
                isDark: true
            )

        // MARK: - Mastercard Cards
        case "mbna-rewards-we":
            return CardStyle(
                cardId: cardId,
                shortName: "MBNA Rewards",
                issuer: "MBNA / TD",
                network: .mastercardWorldElite,
                gradientColors: [Color(red: 0.15, green: 0.18, blue: 0.24), Color(red: 0.08, green: 0.35, blue: 0.48)],
                textColor: .white,
                accentColor: Color(red: 0.3, green: 0.85, blue: 0.95),
                isDark: true
            )
        case "mbna-smart-cash-world":
            return CardStyle(
                cardId: cardId,
                shortName: "Smart Cash World",
                issuer: "MBNA / TD",
                network: .mastercard,
                gradientColors: [Color(red: 0.30, green: 0.34, blue: 0.38), Color(red: 0.16, green: 0.18, blue: 0.22)],
                textColor: .white,
                accentColor: Color(red: 0.25, green: 0.85, blue: 0.45),
                isDark: true
            )
        case "tangerine-moneyback-world":
            return CardStyle(
                cardId: cardId,
                shortName: "Money-Back",
                issuer: "Tangerine",
                network: .mastercard,
                gradientColors: [Color(red: 0.95, green: 0.45, blue: 0.05), Color(red: 0.8, green: 0.3, blue: 0.02)],
                textColor: .white,
                accentColor: .white,
                isDark: true
            )
        case "triangle-we":
            return CardStyle(
                cardId: cardId,
                shortName: "Triangle",
                issuer: "Canadian Tire",
                network: .mastercardWorldElite,
                gradientColors: [Color(red: 0.78, green: 0.12, blue: 0.14), Color(red: 0.45, green: 0.08, blue: 0.1)],
                textColor: .white,
                accentColor: Color(red: 0.95, green: 0.9, blue: 0.9),
                isDark: true
            )
        case "rogers-red-we":
            return CardStyle(
                cardId: cardId,
                shortName: "Rogers Red",
                issuer: "Rogers Bank",
                network: .mastercardWorldElite,
                gradientColors: [Color(red: 0.85, green: 0.15, blue: 0.15), Color(red: 0.6, green: 0.08, blue: 0.08)],
                textColor: .white,
                accentColor: .white,
                isDark: true
            )
        case "national-bank-world-elite":
            return CardStyle(
                cardId: cardId,
                shortName: "NBC World Elite",
                issuer: "National Bank",
                network: .mastercardWorldElite,
                gradientColors: [Color(red: 0.76, green: 0.07, blue: 0.18), Color(red: 0.38, green: 0.00, blue: 0.06)],
                textColor: .white,
                accentColor: .white,
                isDark: true
            )
        case "pc-insiders-world-elite":
            return CardStyle(
                cardId: cardId,
                shortName: "PC Insiders WE",
                issuer: "PC Financial",
                network: .mastercardWorldElite,
                gradientColors: [Color(red: 0.12, green: 0.12, blue: 0.14), Color(red: 0.05, green: 0.05, blue: 0.06)],
                textColor: .white,
                accentColor: Color(red: 0.90, green: 0.12, blue: 0.15),
                isDark: true
            )
        case "bmo-ascend-world-elite":
            return CardStyle(
                cardId: cardId,
                shortName: "BMO Ascend WE",
                issuer: "BMO",
                network: .mastercardWorldElite,
                gradientColors: [Color(red: 0.04, green: 0.22, blue: 0.45), Color(red: 0.02, green: 0.08, blue: 0.20)],
                textColor: .white,
                accentColor: Color(red: 0.45, green: 0.85, blue: 1.0),
                isDark: true
            )
        case "bmo-cashback-world-elite":
            return CardStyle(
                cardId: cardId,
                shortName: "BMO CashBack WE",
                issuer: "BMO",
                network: .mastercardWorldElite,
                gradientColors: [Color(red: 0.05, green: 0.25, blue: 0.50), Color(red: 0.02, green: 0.10, blue: 0.24)],
                textColor: .white,
                accentColor: Color(red: 0.90, green: 0.15, blue: 0.15),
                isDark: true
            )
        case "westjet-rbc-world-elite":
            return CardStyle(
                cardId: cardId,
                shortName: "WestJet RBC WE",
                issuer: "RBC",
                network: .mastercardWorldElite,
                gradientColors: [Color(red: 0.00, green: 0.35, blue: 0.45), Color(red: 0.01, green: 0.12, blue: 0.22)],
                textColor: .white,
                accentColor: Color(red: 0.20, green: 0.85, blue: 0.85),
                isDark: true
            )
        case "rbc-cashback-preferred-we":
            return CardStyle(
                cardId: cardId,
                shortName: "RBC Cash Back WE",
                issuer: "RBC",
                network: .mastercardWorldElite,
                gradientColors: [Color(red: 0.08, green: 0.18, blue: 0.35), Color(red: 0.03, green: 0.08, blue: 0.18)],
                textColor: .white,
                accentColor: Color(red: 1.0, green: 0.80, blue: 0.20),
                isDark: true
            )
        case "amazon-ca-rewards-mastercard":
            return CardStyle(
                cardId: cardId,
                shortName: "Amazon.ca Rewards",
                issuer: "MBNA / TD",
                network: .mastercard,
                gradientColors: [Color(red: 0.14, green: 0.18, blue: 0.22), Color(red: 0.08, green: 0.10, blue: 0.14)],
                textColor: .white,
                accentColor: Color(red: 1.0, green: 0.60, blue: 0.0),
                isDark: true
            )

        // MARK: - Smart Fallback for Custom or Unstyled Cards
        default:
            let lower = cardId.lowercased()
            let inferredNetwork: CardNetwork
            if lower.contains("amex") || lower.hasPrefix("american-express") {
                inferredNetwork = .amex
            } else if lower.contains("vip") || lower.contains("privilege") {
                inferredNetwork = .visaInfinitePrivilege
            } else if lower.contains("infinite") || lower.contains("-vi") {
                inferredNetwork = .visaInfinite
            } else if lower.contains("visa") {
                inferredNetwork = .visa
            } else if lower.contains("world-elite") || lower.contains("-we") {
                inferredNetwork = .mastercardWorldElite
            } else if lower.contains("mastercard") || lower.contains("-mc") {
                inferredNetwork = .mastercard
            } else if lower.contains("prepaid") {
                inferredNetwork = .prepaid
            } else {
                inferredNetwork = .visa
            }

            let inferredIssuer: String
            if lower.contains("amex") || lower.contains("american-express") {
                inferredIssuer = "American Express"
            } else if lower.contains("td-") || lower.contains("td") {
                inferredIssuer = "TD"
            } else if lower.contains("scotia") {
                inferredIssuer = "Scotiabank"
            } else if lower.contains("cibc") {
                inferredIssuer = "CIBC"
            } else if lower.contains("rbc") {
                inferredIssuer = "RBC"
            } else if lower.contains("bmo") {
                inferredIssuer = "BMO"
            } else if lower.contains("tangerine") {
                inferredIssuer = "Tangerine"
            } else if lower.contains("wealthsimple") {
                inferredIssuer = "Wealthsimple"
            } else {
                inferredIssuer = "Card"
            }

            let cleanedName = cardId
                .replacingOccurrences(of: "-", with: " ")
                .capitalized

            return CardStyle(
                cardId: cardId,
                shortName: cleanedName,
                issuer: inferredIssuer,
                network: inferredNetwork,
                gradientColors: [Color(red: 0.25, green: 0.3, blue: 0.38), Color(red: 0.15, green: 0.18, blue: 0.24)],
                textColor: .white,
                accentColor: .white,
                isDark: true
            )
        }
    }
}

/// Helper for category-related icons, colors, and human formatting.
enum CategoryVisuals {
    struct Meta {
        let icon: String
        let color: Color
        let displayName: String
    }

    static func meta(for category: String) -> Meta {
        switch category.lowercased() {
        case "grocery", "groceries":
            return Meta(icon: "cart.fill", color: .green, displayName: "Grocery")
        case "dining", "restaurants", "restaurant", "fooddelivery":
            return Meta(icon: "fork.knife", color: .orange, displayName: "Dining & Food")
        case "gasstation", "gas":
            return Meta(icon: "fuelpump.fill", color: .blue, displayName: "Gas Station")
        case "transit":
            return Meta(icon: "tram.fill", color: .teal, displayName: "Transit & Travel")
        case "flight", "flights", "travel":
            return Meta(icon: "airplane", color: .indigo, displayName: "Travel")
        case "hotel", "lodging", "hotels":
            return Meta(icon: "bed.double.fill", color: .purple, displayName: "Hotel & Lodging")
        case "streaming":
            return Meta(icon: "play.tv.fill", color: .red, displayName: "Streaming")
        case "carrental":
            return Meta(icon: "car.fill", color: .cyan, displayName: "Rental Car")
        case "electronics":
            return Meta(icon: "laptopcomputer", color: .blue, displayName: "Electronics")
        case "mobiledevice":
            return Meta(icon: "iphone", color: .indigo, displayName: "Mobile Device")
        case "homeimprovement":
            return Meta(icon: "hammer.fill", color: .brown, displayName: "Home Improvement")
        case "drugstore", "pharmacy":
            return Meta(icon: "cross.case.fill", color: .mint, displayName: "Pharmacy")
        case "recurring", "recurringbills":
            return Meta(icon: "arrow.triangle.2.circlepath", color: .pink, displayName: "Recurring Bills")
        case "ctfamily":
            return Meta(icon: "triangle.fill", color: .red, displayName: "Canadian Tire Family")
        case "wholesaleclub":
            return Meta(icon: "building.2.fill", color: .blue, displayName: "Wholesale Club")
        case "digitalmedia":
            return Meta(icon: "play.square.fill", color: .purple, displayName: "Digital Media")
        case "evcharging":
            return Meta(icon: "bolt.car.fill", color: .green, displayName: "EV Charging")
        case "entertainment":
            return Meta(icon: "ticket.fill", color: .pink, displayName: "Entertainment")
        case "householdutilities", "utilities":
            return Meta(icon: "lightbulb.fill", color: .yellow, displayName: "Household Utilities")
        case "marriottdirect":
            return Meta(icon: "crown.fill", color: .brown, displayName: "Marriott Direct")
        case "memberships":
            return Meta(icon: "person.2.fill", color: .teal, displayName: "Memberships")
        case "other", "general":
            return Meta(icon: "tag.fill", color: .gray, displayName: "General Merchandise")
        case "fitness":
            return Meta(icon: "figure.run", color: .mint, displayName: "Fitness & Gym")
        default:
            return Meta(icon: "bag.fill", color: .secondary, displayName: "General")
        }
    }

    static func humanizePoiCategory(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let stripped = raw.replacingOccurrences(of: "MKPOICategory", with: "")
        switch stripped {
        case "FoodMarket": return "Supermarket & Grocery"
        case "Restaurant": return "Restaurant"
        case "Cafe": return "Coffee & Cafe"
        case "GasStation": return "Gas Station"
        case "Bakery": return "Bakery"
        case "Brewery": return "Brewery"
        case "Winery": return "Winery"
        case "Store": return "Retail Store"
        case "Pharmacy": return "Pharmacy"
        case "EVCharger": return "EV Charging"
        case "Hotel": return "Hotel"
        case "Airport": return "Airport"
        case "CarRental": return "Car Rental"
        case "FitnessCenter": return "Fitness & Gym"
        case "MovieTheater": return "Movie Theater"
        case "Nightlife": return "Nightlife & Bar"
        case "Park": return "Park"
        case "PublicTransport": return "Public Transit"
        default:
            return stripped
        }
    }

    static func relativeTime(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = max(1, Int(seconds / 60))
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else if seconds < 86400 * 2 {
            return "Yesterday"
        } else if seconds < 86400 * 7 {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
