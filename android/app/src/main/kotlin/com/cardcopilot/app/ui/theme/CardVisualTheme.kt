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
        "national-bank-world-elite",
        "pc-insiders-world-elite"
    )

    fun style(cardId: String): CardStyle {
        return when (cardId) {
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
            "wealthsimple-vip" -> CardStyle(
                cardId = cardId,
                shortName = "Cash Card",
                issuer = "Wealthsimple",
                networkLabel = "MASTERCARD",
                gradientColors = listOf(Color(0xFF1F2421), Color(0xFF0F1210)),
                textColor = Color.White,
                accentColor = Color(0xFF2ECC71),
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
            else -> CardStyle(
                cardId = cardId,
                shortName = cardId.replace("-", " ").capitalizeWords(),
                issuer = "Credit Card",
                networkLabel = "CREDIT",
                gradientColors = listOf(Color(0xFF2A2E35), Color(0xFF1A1C20)),
                textColor = Color.White,
                accentColor = Color(0xFF64B5F6),
                isDark = true
            )
        }
    }

    private fun String.capitalizeWords(): String = split(" ").joinToString(" ") { it.replaceFirstChar(Char::uppercase) }
}
