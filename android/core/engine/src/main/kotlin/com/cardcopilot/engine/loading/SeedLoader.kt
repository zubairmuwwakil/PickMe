package com.cardcopilot.engine.loading

import com.cardcopilot.engine.models.BenefitsCatalogue
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
    const val SUPPORTED_CATALOGUE_MAJOR_VERSION = 1

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

    fun loadCandidateCatalogue(): Catalogue {
        val catalogue: Catalogue = load("candidate-catalogue")
        validate(catalogue.catalogueVersion)
        return catalogue
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
