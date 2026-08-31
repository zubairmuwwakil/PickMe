import SwiftUI
import CardCopilotEngine

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
        case discover = "DISCOVER"
        case privateLabel = "STORE CARD"
        case prepaid = "PREPAID"
    }

    /// All card IDs that have an explicit, dedicated style in `styles`.
    ///
    /// Derived from `styles.keys`, so it can never drift from the styles it describes — unlike a
    /// switch statement's case labels, which cannot be enumerated and had to be copied here by
    /// hand. That copy is what let five cards go missing and let `simplii-cash-back-visa` sit
    /// keyed to a cardId the catalogue has never contained. `CardVisualThemeTests` still checks
    /// this set against the live catalogue; it just can't drift from `styles` anymore.
    static let definedCardIds: Set<String> = Set(styles.keys)

    static let styles: [String: CardStyle] = [
        // MARK: - American Express Cards
        "amex-cobalt": CardStyle(
            cardId: "amex-cobalt",
            shortName: "Cobalt",
            issuer: "American Express",
            network: .amex,
            gradientColors: [Color(red: 0.08, green: 0.22, blue: 0.45), Color(red: 0.12, green: 0.38, blue: 0.72)],
            textColor: .white,
            accentColor: Color(red: 0.45, green: 0.82, blue: 1.0),
            isDark: true
        ),
        "amex-platinum": CardStyle(
            cardId: "amex-platinum",
            shortName: "Platinum",
            issuer: "American Express",
            network: .amex,
            gradientColors: [Color(red: 0.82, green: 0.85, blue: 0.88), Color(red: 0.58, green: 0.63, blue: 0.68)],
            textColor: Color(red: 0.12, green: 0.15, blue: 0.18),
            accentColor: Color(red: 0.2, green: 0.25, blue: 0.3),
            isDark: false
        ),
        "amex-bonvoy": CardStyle(
            cardId: "amex-bonvoy",
            shortName: "Bonvoy",
            issuer: "Marriott / Amex",
            network: .amex,
            gradientColors: [Color(red: 0.11, green: 0.16, blue: 0.28), Color(red: 0.2, green: 0.14, blue: 0.32)],
            textColor: .white,
            accentColor: Color(red: 0.95, green: 0.78, blue: 0.45),
            isDark: true
        ),
        "amex-simplycash": CardStyle(
            cardId: "amex-simplycash",
            shortName: "SimplyCash",
            issuer: "American Express",
            network: .amex,
            gradientColors: [Color(red: 0.06, green: 0.26, blue: 0.52), Color(red: 0.02, green: 0.14, blue: 0.32)],
            textColor: .white,
            accentColor: Color(red: 0.75, green: 0.90, blue: 1.0),
            isDark: true
        ),
        "amex-simplycash-preferred": CardStyle(
            cardId: "amex-simplycash-preferred",
            shortName: "SimplyCash Preferred",
            issuer: "American Express",
            network: .amex,
            gradientColors: [Color(red: 0.04, green: 0.16, blue: 0.36), Color(red: 0.01, green: 0.08, blue: 0.20)],
            textColor: .white,
            accentColor: Color(red: 0.50, green: 0.82, blue: 1.0),
            isDark: true
        ),
        "scotia-gold-amex": CardStyle(
            cardId: "scotia-gold-amex",
            shortName: "Scotia Gold",
            issuer: "Scotiabank",
            network: .amex,
            gradientColors: [Color(red: 0.72, green: 0.56, blue: 0.22), Color(red: 0.42, green: 0.30, blue: 0.10)],
            textColor: .white,
            accentColor: Color(red: 1.0, green: 0.90, blue: 0.55),
            isDark: true
        ),
        // Light champagne, dark text — the same treatment as amex-platinum rather than
        // scotia-gold-amex's dark gold. Two "gold" cards that read alike at a glance
        // defeat the point of card art in a wallet chosen at a till.
        "amex-gold-rewards": CardStyle(
            cardId: "amex-gold-rewards",
            shortName: "Gold Rewards",
            issuer: "American Express",
            network: .amex,
            gradientColors: [Color(red: 0.88, green: 0.76, blue: 0.48), Color(red: 0.70, green: 0.56, blue: 0.28)],
            textColor: Color(red: 0.18, green: 0.13, blue: 0.04),
            accentColor: Color(red: 0.34, green: 0.24, blue: 0.06),
            isDark: false
        ),
        "amex-aeroplan-reserve": CardStyle(
            cardId: "amex-aeroplan-reserve",
            shortName: "Aeroplan Reserve",
            issuer: "Air Canada / Amex",
            network: .amex,
            gradientColors: [Color(red: 0.10, green: 0.13, blue: 0.20), Color(red: 0.03, green: 0.04, blue: 0.08)],
            textColor: .white,
            accentColor: Color(red: 0.92, green: 0.24, blue: 0.26),
            isDark: true
        ),

        // MARK: - Visa Cards
        "scotia-momentum-vi-plus": CardStyle(
            cardId: "scotia-momentum-vi-plus",
            shortName: "Momentum",
            issuer: "Scotiabank",
            network: .visaInfinite,
            gradientColors: [Color(red: 0.65, green: 0.08, blue: 0.12), Color(red: 0.38, green: 0.03, blue: 0.06)],
            textColor: .white,
            accentColor: Color(red: 1.0, green: 0.82, blue: 0.4),
            isDark: true
        ),
        "scotia-passport-visa-infinite-plus": CardStyle(
            cardId: "scotia-passport-visa-infinite-plus",
            shortName: "Scotia Passport",
            issuer: "Scotiabank",
            network: .visaInfinite,
            gradientColors: [Color(red: 0.08, green: 0.26, blue: 0.35), Color(red: 0.03, green: 0.10, blue: 0.18)],
            textColor: .white,
            accentColor: Color(red: 0.35, green: 0.85, blue: 0.95),
            isDark: true
        ),
        "td-aeroplan-visa-infinite": CardStyle(
            cardId: "td-aeroplan-visa-infinite",
            shortName: "TD Aeroplan",
            issuer: "TD",
            network: .visaInfinite,
            gradientColors: [Color(red: 0.08, green: 0.22, blue: 0.15), Color(red: 0.03, green: 0.08, blue: 0.05)],
            textColor: .white,
            accentColor: Color(red: 0.25, green: 0.85, blue: 0.42),
            isDark: true
        ),
        "td-first-class-travel-visa-infinite": CardStyle(
            cardId: "td-first-class-travel-visa-infinite",
            shortName: "TD First Class",
            issuer: "TD",
            network: .visaInfinite,
            gradientColors: [Color(red: 0.04, green: 0.30, blue: 0.18), Color(red: 0.01, green: 0.12, blue: 0.07)],
            textColor: .white,
            accentColor: Color(red: 1.0, green: 0.84, blue: 0.40),
            isDark: true
        ),
        "td-cash-back-visa-infinite": CardStyle(
            cardId: "td-cash-back-visa-infinite",
            shortName: "TD Cash Back",
            issuer: "TD",
            network: .visaInfinite,
            gradientColors: [Color(red: 0.10, green: 0.24, blue: 0.18), Color(red: 0.04, green: 0.10, blue: 0.08)],
            textColor: .white,
            accentColor: Color(red: 0.30, green: 0.90, blue: 0.50),
            isDark: true
        ),
        "rbc-avion-visa-infinite": CardStyle(
            cardId: "rbc-avion-visa-infinite",
            shortName: "RBC Avion",
            issuer: "RBC",
            network: .visaInfinite,
            gradientColors: [Color(red: 0.06, green: 0.20, blue: 0.48), Color(red: 0.02, green: 0.08, blue: 0.25)],
            textColor: .white,
            accentColor: Color(red: 1.0, green: 0.82, blue: 0.15),
            isDark: true
        ),
        "rbc-ion-plus-visa": CardStyle(
            cardId: "rbc-ion-plus-visa",
            shortName: "RBC ION+",
            issuer: "RBC",
            network: .visa,
            gradientColors: [Color(red: 0.72, green: 0.10, blue: 0.38), Color(red: 0.38, green: 0.04, blue: 0.20)],
            textColor: .white,
            accentColor: Color(red: 1.0, green: 0.45, blue: 0.60),
            isDark: true
        ),
        "cibc-dividend-visa-infinite": CardStyle(
            cardId: "cibc-dividend-visa-infinite",
            shortName: "CIBC Dividend",
            issuer: "CIBC",
            network: .visaInfinite,
            gradientColors: [Color(red: 0.58, green: 0.06, blue: 0.15), Color(red: 0.28, green: 0.02, blue: 0.08)],
            textColor: .white,
            accentColor: Color(red: 0.95, green: 0.75, blue: 0.80),
            isDark: true
        ),
        "cibc-aventura-visa": CardStyle(
            cardId: "cibc-aventura-visa",
            shortName: "CIBC Aventura",
            issuer: "CIBC",
            network: .visa,
            gradientColors: [Color(red: 0.45, green: 0.08, blue: 0.16), Color(red: 0.10, green: 0.12, blue: 0.28)],
            textColor: .white,
            accentColor: Color(red: 0.85, green: 0.90, blue: 0.98),
            isDark: true
        ),
        "cibc-aventura-visa-infinite": CardStyle(
            cardId: "cibc-aventura-visa-infinite",
            shortName: "CIBC Aventura VI",
            issuer: "CIBC",
            network: .visaInfinite,
            gradientColors: [Color(red: 0.52, green: 0.05, blue: 0.14), Color(red: 0.15, green: 0.05, blue: 0.18)],
            textColor: .white,
            accentColor: Color(red: 1.0, green: 0.82, blue: 0.45),
            isDark: true
        ),
        "bmo-eclipse-visa-infinite": CardStyle(
            cardId: "bmo-eclipse-visa-infinite",
            shortName: "BMO eclipse",
            issuer: "BMO",
            network: .visaInfinite,
            gradientColors: [Color(red: 0.14, green: 0.12, blue: 0.35), Color(red: 0.06, green: 0.04, blue: 0.18)],
            textColor: .white,
            accentColor: Color(red: 0.75, green: 0.55, blue: 1.0),
            isDark: true
        ),
        "wealthsimple-vip": CardStyle(
            cardId: "wealthsimple-vip",
            shortName: "Wealthsimple VIP",
            issuer: "Wealthsimple",
            network: .visaInfinitePrivilege,
            gradientColors: [Color(red: 0.12, green: 0.13, blue: 0.15), Color(red: 0.04, green: 0.04, blue: 0.05)],
            textColor: .white,
            accentColor: Color(red: 0.75, green: 0.78, blue: 0.82),
            isDark: true
        ),
        "cryptocom-royal-indigo": CardStyle(
            cardId: "cryptocom-royal-indigo",
            shortName: "Royal Indigo",
            issuer: "Crypto.com",
            network: .prepaid,
            gradientColors: [Color(red: 0.18, green: 0.14, blue: 0.44), Color(red: 0.08, green: 0.06, blue: 0.22)],
            textColor: .white,
            accentColor: Color(red: 0.7, green: 0.65, blue: 0.95),
            isDark: true
        ),
        // Was keyed "simplii-cash-back-visa", which is not a cardId the catalogue has ever
        // contained — so this style was unreachable and the card rendered as a generic fallback.
        "simplii-cashback-visa": CardStyle(
            cardId: "simplii-cashback-visa",
            shortName: "Simplii Cash Back",
            issuer: "Simplii Financial",
            network: .visa,
            gradientColors: [Color(red: 0.82, green: 0.12, blue: 0.36), Color(red: 0.50, green: 0.04, blue: 0.22)],
            textColor: .white,
            accentColor: Color(red: 1.0, green: 0.85, blue: 0.90),
            isDark: true
        ),
        "home-trust-preferred-visa": CardStyle(
            cardId: "home-trust-preferred-visa",
            shortName: "Home Trust Preferred",
            issuer: "Home Trust",
            network: .visa,
            gradientColors: [Color(red: 0.08, green: 0.16, blue: 0.32), Color(red: 0.04, green: 0.08, blue: 0.18)],
            textColor: .white,
            accentColor: Color(red: 0.95, green: 0.78, blue: 0.35),
            isDark: true
        ),
        // Deliberately darker than td-aeroplan-visa-infinite's green, with a gold rather
        // than green accent: an owner can hold both, and the pick is worthless if the two
        // are indistinguishable in the half-second before the photo loads.
        "td-aeroplan-visa-infinite-privilege": CardStyle(
            cardId: "td-aeroplan-visa-infinite-privilege",
            shortName: "TD Aeroplan VIP",
            issuer: "TD",
            network: .visaInfinitePrivilege,
            gradientColors: [Color(red: 0.05, green: 0.14, blue: 0.10), Color(red: 0.01, green: 0.04, blue: 0.03)],
            textColor: .white,
            accentColor: Color(red: 0.95, green: 0.82, blue: 0.50),
            isDark: true
        ),
        // Darker than cibc-dividend-visa-infinite's crimson, for the same reason.
        "cibc-aeroplan-visa-infinite-privilege": CardStyle(
            cardId: "cibc-aeroplan-visa-infinite-privilege",
            shortName: "CIBC Aeroplan VIP",
            issuer: "CIBC",
            network: .visaInfinitePrivilege,
            gradientColors: [Color(red: 0.32, green: 0.04, blue: 0.10), Color(red: 0.10, green: 0.01, blue: 0.03)],
            textColor: .white,
            accentColor: Color(red: 1.0, green: 0.45, blue: 0.45),
            isDark: true
        ),

        // MARK: - Mastercard Cards
        "mbna-rewards-we": CardStyle(
            cardId: "mbna-rewards-we",
            shortName: "MBNA Rewards",
            issuer: "MBNA / TD",
            network: .mastercardWorldElite,
            gradientColors: [Color(red: 0.15, green: 0.18, blue: 0.24), Color(red: 0.08, green: 0.35, blue: 0.48)],
            textColor: .white,
            accentColor: Color(red: 0.3, green: 0.85, blue: 0.95),
            isDark: true
        ),
        "mbna-smart-cash-world": CardStyle(
            cardId: "mbna-smart-cash-world",
            shortName: "Smart Cash World",
            issuer: "MBNA / TD",
            network: .mastercard,
            gradientColors: [Color(red: 0.30, green: 0.34, blue: 0.38), Color(red: 0.16, green: 0.18, blue: 0.22)],
            textColor: .white,
            accentColor: Color(red: 0.25, green: 0.85, blue: 0.45),
            isDark: true
        ),
        "tangerine-moneyback-world": CardStyle(
            cardId: "tangerine-moneyback-world",
            shortName: "Money-Back",
            issuer: "Tangerine",
            network: .mastercard,
            gradientColors: [Color(red: 0.95, green: 0.45, blue: 0.05), Color(red: 0.8, green: 0.3, blue: 0.02)],
            textColor: .white,
            accentColor: .white,
            isDark: true
        ),
        "triangle-we": CardStyle(
            cardId: "triangle-we",
            shortName: "Triangle",
            issuer: "Canadian Tire",
            network: .mastercardWorldElite,
            gradientColors: [Color(red: 0.78, green: 0.12, blue: 0.14), Color(red: 0.45, green: 0.08, blue: 0.1)],
            textColor: .white,
            accentColor: Color(red: 0.95, green: 0.9, blue: 0.9),
            isDark: true
        ),
        "rogers-red-we": CardStyle(
            cardId: "rogers-red-we",
            shortName: "Rogers Red",
            issuer: "Rogers Bank",
            network: .mastercardWorldElite,
            gradientColors: [Color(red: 0.85, green: 0.15, blue: 0.15), Color(red: 0.6, green: 0.08, blue: 0.08)],
            textColor: .white,
            accentColor: .white,
            isDark: true
        ),
        "national-bank-world-elite": CardStyle(
            cardId: "national-bank-world-elite",
            shortName: "NBC World Elite",
            issuer: "National Bank",
            network: .mastercardWorldElite,
            gradientColors: [Color(red: 0.76, green: 0.07, blue: 0.18), Color(red: 0.38, green: 0.00, blue: 0.06)],
            textColor: .white,
            accentColor: .white,
            isDark: true
        ),
        "pc-insiders-world-elite": CardStyle(
            cardId: "pc-insiders-world-elite",
            shortName: "PC Insiders WE",
            issuer: "PC Financial",
            network: .mastercardWorldElite,
            gradientColors: [Color(red: 0.12, green: 0.12, blue: 0.14), Color(red: 0.05, green: 0.05, blue: 0.06)],
            textColor: .white,
            accentColor: Color(red: 0.90, green: 0.12, blue: 0.15),
            isDark: true
        ),
        "bmo-ascend-world-elite": CardStyle(
            cardId: "bmo-ascend-world-elite",
            shortName: "BMO Ascend WE",
            issuer: "BMO",
            network: .mastercardWorldElite,
            gradientColors: [Color(red: 0.04, green: 0.22, blue: 0.45), Color(red: 0.02, green: 0.08, blue: 0.20)],
            textColor: .white,
            accentColor: Color(red: 0.45, green: 0.85, blue: 1.0),
            isDark: true
        ),
        "bmo-cashback-world-elite": CardStyle(
            cardId: "bmo-cashback-world-elite",
            shortName: "BMO CashBack WE",
            issuer: "BMO",
            network: .mastercardWorldElite,
            gradientColors: [Color(red: 0.05, green: 0.25, blue: 0.50), Color(red: 0.02, green: 0.10, blue: 0.24)],
            textColor: .white,
            accentColor: Color(red: 0.90, green: 0.15, blue: 0.15),
            isDark: true
        ),
        "westjet-rbc-world-elite": CardStyle(
            cardId: "westjet-rbc-world-elite",
            shortName: "WestJet RBC WE",
            issuer: "RBC",
            network: .mastercardWorldElite,
            gradientColors: [Color(red: 0.00, green: 0.35, blue: 0.45), Color(red: 0.01, green: 0.12, blue: 0.22)],
            textColor: .white,
            accentColor: Color(red: 0.20, green: 0.85, blue: 0.85),
            isDark: true
        ),
        "rbc-cashback-preferred-we": CardStyle(
            cardId: "rbc-cashback-preferred-we",
            shortName: "RBC Cash Back WE",
            issuer: "RBC",
            network: .mastercardWorldElite,
            gradientColors: [Color(red: 0.08, green: 0.18, blue: 0.35), Color(red: 0.03, green: 0.08, blue: 0.18)],
            textColor: .white,
            accentColor: Color(red: 1.0, green: 0.80, blue: 0.20),
            isDark: true
        ),
        "amazon-ca-rewards-mastercard": CardStyle(
            cardId: "amazon-ca-rewards-mastercard",
            shortName: "Amazon.ca Rewards",
            issuer: "MBNA / TD",
            network: .mastercard,
            gradientColors: [Color(red: 0.14, green: 0.18, blue: 0.22), Color(red: 0.08, green: 0.10, blue: 0.14)],
            textColor: .white,
            accentColor: Color(red: 1.0, green: 0.60, blue: 0.0),
            isDark: true
        ),
        "desjardins-odyssey-world-elite": CardStyle(
            cardId: "desjardins-odyssey-world-elite",
            shortName: "Desjardins Odyssey",
            issuer: "Desjardins",
            network: .mastercardWorldElite,
            gradientColors: [Color(red: 0.00, green: 0.42, blue: 0.26), Color(red: 0.00, green: 0.17, blue: 0.11)],
            textColor: .white,
            accentColor: Color(red: 0.45, green: 0.95, blue: 0.65),
            isDark: true
        ),

        // The PC Financial family is four cards deep and the brand is a single near-black, so
        // luminance alone cannot separate them. They step from mid-slate to warm charcoal and
        // carry a different accent each — red, orange, gold — against pc-insiders-world-elite's
        // neutral near-black with red. An owner can plausibly hold two of these at once.
        "pc-financial-mastercard": CardStyle(
            cardId: "pc-financial-mastercard",
            shortName: "PC Financial MC",
            issuer: "PC Financial",
            network: .mastercard,
            gradientColors: [Color(red: 0.34, green: 0.35, blue: 0.38), Color(red: 0.18, green: 0.19, blue: 0.21)],
            textColor: .white,
            accentColor: Color(red: 0.95, green: 0.20, blue: 0.22),
            isDark: true
        ),
        "pc-financial-world-mastercard": CardStyle(
            cardId: "pc-financial-world-mastercard",
            shortName: "PC Financial World",
            issuer: "PC Financial",
            network: .mastercard,
            gradientColors: [Color(red: 0.22, green: 0.24, blue: 0.30), Color(red: 0.10, green: 0.11, blue: 0.15)],
            textColor: .white,
            accentColor: Color(red: 1.0, green: 0.55, blue: 0.15),
            isDark: true
        ),
        "pc-financial-world-elite": CardStyle(
            cardId: "pc-financial-world-elite",
            shortName: "PC Financial WE",
            issuer: "PC Financial",
            network: .mastercardWorldElite,
            gradientColors: [Color(red: 0.20, green: 0.15, blue: 0.13), Color(red: 0.09, green: 0.06, blue: 0.05)],
            textColor: .white,
            accentColor: Color(red: 0.95, green: 0.80, blue: 0.45),
            isDark: true
        ),
        "cibc-dividend-visa": CardStyle(
            cardId: "cibc-dividend-visa",
            shortName: "CIBC Dividend",
            issuer: "CIBC",
            network: .visa,
            gradientColors: [Color(red: 0.52, green: 0.05, blue: 0.12), Color(red: 0.22, green: 0.02, blue: 0.06)],
            textColor: .white,
            accentColor: Color(red: 0.95, green: 0.75, blue: 0.80),
            isDark: true
        ),
        "td-business-travel-visa": CardStyle(
            cardId: "td-business-travel-visa",
            shortName: "TD Biz Travel",
            issuer: "TD",
            network: .visa,
            gradientColors: [Color(red: 0.02, green: 0.26, blue: 0.14), Color(red: 0.01, green: 0.10, blue: 0.05)],
            textColor: .white,
            accentColor: Color(red: 0.35, green: 0.90, blue: 0.55),
            isDark: true
        ),
        "walmart-rewards-mastercard": CardStyle(
            cardId: "walmart-rewards-mastercard",
            shortName: "Walmart Rewards",
            issuer: "Walmart",
            network: .mastercard,
            gradientColors: [Color(red: 0.00, green: 0.44, blue: 0.76), Color(red: 0.00, green: 0.20, blue: 0.45)],
            textColor: .white,
            accentColor: Color(red: 1.0, green: 0.76, blue: 0.03),
            isDark: true
        ),
        "walmart-rewards-world-mastercard": CardStyle(
            cardId: "walmart-rewards-world-mastercard",
            shortName: "Walmart World",
            issuer: "Walmart",
            network: .mastercard,
            gradientColors: [Color(red: 0.15, green: 0.22, blue: 0.32), Color(red: 0.06, green: 0.09, blue: 0.15)],
            textColor: .white,
            accentColor: Color(red: 1.0, green: 0.76, blue: 0.03),
            isDark: true
        ),
        "cibc-costco-mastercard": CardStyle(
            cardId: "cibc-costco-mastercard",
            shortName: "CIBC Costco",
            issuer: "CIBC",
            network: .mastercard,
            gradientColors: [Color(red: 0.60, green: 0.08, blue: 0.16), Color(red: 0.10, green: 0.20, blue: 0.40)],
            textColor: .white,
            accentColor: Color(red: 0.95, green: 0.85, blue: 0.40),
            isDark: true
        ),
        "royal-bank-of-canada-rbc-british-airways-visa": CardStyle(
            cardId: "royal-bank-of-canada-rbc-british-airways-visa",
            shortName: "RBC British Airways",
            issuer: "RBC",
            network: .visaInfinite,
            gradientColors: [Color(red: 0.05, green: 0.15, blue: 0.38), Color(red: 0.02, green: 0.06, blue: 0.18)],
            textColor: .white,
            accentColor: Color(red: 0.90, green: 0.15, blue: 0.20),
            isDark: true
        ),
        "neo-financial-neo-world-mastercard": CardStyle(
            cardId: "neo-financial-neo-world-mastercard",
            shortName: "Neo World",
            issuer: "Neo Financial",
            network: .mastercardWorldElite,
            gradientColors: [Color(red: 0.16, green: 0.17, blue: 0.20), Color(red: 0.06, green: 0.07, blue: 0.09)],
            textColor: .white,
            accentColor: Color(red: 0.30, green: 0.85, blue: 0.65),
            isDark: true
        ),
        "mbna-true-line-mastercard": CardStyle(
            cardId: "mbna-true-line-mastercard",
            shortName: "True Line",
            issuer: "MBNA",
            network: .mastercard,
            gradientColors: [Color(red: 0.28, green: 0.32, blue: 0.38), Color(red: 0.14, green: 0.16, blue: 0.20)],
            textColor: .white,
            accentColor: Color(red: 0.35, green: 0.75, blue: 0.95),
            isDark: true
        ),
        "capital-one-canada-capital-one-guaranteed": CardStyle(
            cardId: "capital-one-canada-capital-one-guaranteed",
            shortName: "Guaranteed Secured",
            issuer: "Capital One",
            network: .mastercard,
            gradientColors: [Color(red: 0.08, green: 0.18, blue: 0.32), Color(red: 0.03, green: 0.08, blue: 0.18)],
            textColor: .white,
            accentColor: Color(red: 0.85, green: 0.20, blue: 0.20),
            isDark: true
        ),
    ]

    private static let catalogueCardsById: [String: CardProduct] = {
        guard let catalogue = try? SeedLoader.loadCatalogue() else { return [:] }
        return Dictionary(uniqueKeysWithValues: catalogue.cards.map { ($0.cardId, $0) })
    }()

    private struct VisualPalette {
        let gradientColors: [Color]
        let textColor: Color
        let accentColor: Color
        let isDark: Bool
    }

    private static func defaultVisuals(forIssuer issuer: String, network: CardNetwork) -> VisualPalette {
        let lower = issuer.lowercased()
        if lower.contains("american express") || lower == "amex" {
            return VisualPalette(
                gradientColors: [Color(red: 0.08, green: 0.22, blue: 0.45), Color(red: 0.12, green: 0.38, blue: 0.72)],
                textColor: .white,
                accentColor: Color(red: 0.45, green: 0.82, blue: 1.0),
                isDark: true
            )
        } else if lower.contains("chase") {
            return VisualPalette(
                gradientColors: [Color(red: 0.06, green: 0.22, blue: 0.48), Color(red: 0.02, green: 0.10, blue: 0.26)],
                textColor: .white,
                accentColor: Color(red: 0.40, green: 0.75, blue: 1.0),
                isDark: true
            )
        } else if lower.contains("citi") {
            return VisualPalette(
                gradientColors: [Color(red: 0.05, green: 0.20, blue: 0.42), Color(red: 0.02, green: 0.08, blue: 0.20)],
                textColor: .white,
                accentColor: Color(red: 0.95, green: 0.30, blue: 0.30),
                isDark: true
            )
        } else if lower.contains("capital one") {
            return VisualPalette(
                gradientColors: [Color(red: 0.08, green: 0.18, blue: 0.32), Color(red: 0.03, green: 0.08, blue: 0.18)],
                textColor: .white,
                accentColor: Color(red: 0.85, green: 0.20, blue: 0.20),
                isDark: true
            )
        } else if lower.contains("bank of america") {
            return VisualPalette(
                gradientColors: [Color(red: 0.65, green: 0.08, blue: 0.12), Color(red: 0.12, green: 0.16, blue: 0.30)],
                textColor: .white,
                accentColor: Color(red: 0.95, green: 0.80, blue: 0.40),
                isDark: true
            )
        } else if lower.contains("wells fargo") {
            return VisualPalette(
                gradientColors: [Color(red: 0.58, green: 0.06, blue: 0.10), Color(red: 0.22, green: 0.02, blue: 0.05)],
                textColor: .white,
                accentColor: Color(red: 1.0, green: 0.82, blue: 0.40),
                isDark: true
            )
        } else if lower.contains("discover") {
            return VisualPalette(
                gradientColors: [Color(red: 0.22, green: 0.24, blue: 0.28), Color(red: 0.10, green: 0.11, blue: 0.14)],
                textColor: .white,
                accentColor: Color(red: 1.0, green: 0.50, blue: 0.10),
                isDark: true
            )
        } else if lower.contains("td") {
            return VisualPalette(
                gradientColors: [Color(red: 0.06, green: 0.26, blue: 0.15), Color(red: 0.02, green: 0.10, blue: 0.06)],
                textColor: .white,
                accentColor: Color(red: 0.25, green: 0.85, blue: 0.45),
                isDark: true
            )
        } else if lower.contains("scotia") {
            return VisualPalette(
                gradientColors: [Color(red: 0.65, green: 0.08, blue: 0.12), Color(red: 0.35, green: 0.03, blue: 0.06)],
                textColor: .white,
                accentColor: Color(red: 1.0, green: 0.82, blue: 0.45),
                isDark: true
            )
        } else if lower.contains("cibc") {
            return VisualPalette(
                gradientColors: [Color(red: 0.55, green: 0.06, blue: 0.15), Color(red: 0.25, green: 0.02, blue: 0.08)],
                textColor: .white,
                accentColor: Color(red: 0.95, green: 0.75, blue: 0.80),
                isDark: true
            )
        } else if lower.contains("bmo") {
            return VisualPalette(
                gradientColors: [Color(red: 0.05, green: 0.25, blue: 0.50), Color(red: 0.02, green: 0.10, blue: 0.24)],
                textColor: .white,
                accentColor: Color(red: 0.45, green: 0.85, blue: 1.0),
                isDark: true
            )
        } else if lower.contains("rbc") || lower.contains("royal bank") {
            return VisualPalette(
                gradientColors: [Color(red: 0.06, green: 0.20, blue: 0.48), Color(red: 0.02, green: 0.08, blue: 0.25)],
                textColor: .white,
                accentColor: Color(red: 1.0, green: 0.82, blue: 0.15),
                isDark: true
            )
        } else if lower.contains("tangerine") {
            return VisualPalette(
                gradientColors: [Color(red: 0.95, green: 0.45, blue: 0.05), Color(red: 0.80, green: 0.30, blue: 0.02)],
                textColor: .white,
                accentColor: .white,
                isDark: true
            )
        } else if lower.contains("barclays") {
            return VisualPalette(
                gradientColors: [Color(red: 0.00, green: 0.35, blue: 0.55), Color(red: 0.00, green: 0.15, blue: 0.28)],
                textColor: .white,
                accentColor: Color(red: 0.35, green: 0.85, blue: 0.95),
                isDark: true
            )
        } else if lower.contains("u.s. bank") || lower.contains("us bank") {
            return VisualPalette(
                gradientColors: [Color(red: 0.08, green: 0.16, blue: 0.35), Color(red: 0.03, green: 0.07, blue: 0.18)],
                textColor: .white,
                accentColor: Color(red: 0.90, green: 0.20, blue: 0.25),
                isDark: true
            )
        } else if lower.contains("goldman sachs") {
            return VisualPalette(
                gradientColors: [Color(red: 0.22, green: 0.22, blue: 0.24), Color(red: 0.11, green: 0.11, blue: 0.12)],
                textColor: .white,
                accentColor: Color(red: 0.85, green: 0.88, blue: 0.92),
                isDark: true
            )
        } else if lower.contains("desjardins") {
            return VisualPalette(
                gradientColors: [Color(red: 0.00, green: 0.42, blue: 0.26), Color(red: 0.00, green: 0.17, blue: 0.11)],
                textColor: .white,
                accentColor: Color(red: 0.45, green: 0.95, blue: 0.65),
                isDark: true
            )
        } else if lower.contains("pnc") {
            return VisualPalette(
                gradientColors: [Color(red: 0.08, green: 0.18, blue: 0.35), Color(red: 0.03, green: 0.08, blue: 0.18)],
                textColor: .white,
                accentColor: Color(red: 0.95, green: 0.55, blue: 0.15),
                isDark: true
            )
        } else if lower.contains("fnbo") {
            return VisualPalette(
                gradientColors: [Color(red: 0.08, green: 0.24, blue: 0.20), Color(red: 0.03, green: 0.10, blue: 0.08)],
                textColor: .white,
                accentColor: Color(red: 0.45, green: 0.85, blue: 0.65),
                isDark: true
            )
        } else {
            return VisualPalette(
                gradientColors: [Color(red: 0.25, green: 0.30, blue: 0.38), Color(red: 0.15, green: 0.18, blue: 0.24)],
                textColor: .white,
                accentColor: .white,
                isDark: true
            )
        }
    }

    static func style(for cardId: String) -> CardStyle {
        if let style = styles[cardId] {
            return style
        }

        // MARK: - Derived Default for Unthemed Catalogue Cards
        if let card = catalogueCardsById[cardId] {
            let derivedNetwork: CardNetwork
            switch card.network {
            case .amex:
                derivedNetwork = .amex
            case .visa:
                let lower = (card.cardId + " " + card.officialName).lowercased()
                if lower.contains("privilege") || lower.contains("vip") {
                    derivedNetwork = .visaInfinitePrivilege
                } else if lower.contains("infinite") || lower.contains("-vi") {
                    derivedNetwork = .visaInfinite
                } else {
                    derivedNetwork = .visa
                }
            case .mastercard:
                let lower = (card.cardId + " " + card.officialName).lowercased()
                if lower.contains("world-elite") || lower.contains("world elite") || lower.contains("-we") {
                    derivedNetwork = .mastercardWorldElite
                } else {
                    derivedNetwork = .mastercard
                }
            case .discover:
                derivedNetwork = .discover
            case .privateLabel:
                derivedNetwork = .privateLabel
            }

            let colors = defaultVisuals(forIssuer: card.issuer, network: derivedNetwork)
            let trimmedOfficial = card.officialName
                .replacingOccurrences(of: " Credit Card", with: "")
                .replacingOccurrences(of: " credit card", with: "")
                .trimmingCharacters(in: .whitespaces)
            let shortName = trimmedOfficial.isEmpty
                ? card.cardId.replacingOccurrences(of: "-", with: " ").capitalized
                : trimmedOfficial

            return CardStyle(
                cardId: cardId,
                shortName: shortName,
                issuer: card.issuer,
                network: derivedNetwork,
                gradientColors: colors.gradientColors,
                textColor: colors.textColor,
                accentColor: colors.accentColor,
                isDark: colors.isDark
            )
        }

        // MARK: - Smart Fallback for Custom or Uncatalogued Cards
        let lower = cardId.lowercased()
        let inferredNetwork: CardNetwork
        if lower.contains("discover") {
            inferredNetwork = .discover
        } else if lower.contains("amex") || lower.contains("american-express") {
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
        if lower.contains("discover") {
            inferredIssuer = "Discover"
        } else if lower.contains("amex") || lower.contains("american-express") {
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

        let colors = defaultVisuals(forIssuer: inferredIssuer, network: inferredNetwork)

        return CardStyle(
            cardId: cardId,
            shortName: cleanedName,
            issuer: inferredIssuer,
            network: inferredNetwork,
            gradientColors: colors.gradientColors,
            textColor: colors.textColor,
            accentColor: colors.accentColor,
            isDark: colors.isDark
        )
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
        switch CategoryTaxonomy.canonicalID(category).lowercased() {
        case "grocery":
            return Meta(icon: "cart.fill", color: .green, displayName: "Grocery")
        case "dining", "fooddelivery":
            return Meta(icon: "fork.knife", color: .orange, displayName: "Dining & Food")
        case "gasstation":
            return Meta(icon: "fuelpump.fill", color: .blue, displayName: "Gas Station")
        case "transit":
            return Meta(icon: "tram.fill", color: .teal, displayName: "Transit & Travel")
        case "travel":
            return Meta(icon: "airplane", color: .indigo, displayName: "Travel")
        case "lodging":
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
        case "drugstore":
            return Meta(icon: "cross.case.fill", color: .mint, displayName: "Pharmacy")
        case "recurring":
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
        case "householdutilities":
            return Meta(icon: "lightbulb.fill", color: .yellow, displayName: "Household Utilities")
        case "marriottdirect":
            return Meta(icon: "crown.fill", color: .brown, displayName: "Marriott Direct")
        case "memberships":
            return Meta(icon: "person.2.fill", color: .teal, displayName: "Memberships")
        case "other":
            return Meta(icon: "tag.fill", color: .gray, displayName: "General Merchandise")
        case "retailshopping":
            return Meta(icon: "bag.fill", color: .indigo, displayName: "Retail Shopping")
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

// MARK: - iOS 26 Liquid Glass Modifiers

/// An iOS 26-inspired Liquid Glass view modifier providing optical refraction borders,
/// multi-layered specular reflections, and reactive lighting.
public struct LiquidGlassModifier: ViewModifier {
    public var cornerRadius: CGFloat
    public var tintColor: Color?
    public var isHighlighted: Bool
    public var intensity: Double

    @Environment(\.colorScheme) private var colorScheme

    public init(
        cornerRadius: CGFloat = 16,
        tintColor: Color? = nil,
        isHighlighted: Bool = false,
        intensity: Double = 1.0
    ) {
        self.cornerRadius = cornerRadius
        self.tintColor = tintColor
        self.isHighlighted = isHighlighted
        self.intensity = intensity
    }

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // 1. Ultra-thin refractive glass material
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // 2. Dynamic glass tint
                    if let tint = tintColor {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(tint.opacity(colorScheme == .dark ? 0.08 * intensity : 0.12 * intensity))
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.04 * intensity)
                                    : Color.white.opacity(0.40 * intensity)
                            )
                    }

                    // 3. Specular refraction top highlight
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.16 * intensity : 0.45 * intensity),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                // 4. Liquid Glass refractive rim
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.35 * intensity : 0.70 * intensity),
                                Color.white.opacity(colorScheme == .dark ? 0.08 * intensity : 0.20 * intensity),
                                Color.black.opacity(colorScheme == .dark ? 0.20 * intensity : 0.05 * intensity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: isHighlighted ? 1.5 : 1.0
                    )
            )
            .shadow(
                color: (tintColor ?? Color.black).opacity(colorScheme == .dark ? 0.28 : 0.07),
                radius: isHighlighted ? 14 : 10,
                x: 0,
                y: isHighlighted ? 6 : 4
            )
    }
}

public extension View {
    func liquidGlass(
        cornerRadius: CGFloat = 16,
        tint: Color? = nil,
        isHighlighted: Bool = false,
        intensity: Double = 1.0
    ) -> some View {
        modifier(LiquidGlassModifier(
            cornerRadius: cornerRadius,
            tintColor: tint,
            isHighlighted: isHighlighted,
            intensity: intensity
        ))
    }
}
