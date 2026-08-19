package com.cardcopilot.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cardcopilot.app.ui.theme.CardVisualTheme

@Composable
fun CardArtView(
    cardId: String,
    modifier: Modifier = Modifier,
    isHero: Boolean = true
) {
    val style = CardVisualTheme.style(cardId)
    val shape = RoundedCornerShape(16.dp)

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(if (isHero) 190.dp else 130.dp)
            .shadow(elevation = if (isHero) 8.dp else 4.dp, shape = shape)
            .clip(shape)
            .background(
                brush = Brush.linearGradient(colors = style.gradientColors)
            )
            .border(width = 1.dp, color = Color.White.copy(alpha = 0.15f), shape = shape)
            .padding(18.dp)
    ) {
        Column(
            modifier = Modifier.matchParentSize(),
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = style.issuer.uppercase(),
                    color = style.textColor.copy(alpha = 0.8f),
                    fontSize = 11.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 1.sp
                )
                Text(
                    text = style.networkLabel,
                    color = style.accentColor,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.2.sp
                )
            }

            Spacer(modifier = Modifier.weight(1f))

            Column {
                Text(
                    text = style.shortName,
                    color = style.textColor,
                    fontSize = if (isHero) 22.sp else 16.sp,
                    fontWeight = FontWeight.Bold
                )
                Text(
                    text = "•••• •••• •••• 2026",
                    color = style.textColor.copy(alpha = 0.5f),
                    fontSize = 12.sp,
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier.padding(top = 4.dp)
                )
            }
        }
    }
}
