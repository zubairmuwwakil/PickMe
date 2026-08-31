package com.cardcopilot.store

import com.cardcopilot.engine.models.Catalogue
import com.cardcopilot.engine.models.CategoryTaxonomy
import com.cardcopilot.engine.models.Network
import com.cardcopilot.store.db.StoredMerchantEntity
import com.cardcopilot.store.models.CategoryPrediction
import com.cardcopilot.store.models.ConfidenceSource
import java.text.Normalizer
import java.util.Locale

object CategoryMapper {

    private data class BrandPrior(
        val normalizedNeedle: String,
        val category: String
    )

    private val brandPriors: List<BrandPrior> = listOf(
        BrandPrior(normalizedMerchantName("canadian tire"), "ctFamily"),
        BrandPrior(normalizedMerchantName("sport chek"), "ctFamily"),
        BrandPrior(normalizedMerchantName("mark's"), "ctFamily"),
        BrandPrior(normalizedMerchantName("atmosphere"), "ctFamily"),
        BrandPrior(normalizedMerchantName("party city"), "ctFamily"),
        BrandPrior(normalizedMerchantName("pro hockey life"), "ctFamily"),
        BrandPrior(normalizedMerchantName("sports experts"), "ctFamily"),
        BrandPrior(normalizedMerchantName("costco"), "wholesaleClub"),
        BrandPrior(normalizedMerchantName("marriott"), "marriottDirect")
    )

    fun predict(poiCategoryRaw: String?, merchantName: String, merchantCategoryCode: Int? = null): CategoryPrediction {
        val mccCategory = observedMccCategory(merchantCategoryCode)
        if (mccCategory != null) {
            return CategoryPrediction(mccCategory, ConfidenceSource.OBSERVED_MCC, listOf(mccCategory),
                rawCategory = poiCategoryRaw, merchantCategoryCode = merchantCategoryCode)
        }
        val normalizedMerchant = normalizedMerchantName(merchantName)
        val prior = brandPriors.firstOrNull { normalizedMerchant.contains(it.normalizedNeedle) }
        if (prior != null) {
            return CategoryPrediction(
                category = prior.category,
                confidenceSource = ConfidenceSource.BRAND_PRIOR,
                candidates = listOf(prior.category)
            )
        }

        return when (canonicalPoiCategory(poiCategoryRaw)) {
            "foodmarket" -> {
                if (isWalmart(normalizedMerchant)) {
                    CategoryPrediction("grocery", ConfidenceSource.MAP_KIT_CATEGORY, listOf("grocery", "other"))
                } else {
                    CategoryPrediction("grocery", ConfidenceSource.MAP_KIT_CATEGORY, listOf("grocery"))
                }
            }
            "gasstation" -> CategoryPrediction("gasStation", ConfidenceSource.MAP_KIT_CATEGORY, listOf("gasStation", "other"))
            "restaurant", "cafe", "bakery" -> CategoryPrediction("dining", ConfidenceSource.MAP_KIT_CATEGORY, listOf("dining"))
            "pharmacy" -> CategoryPrediction("drugStore", ConfidenceSource.MAP_KIT_CATEGORY, listOf("drugStore"))
            "publictransport" -> CategoryPrediction("transit", ConfidenceSource.MAP_KIT_CATEGORY, listOf("transit"))
            "hotel" -> CategoryPrediction("lodging", ConfidenceSource.MAP_KIT_CATEGORY, listOf("lodging"))
            "movietheater" -> CategoryPrediction("entertainment", ConfidenceSource.MAP_KIT_CATEGORY, listOf("entertainment"))
            "fitnesscenter" -> CategoryPrediction("fitness", ConfidenceSource.MAP_KIT_CATEGORY, listOf("fitness"))
            "store" -> CategoryPrediction("other", ConfidenceSource.MAP_KIT_CATEGORY, listOf("other", "grocery"))
            else -> CategoryPrediction("other", ConfidenceSource.FALLBACK, listOf("other"))
        }
    }

    fun predictionForKnownMerchant(merchant: StoredMerchantEntity): CategoryPrediction {
        val confirmed = merchant.confirmedCategory
        if (confirmed != null) {
            val category = CategoryTaxonomy.canonicalId(confirmed)
            return CategoryPrediction(
                category = category,
                confidenceSource = if (merchant.confirmationCount >= 2) ConfidenceSource.REPEATED_TERMINAL else ConfidenceSource.OWNER_CONFIRMED_TERMINAL,
                candidates = listOf(category),
                rawCategory = merchant.rawCategory ?: merchant.poiCategoryRaw,
                merchantCategoryCode = merchant.merchantCategoryCode,
                merchantGroupID = merchant.merchantGroupID,
                taxonomyVersion = merchant.categoryTaxonomyVersion ?: CategoryTaxonomy.taxonomyVersion
            )
        }
        return predict(merchant.poiCategoryRaw, merchant.name, merchant.merchantCategoryCode)
    }

    private fun observedMccCategory(mcc: Int?): String? = when (mcc) {
        4111, 4121 -> "transit"
        5411 -> "grocery"
        5541, 5542 -> "gasStation"
        5812, 5814 -> "dining"
        5912 -> "drugStore"
        7011 -> "lodging"
        7512 -> "carRental"
        else -> null
    }

    fun canonicalEngineBrand(merchantName: String): String? {
        val n = merchantName.lowercase(Locale.ROOT)
        return when {
            n.contains("costco") -> "costco"
            n.contains("walmart") -> "walmart"
            n.contains("canadian tire") -> "canadian-tire"
            n.contains("marriott") -> "marriott"
            n.contains("loblaws") -> "loblaws"
            n.contains("netflix") -> "netflix"
            else -> null
        }
    }

    fun knownAcceptedNetworks(brand: String?): Set<Network> {
        return if (brand == "costco") setOf(Network.MASTERCARD) else setOf(Network.AMEX, Network.VISA, Network.MASTERCARD)
    }

    val categoryAmountEstimates: Map<String, Double> = mapOf(
        "grocery" to 60.0,
        "dining" to 35.0,
        "gasStation" to 55.0,
        "drugStore" to 25.0,
        "streaming" to 15.0,
        "ctFamily" to 80.0,
        "wholesaleClub" to 150.0,
        "marriottDirect" to 250.0
    )

    const val FALLBACK_AMOUNT_ESTIMATE: Double = 50.0

    private fun isWalmart(normalizedMerchant: String): Boolean = normalizedMerchant.contains("walmart")

    private fun canonicalPoiCategory(raw: String?): String? {
        if (raw == null) return null
        val normalized = Normalizer.normalize(raw, Normalizer.Form.NFD)
            .replace("\\p{InCombiningDiacriticalMarks}+".toRegex(), "")
        val compact = normalized.filter { it.isLetterOrDigit() }.lowercase(Locale.ROOT)
        if (compact.startsWith("mkpoicategory")) {
            return compact.removePrefix("mkpoicategory")
        }
        return compact.ifEmpty { null }
    }

    private fun normalizedMerchantName(merchantName: String): String {
        val normalized = Normalizer.normalize(merchantName, Normalizer.Form.NFD)
            .replace("\\p{InCombiningDiacriticalMarks}+".toRegex(), "")
        val sb = StringBuilder()
        var lastWasSpace = true
        for (ch in normalized) {
            if (ch.isLetterOrDigit()) {
                sb.append(ch.lowercaseChar())
                lastWasSpace = false
            } else if (!lastWasSpace) {
                sb.append(' ')
                lastWasSpace = true
            }
        }
        return sb.toString().trim()
    }

    private val unscoredPredictableCategories = listOf(
        "other", "wholesaleClub", "drugStore", "entertainment", "fitness"
    )

    private val ruleSideMarkers = CategoryTaxonomy.ruleSideCategoryIds

    fun observableCategories(catalogue: Catalogue): List<String> {
        val fromRules = catalogue.cards.flatMap { it.earnRules }.mapNotNull { it.predicate.categories }
            .flatten().map(CategoryTaxonomy::canonicalId)
        return (fromRules + unscoredPredictableCategories - ruleSideMarkers).toSet().toList().sorted()
    }

    fun categoryDisplayName(category: String): String {
        return CategoryTaxonomy.displayName(category)
    }
}
