package com.cardcopilot.engine

import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.isDirectory
import org.junit.jupiter.api.Assertions.assertArrayEquals
import org.junit.jupiter.api.Assertions.assertNotNull
import org.junit.jupiter.api.Test

class ContractsSyncTest {
    private val repoRoot: Path by lazy {
        generateSequence(Path.of("").toAbsolutePath()) { it.parent }
            .firstOrNull { candidate ->
                candidate.resolve("contracts").isDirectory() &&
                    candidate.resolve("android/core/engine").isDirectory()
            }
            ?: error("Could not find the PickMe repository root from ${Path.of("").toAbsolutePath()}")
    }

    private fun assertPackagedResourceMatchesContract(
        contractName: String,
        resourcePath: String,
    ) {
        val expected = Files.readAllBytes(repoRoot.resolve("contracts").resolve(contractName))
        val stream = javaClass.getResourceAsStream(resourcePath)
        assertNotNull(stream, "$resourcePath is missing from the Kotlin engine test classpath")
        val actual = requireNotNull(stream).use { it.readBytes() }

        assertArrayEquals(
            expected,
            actual,
            "$resourcePath has drifted from contracts/$contractName. " +
                "Run scripts/sync-contracts-into-android.sh from the repository root.",
        )
    }

    @Test
    fun `packaged card catalogue matches the published contract byte for byte`() {
        assertPackagedResourceMatchesContract(
            contractName = "card-catalogue.json",
            resourcePath = "/com/cardcopilot/engine/card-catalogue.json",
        )
    }

    @Test
    fun `packaged purchase categories match the published contract byte for byte`() {
        assertPackagedResourceMatchesContract(
            contractName = "purchase-categories.json",
            resourcePath = "/com/cardcopilot/engine/purchase-categories.json",
        )
    }

    @Test
    fun `packaged application requirements match the published contract byte for byte`() {
        assertPackagedResourceMatchesContract(
            contractName = "application-requirements.json",
            resourcePath = "/com/cardcopilot/engine/application-requirements.json",
        )
    }

    @Test
    fun `packaged application requirement fixtures match the published contract byte for byte`() {
        assertPackagedResourceMatchesContract(
            contractName = "application-requirements-fixtures.json",
            resourcePath = "/com/cardcopilot/engine/application-requirements-fixtures.json",
        )
    }

    @Test
    fun `packaged engine fixtures match the published contract byte for byte`() {
        assertPackagedResourceMatchesContract(
            contractName = "engine-fixtures.json",
            resourcePath = "/com/cardcopilot/engine/engine-fixtures.json",
        )
    }
}
