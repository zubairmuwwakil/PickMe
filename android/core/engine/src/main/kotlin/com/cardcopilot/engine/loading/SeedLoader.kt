package com.cardcopilot.engine.loading

import com.cardcopilot.engine.models.BenefitsCatalogue
import com.cardcopilot.engine.models.CandidateSet
import com.cardcopilot.engine.models.Catalogue
import com.cardcopilot.engine.models.OwnerState
import com.cardcopilot.engine.models.ProgramCatalogue
import com.cardcopilot.engine.models.ProgramValuation
import kotlinx.serialization.json.Json

sealed class SeedLoaderException(message: String) : Exception(message) {
    class ResourceMissing(name: String) : SeedLoaderException("Resource missing: $name.json")
    class UnsupportedCatalogueVersion(version: String) : SeedLoaderException("Unsupported catalogue version: $version")
}

object SeedLoader {
    // Bumped 1 -> 2 for the 2026-08-26 multi-market shape change (Money-shaped fee/credit
    // values, market/billingCurrency, spendNative replacing spendCad, calendarQuarter) — mirrors
    // Swift's SeedLoader.supportedCatalogueMajorVersion.
    const val SUPPORTED_CATALOGUE_MAJOR_VERSION = 2

    // candidate-catalogue.json became a list of cardIds in 2.0 (was full card definitions) —
    // mirrors Swift's SeedLoader.supportedCandidateCatalogueMajorVersion.
    const val SUPPORTED_CANDIDATE_CATALOGUE_MAJOR_VERSION = 2

    val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        // ProgramValuation puts its discriminator in the same object as the payload, under
        // `model` — the shape the Swift twin's hand-written Codable produces. Any Json instance
        // that decodes an OwnerState or a ProgramCatalogue needs this; the default `type` would
        // read every valuation as an unknown model.
        classDiscriminator = "model"
    }

    fun loadCatalogue(): Catalogue {
        val catalogue: Catalogue = load("card-catalogue")
        validate(catalogue.catalogueVersion)
        return catalogue
    }

    /**
     * Which catalogue products are researched acquisition candidates — IDs, not card
     * definitions (see [CandidateSet]'s doc comment). Pre-2026-08-24 Kotlin mistakenly decoded
     * this resource as a full [Catalogue]; it never carried that shape after the refactor, which
     * this fixes to mirror the Swift twin.
     */
    fun loadCandidateCatalogue(): CandidateSet {
        val candidates: CandidateSet = load("candidate-catalogue")
        val major = candidates.candidateCatalogueVersion.split(".", limit = 2).firstOrNull()?.toIntOrNull()
        if (major != SUPPORTED_CANDIDATE_CATALOGUE_MAJOR_VERSION) {
            throw SeedLoaderException.UnsupportedCatalogueVersion(candidates.candidateCatalogueVersion)
        }
        return candidates
    }

    fun loadOwnerState(): OwnerState {
        return load("owner-state")
    }

    fun loadBenefitsCatalogue(): BenefitsCatalogue {
        return load("benefits-catalogue")
    }

    /**
     * Catalogue-level default valuations. Owner state overrides any entry; a program present
     * here and absent from owner state is valued by this file rather than excluded.
     */
    fun loadPrograms(): ProgramCatalogue = load("programs")

    /**
     * Throws rather than falling back to an empty map. programs.json is a resource compiled into
     * the module, so failing to read it is a build or packaging fault, not a runtime condition an
     * owner can be in. Degrading to empty would unvalue every program the owner has not declared,
     * which is the exact failure this file exists to prevent.
     */
    val programValuationDefaults: Map<String, ProgramValuation> by lazy {
        try {
            loadPrograms().defaults
        } catch (e: Exception) {
            throw IllegalStateException("contracts/programs.json is unreadable", e)
        }
    }

    fun validate(catalogueVersion: String) {
        val majorComponent = catalogueVersion.split(".", limit = 2).firstOrNull()
        val major = majorComponent?.toIntOrNull()
        if (major != SUPPORTED_CATALOGUE_MAJOR_VERSION) {
            throw SeedLoaderException.UnsupportedCatalogueVersion(catalogueVersion)
        }
    }

    inline fun <reified T> load(name: String): T {
        val resourcePath = "/com/cardcopilot/engine/$name.json"
        val stream = SeedLoader::class.java.getResourceAsStream(resourcePath)
            ?: SeedLoader::class.java.classLoader.getResourceAsStream(resourcePath.removePrefix("/"))
            ?: throw SeedLoaderException.ResourceMissing(name)

        val content = stream.bufferedReader().use { it.readText() }
        return json.decodeFromString(content)
    }
}
