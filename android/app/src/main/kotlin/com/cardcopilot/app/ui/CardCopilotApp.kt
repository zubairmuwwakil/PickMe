package com.cardcopilot.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.cardcopilot.app.ui.screens.AmountCaptureScreen
import com.cardcopilot.app.ui.screens.BenefitsReferenceScreen
import com.cardcopilot.app.ui.screens.DashboardScreen
import com.cardcopilot.app.ui.screens.FinishPurchaseScreen
import com.cardcopilot.app.ui.screens.HomeScreen
import com.cardcopilot.app.ui.screens.ReconcileScreen
import com.cardcopilot.app.ui.screens.RecommendationScreen
import com.cardcopilot.app.ui.screens.WalletHealthScreen
import com.cardcopilot.app.ui.theme.CardCopilotTheme
import com.cardcopilot.engine.engine.AcquisitionAnalyzer
import com.cardcopilot.engine.engine.PortfolioAnalyzer
import com.cardcopilot.engine.loading.SeedLoader
import com.cardcopilot.engine.models.SpendDistribution
import com.cardcopilot.store.CategoryMapper
import com.cardcopilot.store.CheckoutResult
import com.cardcopilot.store.CheckoutService
import com.cardcopilot.store.ExperimentMetrics
import com.cardcopilot.store.PredictionLogRepository
import com.cardcopilot.store.db.CardCopilotDatabase
import com.cardcopilot.store.models.CaptureSource
import com.cardcopilot.store.models.NearbyMerchant
import kotlinx.coroutines.launch

@Composable
fun CardCopilotApp() {
    CardCopilotTheme {
        val context = LocalContext.current
        val scope = rememberCoroutineScope()
        val navController = rememberNavController()

        val catalogue = remember { SeedLoader.loadCatalogue() }
        val ownerState = remember { SeedLoader.loadOwnerState() }
        val benefitsCatalogue = remember { SeedLoader.loadBenefitsCatalogue() }
        val candidateCatalogue = remember { SeedLoader.loadCandidateCatalogue() }

        val db = remember { CardCopilotDatabase.getInstance(context) }
        val repository = remember { PredictionLogRepository(db) }
        val checkoutService = remember { CheckoutService(catalogue, ownerState) }

        val portfolioAnalysis = remember {
            PortfolioAnalyzer(catalogue, ownerState).analyze(
                SpendDistribution.placeholderCanadianHousehold,
                "2026-08-20"
            )
        }

        val acquisitionAnalysis = remember {
            AcquisitionAnalyzer(catalogue, candidateCatalogue, ownerState).analyze(
                SpendDistribution.placeholderCanadianHousehold,
                "2026-08-20"
            )
        }

        val sampleMerchants = remember {
            listOf(
                NearbyMerchant("loblaws-1", "Loblaws (Queen & Portland)", "MKPOICategoryFoodMarket", 43.6487, -79.4002, 120.0),
                NearbyMerchant("costco-1", "Costco Wholesale #541", null, 43.6532, -79.3832, 450.0),
                NearbyMerchant("pai-1", "Pai Northern Thai Kitchen", "MKPOICategoryRestaurant", 43.6479, -79.3887, 230.0),
                NearbyMerchant("shoppers-1", "Shoppers Drug Mart", "MKPOICategoryPharmacy", 43.6500, -79.3900, 310.0),
                NearbyMerchant("shell-1", "Shell Gas Station", "MKPOICategoryGasStation", 43.6450, -79.4100, 580.0),
                NearbyMerchant("marriott-1", "Toronto Marriott Downtown", "MKPOICategoryHotel", 43.6540, -79.3810, 800.0)
            )
        }

        val predictionRecords by repository.observeAllRecords().collectAsState(initial = emptyList())
        val metrics = remember(predictionRecords) { repository.computeMetrics(predictionRecords) }
        val valueRecovered = remember(predictionRecords) { repository.computeValueRecovered(predictionRecords) }

        var currentCheckoutResult by remember { mutableStateOf<CheckoutResult?>(null) }

        NavHost(navController = navController, startDestination = "home") {
            composable("home") {
                HomeScreen(
                    merchants = sampleMerchants,
                    recentMerchants = sampleMerchants.take(3),
                    onSelectMerchant = { merchant ->
                        navController.navigate("amount_capture/${merchant.id}")
                    },
                    onNavigateDashboard = { navController.navigate("dashboard") },
                    onNavigateWalletHealth = { navController.navigate("wallet_health") },
                    onNavigateBenefits = { navController.navigate("benefits") },
                    onNavigateReconcile = { navController.navigate("reconcile") }
                )
            }

            composable(
                route = "amount_capture/{merchantId}",
                arguments = listOf(navArgument("merchantId") { type = NavType.StringType })
            ) { backStackEntry ->
                val merchantId = backStackEntry.arguments?.getString("merchantId")
                val merchant = sampleMerchants.firstOrNull { it.id == merchantId } ?: sampleMerchants.first()

                AmountCaptureScreen(
                    merchant = merchant,
                    onConfirmAmount = { amount ->
                        val result = checkoutService.evaluate(
                            merchant = merchant,
                            userAmountCad = amount,
                            asOf = "2026-08-20"
                        )
                        currentCheckoutResult = result

                        // Record prediction immediately in database
                        scope.launch {
                            repository.recordPrediction(
                                merchant = merchant,
                                predictedCategory = result.prediction.category,
                                confidenceSource = result.prediction.confidenceSource,
                                recommendation = result.primaryRecommendation,
                                scoredAmountCad = result.scoredContext.amountCad,
                                valuationCentsPerPoint = ownerState.valuationsCad.amexMembershipRewards.centsPerPoint,
                                headline = result.explanation.headline
                            )
                        }

                        navController.navigate("recommendation")
                    },
                    onBack = { navController.popBackStack() }
                )
            }

            composable("recommendation") {
                val result = currentCheckoutResult
                if (result != null) {
                    RecommendationScreen(
                        result = result,
                        onFinishPurchase = {
                            navController.navigate("finish_purchase")
                        },
                        onBack = { navController.popBackStack() }
                    )
                }
            }

            composable("finish_purchase") {
                val result = currentCheckoutResult
                if (result != null) {
                    FinishPurchaseScreen(
                        merchant = result.merchant,
                        initialCardId = result.primaryRecommendation.winner.cardId,
                        initialAmountCad = result.scoredContext.amountCad,
                        walletCards = catalogue.cards.filter { ownerState.ownedCardIds.contains(it.cardId) },
                        onSavePurchase = { cardId, amount ->
                            scope.launch {
                                val latestRecord = predictionRecords.firstOrNull()
                                val purchaseId = latestRecord?.purchaseWithObservation?.purchase?.id
                                if (purchaseId != null) {
                                    repository.updatePurchase(
                                        purchaseId = purchaseId,
                                        cardUsedId = cardId,
                                        cardSource = CaptureSource.AT_TILL,
                                        amountCad = amount,
                                        amountSource = CaptureSource.AT_TILL
                                    )
                                }
                            }
                            navController.navigate("home") {
                                popUpTo("home") { inclusive = true }
                            }
                        },
                        onBack = { navController.popBackStack() }
                    )
                }
            }

            composable("reconcile") {
                val unreconciled = predictionRecords.filter {
                    val p = it.purchaseWithObservation?.purchase
                    p != null && it.purchaseWithObservation?.observation == null
                }
                ReconcileScreen(
                    unreconciledRecords = unreconciled,
                    availableCategories = CategoryMapper.observableCategories(catalogue),
                    onConfirmReconciliation = { purchaseId, observedCategory, units, missClass ->
                        scope.launch {
                            repository.confirmObservation(
                                purchaseId = purchaseId,
                                observedCategory = observedCategory,
                                observedRewardUnits = units,
                                missClass = missClass
                            )
                        }
                    },
                    onBack = { navController.popBackStack() }
                )
            }

            composable("dashboard") {
                DashboardScreen(
                    metrics = metrics,
                    valueRecovered = valueRecovered,
                    onBack = { navController.popBackStack() }
                )
            }

            composable("wallet_health") {
                WalletHealthScreen(
                    portfolioAnalysis = portfolioAnalysis,
                    acquisitionAnalysis = acquisitionAnalysis,
                    onBack = { navController.popBackStack() }
                )
            }

            composable("benefits") {
                BenefitsReferenceScreen(
                    catalogue = benefitsCatalogue,
                    walletCardIds = ownerState.ownedCardIds,
                    onBack = { navController.popBackStack() }
                )
            }
        }
    }
}
