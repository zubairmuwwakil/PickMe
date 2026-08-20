package com.cardcopilot.app.ui.theme

import androidx.compose.ui.graphics.Color

data class CardStyle(
    val cardId: String,
    val shortName: String,
    val issuer: String,
    val networkLabel: String,
    val gradientColors: List<Color>,
    val textColor: Color,
    val accentColor: Color,
    val isDark: Boolean
)

object CardVisualTheme {
    val definedCardIds: Set<String> = setOf(
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
        "cibc-aventura-visa"
    )

    fun style(cardId: String): CardStyle {
        return when (cardId) {
            // MARK: - American Express Cards
            "amex-cobalt" -> CardStyle(
                cardId = cardId,
                shortName = "Cobalt",
                issuer = "American Express",
                networkLabel = "AMEX",
                gradientColors = listOf(Color(0xFF143873), Color(0xFF1F61B8)),
                textColor = Color.White,
                accentColor = Color(0xFF73D1FF),
                isDark = true
            )
            "amex-platinum" -> CardStyle(
                cardId = cardId,
                shortName = "Platinum",
                issuer = "American Express",
                networkLabel = "AMEX",
                gradientColors = listOf(Color(0xFFD1D9E0), Color(0xFF94A1AD)),
                textColor = Color(0xFF1F262E),
                accentColor = Color(0xFF33404D),
                isDark = false
            )
            "amex-bonvoy" -> CardStyle(
                cardId = cardId,
                shortName = "Bonvoy",
                issuer = "Marriott / Amex",
                networkLabel = "AMEX",
                gradientColors = listOf(Color(0xFF1C2947), Color(0xFF332452)),
                textColor = Color.White,
                accentColor = Color(0xFFF2C773),
                isDark = true
            )
            "amex-simplycash" -> CardStyle(
                cardId = cardId,
                shortName = "SimplyCash",
                issuer = "American Express",
                networkLabel = "AMEX",
                gradientColors = listOf(Color(0xFF0F4285), Color(0xFF052452)),
                textColor = Color.White,
                accentColor = Color(0xFFBFE6FF),
                isDark = true
            )
            "amex-simplycash-preferred" -> CardStyle(
                cardId = cardId,
                shortName = "SimplyCash Preferred",
                issuer = "American Express",
                networkLabel = "AMEX",
                gradientColors = listOf(Color(0xFF0A295C), Color(0xFF031433)),
                textColor = Color.White,
                accentColor = Color(0xFF80D1FF),
                isDark = true
            )
            "scotia-gold-amex" -> CardStyle(
                cardId = cardId,
                shortName = "Gold Amex",
                issuer = "Scotiabank",
                networkLabel = "AMEX",
                gradientColors = listOf(Color(0xFFB8860B), Color(0xFF7D5A00)),
                textColor = Color.White,
                accentColor = Color(0xFFFFD700),
                isDark = true
            )

            // MARK: - Visa Cards
            "scotia-momentum-vi-plus" -> CardStyle(
                cardId = cardId,
                shortName = "Momentum",
                issuer = "Scotiabank",
                networkLabel = "VISA INFINITE",
                gradientColors = listOf(Color(0xFFA6141F), Color(0xFF61080F)),
                textColor = Color.White,
                accentColor = Color(0xFFFFD166),
                isDark = true
            )
            "scotia-passport-visa-infinite-plus" -> CardStyle(
                cardId = cardId,
                shortName = "Passport VI",
                issuer = "Scotiabank",
                networkLabel = "VISA INFINITE",
                gradientColors = listOf(Color(0xFF1C3B57), Color(0xFF0D1E2E)),
                textColor = Color.White,
                accentColor = Color(0xFF4DA6FF),
                isDark = true
            )
            "td-aeroplan-visa-infinite" -> CardStyle(
                cardId = cardId,
                shortName = "Aeroplan VI",
                issuer = "TD",
                networkLabel = "VISA INFINITE",
                gradientColors = listOf(Color(0xFF005A36), Color(0xFF00331F)),
                textColor = Color.White,
                accentColor = Color(0xFF00D284),
                isDark = true
            )
            "td-first-class-travel-visa-infinite" -> CardStyle(
                cardId = cardId,
                shortName = "TD First Class",
                issuer = "TD",
                networkLabel = "VISA INFINITE",
                gradientColors = listOf(Color(0xFF0A4D2E), Color(0xFF031F12)),
                textColor = Color.White,
                accentColor = Color(0xFFFFD666),
                isDark = true
            )
            "td-cash-back-visa-infinite" -> CardStyle(
                cardId = cardId,
                shortName = "TD Cash Back",
                issuer = "TD",
                networkLabel = "VISA INFINITE",
                gradientColors = listOf(Color(0xFF1A3D2E), Color(0xFF0A1A14)),
                textColor = Color.White,
                accentColor = Color(0xFF4DE680),
                isDark = true
            )
            "rbc-avion-visa-infinite" -> CardStyle(
                cardId = cardId,
                shortName = "Avion VI",
                issuer = "RBC",
                networkLabel = "VISA INFINITE",
                gradientColors = listOf(Color(0xFF003366), Color(0xFF001A33)),
                textColor = Color.White,
                accentColor = Color(0xFFFFD200),
                isDark = true
            )
            "rbc-ion-plus-visa" -> CardStyle(
                cardId = cardId,
                shortName = "RBC ION+",
                issuer = "RBC",
                networkLabel = "VISA",
                gradientColors = listOf(Color(0xFFB81A61), Color(0xFF610A33)),
                textColor = Color.White,
                accentColor = Color(0xFFFF7399),
                isDark = true
            )
            "cibc-dividend-visa-infinite" -> CardStyle(
                cardId = cardId,
                shortName = "Dividend VI",
                issuer = "CIBC",
                networkLabel = "VISA INFINITE",
                gradientColors = listOf(Color(0xFF8B0000), Color(0xFF4D0000)),
                textColor = Color.White,
                accentColor = Color(0xFFFF4D4D),
                isDark = true
            )
            "cibc-aventura-visa" -> CardStyle(
                cardId = cardId,
                shortName = "CIBC Aventura",
                issuer = "CIBC",
                networkLabel = "VISA",
                gradientColors = listOf(Color(0xFF731429), Color(0xFF1A1F47)),
                textColor = Color.White,
                accentColor = Color(0xFFD9E6FA),
                isDark = true
            )
            "cibc-aventura-visa-infinite" -> CardStyle(
                cardId = cardId,
                shortName = "CIBC Aventura VI",
                issuer = "CIBC",
                networkLabel = "VISA INFINITE",
                gradientColors = listOf(Color(0xFF850D24), Color(0xFF260D2E)),
                textColor = Color.White,
                accentColor = Color(0xFFFFD173),
                isDark = true
            )
            "bmo-eclipse-visa-infinite" -> CardStyle(
                cardId = cardId,
                shortName = "BMO eclipse",
                issuer = "BMO",
                networkLabel = "VISA INFINITE",
                gradientColors = listOf(Color(0xFF241F59), Color(0xFF0F0A2E)),
                textColor = Color.White,
                accentColor = Color(0xFFBF8CFF),
                isDark = true
            )
            "wealthsimple-vip" -> CardStyle(
                cardId = cardId,
                shortName = "Wealthsimple VIP",
                issuer = "Wealthsimple",
                networkLabel = "VISA INFINITE PRIVILEGE",
                gradientColors = listOf(Color(0xFF1F2421), Color(0xFF0F1210)),
                textColor = Color.White,
                accentColor = Color(0xFFBFC7D1),
                isDark = true
            )
            "cryptocom-royal-indigo" -> CardStyle(
                cardId = cardId,
                shortName = "Royal Indigo",
                issuer = "Crypto.com",
                networkLabel = "VISA PREPAID",
                gradientColors = listOf(Color(0xFF1A1F3C), Color(0xFF2B3566)),
                textColor = Color.White,
                accentColor = Color(0xFF6C7AE0),
                isDark = true
            )
            "simplii-cash-back-visa" -> CardStyle(
                cardId = cardId,
                shortName = "Simplii Cash Back",
                issuer = "Simplii Financial",
                networkLabel = "VISA",
                gradientColors = listOf(Color(0xFFD11F5C), Color(0xFF800A38)),
                textColor = Color.White,
                accentColor = Color(0xFFFFD9E6),
                isDark = true
            )
            "home-trust-preferred-visa" -> CardStyle(
                cardId = cardId,
                shortName = "Home Trust Preferred",
                issuer = "Home Trust",
                networkLabel = "VISA",
                gradientColors = listOf(Color(0xFF142952), Color(0xFF0A1429)),
                textColor = Color.White,
                accentColor = Color(0xFFF2C759),
                isDark = true
            )

            // MARK: - Mastercard Cards
            "mbna-rewards-we" -> CardStyle(
                cardId = cardId,
                shortName = "MBNA Rewards",
                issuer = "MBNA / TD",
                networkLabel = "WORLD ELITE",
                gradientColors = listOf(Color(0xFF262E3D), Color(0xFF14597A)),
                textColor = Color.White,
                accentColor = Color(0xFF4DD9F2),
                isDark = true
            )
            "mbna-smart-cash-world" -> CardStyle(
                cardId = cardId,
                shortName = "Smart Cash World",
                issuer = "MBNA / TD",
                networkLabel = "MASTERCARD",
                gradientColors = listOf(Color(0xFF4D5761), Color(0xFF292E33)),
                textColor = Color.White,
                accentColor = Color(0xFF40D973),
                isDark = true
            )
            "tangerine-moneyback-world" -> CardStyle(
                cardId = cardId,
                shortName = "Money-Back",
                issuer = "Tangerine",
                networkLabel = "MASTERCARD",
                gradientColors = listOf(Color(0xFFF26B1D), Color(0xFFD14D0A)),
                textColor = Color.White,
                accentColor = Color.White,
                isDark = true
            )
            "triangle-we" -> CardStyle(
                cardId = cardId,
                shortName = "Triangle WE",
                issuer = "Canadian Tire Bank",
                networkLabel = "WORLD ELITE",
                gradientColors = listOf(Color(0xFFD92B2B), Color(0xFF8C1414)),
                textColor = Color.White,
                accentColor = Color(0xFFFFD166),
                isDark = true
            )
            "rogers-red-we" -> CardStyle(
                cardId = cardId,
                shortName = "Rogers Red WE",
                issuer = "Rogers Bank",
                networkLabel = "WORLD ELITE",
                gradientColors = listOf(Color(0xFFD91A2A), Color(0xFF8F0E1A)),
                textColor = Color.White,
                accentColor = Color.White,
                isDark = true
            )
            "national-bank-world-elite" -> CardStyle(
                cardId = cardId,
                shortName = "NBC World Elite",
                issuer = "National Bank",
                networkLabel = "WORLD ELITE",
                gradientColors = listOf(Color(0xFFC41230), Color(0xFF60000F)),
                textColor = Color.White,
                accentColor = Color.White,
                isDark = true
            )
            "pc-insiders-world-elite" -> CardStyle(
                cardId = cardId,
                shortName = "PC Insiders WE",
                issuer = "PC Financial",
                networkLabel = "WORLD ELITE",
                gradientColors = listOf(Color(0xFF111111), Color(0xFF2B2B2B)),
                textColor = Color.White,
                accentColor = Color(0xFFE01A22),
                isDark = true
            )
            "bmo-ascend-world-elite" -> CardStyle(
                cardId = cardId,
                shortName = "BMO Ascend WE",
                issuer = "BMO",
                networkLabel = "WORLD ELITE",
                gradientColors = listOf(Color(0xFF0A3873), Color(0xFF051433)),
                textColor = Color.White,
                accentColor = Color(0xFF73D9FF),
                isDark = true
            )
            "bmo-cashback-world-elite" -> CardStyle(
                cardId = cardId,
                shortName = "BMO CashBack WE",
                issuer = "BMO",
                networkLabel = "WORLD ELITE",
                gradientColors = listOf(Color(0xFF0D4080), Color(0xFF051A3D)),
                textColor = Color.White,
                accentColor = Color(0xFFE62626),
                isDark = true
            )
            "westjet-rbc-world-elite" -> CardStyle(
                cardId = cardId,
                shortName = "WestJet RBC WE",
                issuer = "RBC",
                networkLabel = "WORLD ELITE",
                gradientColors = listOf(Color(0xFF005973), Color(0xFF031F38)),
                textColor = Color.White,
                accentColor = Color(0xFF33D9D9),
                isDark = true
            )
            "rbc-cashback-preferred-we" -> CardStyle(
                cardId = cardId,
                shortName = "RBC Cash Back WE",
                issuer = "RBC",
                networkLabel = "WORLD ELITE",
                gradientColors = listOf(Color(0xFF142E59), Color(0xFF05142E)),
                textColor = Color.White,
                accentColor = Color(0xFFFFCC33),
                isDark = true
            )
            "amazon-ca-rewards-mastercard" -> CardStyle(
                cardId = cardId,
                shortName = "Amazon.ca Rewards",
                issuer = "MBNA / TD",
                networkLabel = "MASTERCARD",
                gradientColors = listOf(Color(0xFF242E38), Color(0xFF141A24)),
                textColor = Color.White,
                accentColor = Color(0xFFFF9900),
                isDark = true
            )

            // MARK: - Smart Fallback for Custom or Unstyled Cards
            else -> {
                val lower = cardId.lowercase()
                val inferredNetwork = when {
                    lower.contains("amex") || lower.startsWith("american-express") -> "AMEX"
                    lower.contains("vip") || lower.contains("privilege") -> "VISA INFINITE PRIVILEGE"
                    lower.contains("infinite") || lower.contains("-vi") -> "VISA INFINITE"
                    lower.contains("visa") -> "VISA"
                    lower.contains("world-elite") || lower.contains("-we") -> "WORLD ELITE"
                    lower.contains("mastercard") || lower.contains("-mc") -> "MASTERCARD"
                    lower.contains("prepaid") -> "PREPAID"
                    else -> "VISA"
                }

                val inferredIssuer = when {
                    lower.contains("amex") || lower.contains("american-express") -> "American Express"
                    lower.contains("td-") || lower.contains("td") -> "TD"
                    lower.contains("scotia") -> "Scotiabank"
                    lower.contains("cibc") -> "CIBC"
                    lower.contains("rbc") -> "RBC"
                    lower.contains("bmo") -> "BMO"
                    lower.contains("tangerine") -> "Tangerine"
                    lower.contains("wealthsimple") -> "Wealthsimple"
                    else -> "Credit Card"
                }

                CardStyle(
                    cardId = cardId,
                    shortName = cardId.replace("-", " ").capitalizeWords(),
                    issuer = inferredIssuer,
                    networkLabel = inferredNetwork,
                    gradientColors = listOf(Color(0xFF2A2E35), Color(0xFF1A1C20)),
                    textColor = Color.White,
                    accentColor = Color(0xFF64B5F6),
                    isDark = true
                )
            }
        }
    }

    private fun String.capitalizeWords(): String = split(" ").joinToString(" ") { it.replaceFirstChar(Char::uppercase) }
}
