package com.cardcopilot.store.db

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import java.util.UUID

@Entity(
    tableName = "predictions",
    indices = [Index("merchantIdentifier"), Index("recordedAt")]
)
data class StoredPredictionEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val recordedAt: Long = System.currentTimeMillis(),
    val merchantName: String,
    val merchantIdentifier: String? = null,
    val predictedCategory: String,
    val confidenceSourceRaw: String,
    val winnerCardId: String,
    val winnerValueCad: Double,
    val predictedRewardUnits: Double? = null,
    val predictedRewardUnitKind: String? = null,
    val defaultCardValueCad: Double? = null,
    val winnerRuleId: String? = null,
    val runnerUpCardId: String? = null,
    val runnerUpValueCad: Double? = null,
    val scoredAmountCad: Double? = null,
    val valuationCentsPerPoint: Double? = null,
    val rawCategory: String? = null,
    val categoryTaxonomyVersion: String? = null,
    val categoryConfidenceScore: Double? = null,
    val merchantCategoryCode: Int? = null,
    val merchantGroupID: String? = null,
    val headline: String
)

@Entity(
    tableName = "purchases",
    foreignKeys = [
        ForeignKey(
            entity = StoredPredictionEntity::class,
            parentColumns = ["id"],
            childColumns = ["predictionId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("predictionId")]
)
data class StoredPurchaseEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val predictionId: String,
    val createdAt: Long = System.currentTimeMillis(),
    var cardUsedId: String? = null,
    var cardSourceRaw: String? = null,
    var amountCad: Double? = null,
    var amountSourceRaw: String? = null,
    var completedAt: Long? = null,
    var rawCategoryAtPurchase: String? = null,
    var categoryTaxonomyVersion: String? = null,
    var categoryConfidenceScore: Double? = null,
    var merchantCategoryCode: Int? = null,
    var merchantGroupID: String? = null
)

@Entity(
    tableName = "observations",
    foreignKeys = [
        ForeignKey(
            entity = StoredPurchaseEntity::class,
            parentColumns = ["id"],
            childColumns = ["purchaseId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index("purchaseId")]
)
data class StoredObservationEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val purchaseId: String,
    val confirmedAt: Long = System.currentTimeMillis(),
    val observedCategory: String,
    val observedRewardUnits: Double? = null,
    val missClassRaw: String? = null,
    val note: String? = null,
    val rawObservedCategory: String? = null,
    val categoryTaxonomyVersion: String? = null,
    val categorySourceRaw: String? = null,
    val categoryConfidenceScore: Double? = null,
    val observedMerchantCategoryCode: Int? = null
)

@Entity(
    tableName = "merchants",
    indices = [Index("name"), Index("identifier"), Index("lastSeenAt")]
)
data class StoredMerchantEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val name: String,
    val identifier: String? = null,
    val poiCategoryRaw: String? = null,
    val latitude: Double = 0.0,
    val longitude: Double = 0.0,
    var confirmedCategory: String? = null,
    var confirmationCount: Int = 0,
    var lastSeenAt: Long = System.currentTimeMillis(),
    var rawCategory: String? = null,
    var merchantCategoryCode: Int? = null,
    var merchantGroupID: String? = null,
    var categoryTaxonomyVersion: String? = null,
    var categoryConfidenceScore: Double? = null,
    var lastConfirmedAt: Long? = null
)

@Entity(tableName = "discovery_cache")
data class DiscoveryCacheEntity(
    @PrimaryKey val cellKey: String,
    val queriedAt: Long = System.currentTimeMillis(),
    val merchantCount: Int = 0
)
