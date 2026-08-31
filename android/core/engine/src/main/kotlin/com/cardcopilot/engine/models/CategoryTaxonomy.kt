package com.cardcopilot.engine.models

import com.cardcopilot.engine.loading.SeedLoader
import java.text.Normalizer
import java.util.Locale
import kotlinx.serialization.Serializable

@Serializable
data class PurchaseCategoryDefinition(
    val id: String,
    val displayName: String,
    val parentID: String? = null,
    val merchantGroupID: String? = null,
    val aliases: List<String> = emptyList(),
)

@Serializable
data class PurchaseCategoryRegistry(
    val taxonomyVersion: String = "1.0",
    val categories: List<PurchaseCategoryDefinition> = emptyList(),
    val ruleSideCategories: List<PurchaseCategoryDefinition> = emptyList(),
)

/** Kotlin twin of Swift's canonical purchase-category boundary. */
object CategoryTaxonomy {
    private val registry by lazy(SeedLoader::loadPurchaseCategories)

    val purchaseCategoryIds: Set<String> by lazy { registry.categories.mapTo(mutableSetOf()) { it.id } }

    val taxonomyVersion: String get() = registry.taxonomyVersion

    val ruleSideCategoryIds: Set<String> by lazy {
        registry.ruleSideCategories.mapTo(mutableSetOf()) { it.id }
    }

    private val definitionsById: Map<String, PurchaseCategoryDefinition> by lazy {
        val definitions = registry.categories + registry.ruleSideCategories
        definitions.associateBy { it.id }.also {
            require(it.size == definitions.size) {
                "purchase-categories.json contains duplicate ids"
            }
        }
    }

    private val canonicalIdByCompactKey: Map<String, String> by lazy {
        buildMap {
            for (definition in registry.categories + registry.ruleSideCategories) {
                for (raw in listOf(definition.id) + definition.aliases) {
                    val key = compactKey(raw)
                    val existing = this[key]
                    require(existing == null || existing == definition.id) {
                        "Category alias '$raw' is ambiguous: $existing, ${definition.id}"
                    }
                    put(key, definition.id)
                }
            }
        }
    }

    fun canonicalId(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return trimmed
        return canonicalIdByCompactKey[compactKey(trimmed)] ?: trimmed
    }

    fun canonicalPurchaseId(raw: String): String? =
        canonicalId(raw).takeIf(purchaseCategoryIds::contains)

    fun parentIds(raw: String): List<String> {
        val result = mutableListOf<String>()
        val visited = mutableSetOf<String>()
        var current = canonicalId(raw)
        while (true) {
            val parent = definitionsById[current]?.parentID ?: break
            if (!visited.add(parent)) break
            result += parent
            current = parent
        }
        return result
    }

    fun merchantGroupId(raw: String): String? = definitionsById[canonicalId(raw)]?.merchantGroupID

    fun displayName(raw: String): String {
        val category = canonicalId(raw)
        return definitionsById[category]?.displayName ?: humanize(category)
    }

    private fun compactKey(raw: String): String = Normalizer
        .normalize(raw, Normalizer.Form.NFD)
        .replace("\\p{InCombiningDiacriticalMarks}+".toRegex(), "")
        .filter(Char::isLetterOrDigit)
        .lowercase(Locale.CANADA)

    private fun humanize(category: String): String {
        if (category.isEmpty()) return category
        val spaced = buildString {
            category.forEach { character ->
                if (character.isUpperCase() && isNotEmpty()) append(' ')
                append(character)
            }
        }
        return spaced.replaceFirstChar { it.uppercase(Locale.CANADA) }.lowercase()
            .replaceFirstChar { it.uppercase(Locale.CANADA) }
    }
}
