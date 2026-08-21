package com.cardcopilot.engine

import com.cardcopilot.engine.loading.SeedLoader
import com.cardcopilot.engine.models.CashBackValuation
import com.cardcopilot.engine.models.CroValuation
import com.cardcopilot.engine.models.CtMoneyValuation
import com.cardcopilot.engine.models.PointValuation
import com.cardcopilot.engine.models.ProgramValuation
import com.cardcopilot.engine.models.Valuations
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertThrows
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

/**
 * The Kotlin twin of `Engine/Tests/CardCopilotEngineTests/ProgramValuationTests.swift`. The two
 * engines read the same owner-state.json off the same wire format, so every shape asserted there
 * has to hold here — a divergence is not a Kotlin bug, it is a broken contract.
 */
class ProgramValuationTest {

    /** The production instance: the discriminator lives in its configuration, not in a test. */
    private val json: Json = SeedLoader.json

    private fun roundTrip(value: ProgramValuation): ProgramValuation =
        json.decodeFromString(ProgramValuation.serializer(), json.encodeToString(ProgramValuation.serializer(), value))

    @Test
    fun pointsRoundTrips() {
        val p = PointValuation(
            centsPerPoint = 1.0,
            floorCentsPerPoint = 0.9,
            aspirationalCentsPerPoint = 2.2,
            basis = "cash floor"
        )
        assertEquals(p, roundTrip(p))
    }

    @Test
    fun cashbackRoundTrips() {
        val v = CashBackValuation(cadPerDollar = 1.0)
        assertEquals(v, roundTrip(v))
    }

    @Test
    fun ctMoneyRoundTrips() {
        val v = CtMoneyValuation(
            cadPerUnit = 1.0,
            optionalUsabilityFactor = 0.95,
            usabilityFactorApplied = true
        )
        assertEquals(v, roundTrip(v))
    }

    @Test
    fun croRoundTrips() {
        val v = CroValuation(
            redemptionModel = "reward-currency",
            faceValueFactorIfAutoSold = 1.0,
            defaultHeldRiskFactor = 0.8
        )
        assertEquals(v, roundTrip(v))
    }

    @Test
    fun decodesFromModelDiscriminator() {
        val decoded = json.decodeFromString(
            ProgramValuation.serializer(),
            """{"model":"points","centsPerPoint":1.5}"""
        )
        assertTrue(decoded is PointValuation, "expected points, got $decoded")
        assertEquals(1.5, (decoded as PointValuation).centsPerPoint)
    }

    /**
     * An unknown model is a hard decode failure, not a silent default. A valuation the engine
     * cannot interpret must never be mistaken for one it can.
     */
    @Test
    fun unknownModelIsADecodeError() {
        assertThrows(SerializationException::class.java) {
            json.decodeFromString(
                ProgramValuation.serializer(),
                """{"model":"cryptoKittyPoints","centsPerPoint":1}"""
            )
        }
    }

    /**
     * The discriminator sits at the same JSON level as the payload, so `cro`'s own model field
     * had to be renamed out of the way. Encoding must emit both, distinctly. kotlinx would throw
     * outright if the two collided, which is the same defence the Swift twin gets from review.
     */
    @Test
    fun croEncodesBothTheDiscriminatorAndItsRedemptionModel() {
        val v = CroValuation(
            redemptionModel = "reward-currency",
            faceValueFactorIfAutoSold = 1.0,
            defaultHeldRiskFactor = 0.8
        )
        val encoded = json.encodeToJsonElement(ProgramValuation.serializer(), v) as JsonObject
        assertEquals("cro", encoded["model"]?.jsonPrimitive?.content)
        assertEquals("reward-currency", encoded["redemptionModel"]?.jsonPrimitive?.content)
    }

    /**
     * Every wallet already on a device is written in the legacy shape. Failing to read it would
     * evict the owner's declared valuations on upgrade.
     */
    @Test
    fun legacyNamedFieldShapeStillDecodes() {
        val legacy = """
        {
          "amexMembershipRewards": {"centsPerPoint": 1.0, "floorCentsPerPoint": 1.0},
          "marriottBonvoy": {"centsPerPoint": 0.8},
          "mbnaRewards": {"centsPerPoint": 1.0},
          "ctMoney": {"cadPerUnit": 1.0, "optionalUsabilityFactor": 0.95,
                      "usabilityFactorApplied": true},
          "cro": {"redemptionModel": "reward-currency", "faceValueFactorIfAutoSold": 1.0,
                  "defaultHeldRiskFactor": 0.8},
          "cashBack": {"cadPerDollar": 1.0}
        }
        """.trimIndent()
        val v = json.decodeFromString(Valuations.serializer(), legacy)

        assertEquals(1.0, (v["amexMembershipRewards"] as PointValuation).centsPerPoint)
        assertEquals(1.0, (v["cashback"] as CashBackValuation).cadPerDollar)
        assertEquals(0.8, (v["cro"] as CroValuation).defaultHeldRiskFactor)
    }

    @Test
    fun newProgramsShapeDecodes() {
        val modern = """{"programs": {"aeroplan": {"model": "points", "centsPerPoint": 1.9}}}"""
        val v = json.decodeFromString(Valuations.serializer(), modern)
        assertEquals(1.9, (v["aeroplan"] as PointValuation).centsPerPoint)
    }

    /** Legacy in, modern out — so a wallet upgrades itself the first time it is written back. */
    @Test
    fun legacyShapeReEncodesAsProgramsDictionary() {
        val decoded = json.decodeFromString(Valuations.serializer(), """{"cashBack": {"cadPerDollar": 1.0}}""")
        val reencoded = json.encodeToJsonElement(Valuations.serializer(), decoded) as JsonObject
        assertNotNull(reencoded["programs"])
        assertNull(reencoded["cashBack"])
    }

    /**
     * The legacy file's `cashBack` key is `cashback` as a programId — the catalogue spells it
     * lowercase. A mismatch here would silently unvalue every cash-back card.
     */
    @Test
    fun legacyCashBackKeyMapsToCatalogueProgramId() {
        val v = json.decodeFromString(Valuations.serializer(), """{"cashBack": {"cadPerDollar": 1.0}}""")
        assertNotNull(v["cashback"], "catalogue programId is 'cashback', not 'cashBack'")
    }

    /**
     * owner-state.json carries a `rogersEligibleServiceRedemption` block that is not a catalogue
     * programId and has no ProgramValuation model. It must be ignored, not a decode failure.
     */
    @Test
    fun unknownLegacyKeyIsIgnoredNotFatal() {
        val legacy = """
        {"cashBack": {"cadPerDollar": 1.0},
         "rogersEligibleServiceRedemption": {"redemptionFactor": 1.5, "appliedAtCheckout": false}}
        """.trimIndent()
        val v = json.decodeFromString(Valuations.serializer(), legacy)
        assertNotNull(v["cashback"])
        assertNull(v["rogersEligibleServiceRedemption"])
    }

    /**
     * A malformed modern block must throw rather than fall through to the legacy branch and
     * quietly produce an empty wallet. Silence here is indistinguishable from "the owner values
     * nothing", which is how a wallet loses every valuation on one bad save.
     */
    @Test
    fun malformedProgramsBlockThrowsRatherThanDecodingEmpty() {
        assertThrows(SerializationException::class.java) {
            json.decodeFromString(
                Valuations.serializer(),
                """{"programs": {"aeroplan": {"model": "points"}}}"""
            )
        }
    }

    /**
     * A full round trip through the modern shape must be lossless, or a wallet degrades a
     * little on every save.
     */
    @Test
    fun modernShapeRoundTripsLosslessly() {
        val original = Valuations(
            mapOf(
                "amexMembershipRewards" to PointValuation(
                    centsPerPoint = 1.0,
                    floorCentsPerPoint = 1.0,
                    aspirationalCentsPerPoint = 2.2,
                    basis = "cash floor"
                ),
                "ctMoney" to CtMoneyValuation(
                    cadPerUnit = 1.0,
                    optionalUsabilityFactor = 0.95,
                    usabilityFactorApplied = true
                ),
                "cashback" to CashBackValuation(cadPerDollar = 1.0)
            )
        )
        val decoded = json.decodeFromString(
            Valuations.serializer(),
            json.encodeToString(Valuations.serializer(), original)
        )
        assertEquals(original, decoded)
    }

    /**
     * The shipped owner state is still written in the legacy shape, so this is the live proof
     * that the compatibility branch reads a real file and loses nothing. If this drops to five
     * entries, some behaviour test somewhere is silently scoring a program at $0.00.
     */
    @Test
    fun shippedOwnerStateDecodesAllSixLegacyPrograms() {
        val v = SeedLoader.loadOwnerState().valuationsCad
        assertEquals(
            setOf(
                "amexMembershipRewards", "marriottBonvoy", "mbnaRewards",
                "ctMoney", "cro", "cashback"
            ),
            v.programs.keys
        )
        assertNotNull(
            v.points("amexMembershipRewards"),
            "the fixture pin writes through this accessor; a null here is a silent no-op"
        )
    }

    /**
     * programs.json is a resource of this module, and every programId the catalogue declares must
     * resolve in it — the Kotlin end of the ratchet Swift's CatalogueIntegrityTests holds.
     */
    @Test
    fun everyCatalogueProgramIdHasACatalogueDefault() {
        val defaults = SeedLoader.programValuationDefaults
        val declared = (SeedLoader.loadCatalogue().cards + SeedLoader.loadCandidateCatalogue().cards)
            .map { it.program.programId }
            .toSortedSet()
        val unvalued = declared.filter { it !in defaults }
        assertTrue(unvalued.isEmpty(), "catalogue programIds with no valuation: $unvalued")
    }

    /**
     * The direction of the merge is the whole contract: the catalogue may supply a number where
     * the owner has none, and must never overrule one they declared.
     */
    @Test
    fun ownerDeclaredValuationsSurviveTheCatalogueMerge() {
        val owner = SeedLoader.loadOwnerState()
        val declaredAmex = owner.valuationsCad.points("amexMembershipRewards")!!.centsPerPoint
        val engine = com.cardcopilot.engine.engine.RecommendationEngine(SeedLoader.loadCatalogue(), owner)

        assertEquals(
            declaredAmex,
            engine.ownerState.valuationsCad.points("amexMembershipRewards")!!.centsPerPoint,
            "the catalogue default must not overrule an owner-declared valuation"
        )
        assertNotNull(
            engine.ownerState.valuationsCad["aeroplan"],
            "a program the owner never declared must pick up its catalogue default"
        )
    }
}
