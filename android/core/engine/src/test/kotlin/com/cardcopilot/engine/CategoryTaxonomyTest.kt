package com.cardcopilot.engine

import com.cardcopilot.engine.models.CategoryTaxonomy
import com.cardcopilot.engine.loading.SeedLoader
import com.cardcopilot.engine.models.PurchaseContext
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Test

class CategoryTaxonomyTest {

    @Test
    fun `taxonomy is loaded from the published registry`() {
        val registry = SeedLoader.loadPurchaseCategories()
        assertEquals("1.0", registry.taxonomyVersion)
        assertEquals(25, registry.categories.size)
        assertEquals(registry.categories.map { it.id }.toSet(), CategoryTaxonomy.purchaseCategoryIds)
        assertEquals(
            registry.ruleSideCategories.map { it.id }.toSet(),
            CategoryTaxonomy.ruleSideCategoryIds,
        )
    }
    @Test
    fun aliasesResolveToCanonicalPurchaseIds() {
        assertEquals("grocery", CategoryTaxonomy.canonicalPurchaseId(" groceries "))
        assertEquals("householdUtilities", CategoryTaxonomy.canonicalPurchaseId("bills"))
        assertEquals("retailShopping", CategoryTaxonomy.canonicalPurchaseId("shopping"))
    }

    @Test
    fun predicateMarkersAreNotPersistablePurchaseCategories() {
        assertNull(CategoryTaxonomy.canonicalPurchaseId("recurring"))
        assertNull(CategoryTaxonomy.canonicalPurchaseId("ownerSelectedCategory"))
    }

    @Test
    fun purchaseContextsCanonicalizeAtTheEngineBoundary() {
        assertEquals(
            "gasStation",
            PurchaseContext(amountCad = 20.0, category = "gas").canonicalized().category
        )
    }

    @Test
    fun displayNamesUseSharedMetadata() {
        assertEquals("EV charging", CategoryTaxonomy.displayName("evCharging"))
        assertEquals("Utilities & telecom", CategoryTaxonomy.displayName("householdUtilities"))
    }
}
