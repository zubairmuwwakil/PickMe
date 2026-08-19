package com.cardcopilot.store

import com.cardcopilot.store.models.ConfidenceSource
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

class CategoryMapperTest {

    @Test
    fun testBrandPriorsMatchAccurately() {
        val ct = CategoryMapper.predict(poiCategoryRaw = null, merchantName = "Canadian Tire - Eaton Centre")
        assertEquals("ctFamily", ct.category)
        assertEquals(ConfidenceSource.BRAND_PRIOR, ct.confidenceSource)

        val costco = CategoryMapper.predict(poiCategoryRaw = null, merchantName = "Costco Wholesale #541")
        assertEquals("wholesaleClub", costco.category)
        assertEquals(ConfidenceSource.BRAND_PRIOR, costco.confidenceSource)

        val marriott = CategoryMapper.predict(poiCategoryRaw = null, merchantName = "Toronto Marriott Downtown Eaton Centre Hotel")
        assertEquals("marriottDirect", marriott.category)
        assertEquals(ConfidenceSource.BRAND_PRIOR, marriott.confidenceSource)
    }

    @Test
    fun testPoiCategoryMapping() {
        val grocery = CategoryMapper.predict(poiCategoryRaw = "MKPOICategoryFoodMarket", merchantName = "Loblaws Queen St")
        assertEquals("grocery", grocery.category)
        assertEquals(ConfidenceSource.MAP_KIT_CATEGORY, grocery.confidenceSource)
        assertEquals(listOf("grocery"), grocery.candidates)

        val walmart = CategoryMapper.predict(poiCategoryRaw = "MKPOICategoryFoodMarket", merchantName = "Walmart Supercentre")
        assertEquals("grocery", walmart.category)
        assertEquals(listOf("grocery", "other"), walmart.candidates)

        val gas = CategoryMapper.predict(poiCategoryRaw = "MKPOICategoryGasStation", merchantName = "Shell")
        assertEquals("gasStation", gas.category)
        assertEquals(listOf("gasStation", "other"), gas.candidates)

        val restaurant = CategoryMapper.predict(poiCategoryRaw = "MKPOICategoryRestaurant", merchantName = "Pai Northern Thai Kitchen")
        assertEquals("dining", restaurant.category)

        val pharmacy = CategoryMapper.predict(poiCategoryRaw = "MKPOICategoryPharmacy", merchantName = "Shoppers Drug Mart")
        assertEquals("drugStore", pharmacy.category)
    }

    @Test
    fun testCanonicalEngineBrands() {
        assertEquals("costco", CategoryMapper.canonicalEngineBrand("Costco Wholesale"))
        assertEquals("walmart", CategoryMapper.canonicalEngineBrand("Walmart Supercentre"))
        assertEquals("canadian-tire", CategoryMapper.canonicalEngineBrand("Canadian Tire"))
        assertEquals("marriott", CategoryMapper.canonicalEngineBrand("JW Marriott"))
        assertEquals("loblaws", CategoryMapper.canonicalEngineBrand("Loblaws"))
        assertEquals("netflix", CategoryMapper.canonicalEngineBrand("Netflix.com"))
        assertEquals(null, CategoryMapper.canonicalEngineBrand("Unknown Corner Store"))
    }
}
