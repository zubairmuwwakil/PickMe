package com.cardcopilot.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val DarkGray900 = Color(0xFF0E1116)
val DarkGray800 = Color(0xFF161B22)
val DarkGray700 = Color(0xFF21262D)
val AccentGreen = Color(0xFF2EA043)
val AccentBlue = Color(0xFF58A6FF)
val AccentGold = Color(0xFFD29922)
val TextPrimaryDark = Color(0xFFF0F6FC)
val TextSecondaryDark = Color(0xFF8B949E)

val LightGray100 = Color(0xFFF6F8FA)
val LightGray200 = Color(0xFFEAEEF2)
val TextPrimaryLight = Color(0xFF1F2328)
val TextSecondaryLight = Color(0xFF656D76)

private val DarkColorScheme = darkColorScheme(
    primary = AccentGreen,
    secondary = AccentBlue,
    tertiary = AccentGold,
    background = DarkGray900,
    surface = DarkGray800,
    surfaceVariant = DarkGray700,
    onPrimary = Color.White,
    onBackground = TextPrimaryDark,
    onSurface = TextPrimaryDark,
    onSurfaceVariant = TextSecondaryDark
)

private val LightColorScheme = lightColorScheme(
    primary = Color(0xFF1A7F37),
    secondary = Color(0xFF0969DA),
    tertiary = Color(0xFF9A6700),
    background = Color(0xFFFFFFFF),
    surface = LightGray100,
    surfaceVariant = LightGray200,
    onPrimary = Color.White,
    onBackground = TextPrimaryLight,
    onSurface = TextPrimaryLight,
    onSurfaceVariant = TextSecondaryLight
)

@Composable
fun CardCopilotTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme
    MaterialTheme(
        colorScheme = colorScheme,
        content = content
    )
}
