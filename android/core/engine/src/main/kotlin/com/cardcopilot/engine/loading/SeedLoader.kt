package com.cardcopilot.engine.loading

import com.cardcopilot.engine.models.BenefitsCatalogue
import com.cardcopilot.engine.models.Catalogue
import com.cardcopilot.engine.models.OwnerState
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
