package com.cardcopilot.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cardcopilot.app.ui.components.CardArtView
import com.cardcopilot.app.ui.theme.CardVisualTheme
import com.cardcopilot.engine.engine.AcquisitionAnalysis
import com.cardcopilot.engine.engine.PortfolioAnalysis
import com.cardcopilot.engine.engine.PortfolioVerdict
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WalletHealthScreen(
    portfolioAnalysis: PortfolioAnalysis,
    acquisitionAnalysis: AcquisitionAnalysis,
    onBack: () -> Unit
) {
    var selectedTab by remember { mutableIntStateOf(0) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Wallet Health & Audit", fontWeight = FontWeight.Bold) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            PrimaryTabRow(
                selectedTabIndex = selectedTab,
                containerColor = MaterialTheme.colorScheme.surfaceVariant
            ) {
                Tab(
                    selected = selectedTab == 0,
                    onClick = { selectedTab = 0 },
                    text = { Text("Keep / Cancel Audit", fontWeight = FontWeight.SemiBold) }
                )
                Tab(
                    selected = selectedTab == 1,
                    onClick = { selectedTab = 1 },
                    text = { Text("Acquisitions (${acquisitionAnalysis.recommended.size})", fontWeight = FontWeight.SemiBold) }
                )
            }

            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                if (selectedTab == 0) {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(14.dp))
                                .background(MaterialTheme.colorScheme.surface)
                                .padding(16.dp)
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(
                                    text = "ANNUAL WALLET PORTFOLIO VALUE",
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    letterSpacing = 1.sp
                                )
                                Text(
                                    text = String.format(Locale.US, "$%.2f CAD / yr", portfolioAnalysis.portfolioValueCad),
                                    fontSize = 28.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = MaterialTheme.colorScheme.primary
                                )
                                Text(
                                    text = String.format(Locale.US, "Total Annual Fees: $%.2f CAD", portfolioAnalysis.totalAnnualFeesCad),
                                    fontSize = 13.sp,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                            }
                        }
                    }

                    items(portfolioAnalysis.contributions) { contribution ->
                        val style = CardVisualTheme.style(contribution.cardId)
                        val verdictColor = when (contribution.verdict) {
                            PortfolioVerdict.KEEP, PortfolioVerdict.FREE_TO_KEEP -> MaterialTheme.colorScheme.primary
                            PortfolioVerdict.DOWNGRADE -> Color(0xFFD29922)
                            PortfolioVerdict.CANCEL -> Color(0xFFF85149)
                        }

                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(14.dp))
                                .background(MaterialTheme.colorScheme.surface)
                                .padding(16.dp)
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Column {
                                        Text(style.shortName, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                                        Text(style.issuer, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }

                                    Box(
                                        modifier = Modifier
                                            .clip(RoundedCornerShape(8.dp))
                                            .background(verdictColor.copy(alpha = 0.15f))
                                            .padding(horizontal = 10.dp, vertical = 4.dp)
                                    ) {
                                        Text(
                                            text = contribution.verdict.name.replace("_", " "),
                                            color = verdictColor,
                                            fontSize = 12.sp,
                                            fontWeight = FontWeight.Bold
                                        )
                                    }
                                }

                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween
                                ) {
                                    Column {
                                        Text("Marginal Value", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        Text(String.format(Locale.US, "$%.2f", contribution.marginalValueCad), fontWeight = FontWeight.SemiBold)
                                    }
                                    Column {
                                        Text("Annual Fee", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        Text(String.format(Locale.US, "$%.2f", contribution.annualFeeCad), fontWeight = FontWeight.SemiBold)
                                    }
                                    Column {
                                        Text("Net Contribution", fontSize = 11.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                        Text(
                                            text = String.format(Locale.US, "$%.2f", contribution.netContributionCad),
                                            fontWeight = FontWeight.Bold,
                                            color = if (contribution.netContributionCad >= 0) MaterialTheme.colorScheme.primary else Color(0xFFF85149)
                                        )
                                    }
                                }
                            }
                        }
                    }
                } else {
                    item {
                        Text(
                            text = "Cards that increase your wallet's rewards after subtracting their annual fee.",
                            fontSize = 14.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }

                    items(acquisitionAnalysis.candidates) { candidate ->
                        val style = CardVisualTheme.style(candidate.cardId)

                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(14.dp))
                                .background(MaterialTheme.colorScheme.surface)
                                .padding(16.dp)
                        ) {
                            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                                Row(
                                    modifier = Modifier.fillMaxWidth(),
                                    horizontalArrangement = Arrangement.SpaceBetween,
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Column {
                                        Text(style.shortName, fontWeight = FontWeight.Bold, fontSize = 16.sp)
                                        Text(style.issuer, fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                    }

                                    Text(
                                        text = String.format(Locale.US, "+$%.2f / yr", candidate.netAnnualValueCad),
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 16.sp,
                                        color = if (candidate.netAnnualValueCad > 0) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }

                                if (candidate.bucketGains.isNotEmpty()) {
                                    Text(
                                        text = "Top Gains: " + candidate.bucketGains.take(2).joinToString { "${it.label} (+$${String.format(Locale.US, "%.0f", it.marginalValueCad)})" },
                                        fontSize = 12.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
