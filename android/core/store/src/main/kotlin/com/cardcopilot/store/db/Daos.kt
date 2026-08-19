package com.cardcopilot.store.db

import androidx.room.Dao
import androidx.room.Embedded
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Relation
import androidx.room.Transaction
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

data class PurchaseWithObservation(
    @Embedded val purchase: StoredPurchaseEntity,
    @Relation(
        parentColumn = "id",
        entityColumn = "purchaseId"
    )
    val observation: StoredObservationEntity?
)

data class PredictionRecord(
    @Embedded val prediction: StoredPredictionEntity,
    @Relation(
        entity = StoredPurchaseEntity::class,
        parentColumn = "id",
        entityColumn = "predictionId"
    )
    val purchaseWithObservation: PurchaseWithObservation?
)

@Dao
interface PredictionDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(prediction: StoredPredictionEntity)

    @Query("SELECT * FROM predictions WHERE id = :id")
    suspend fun getById(id: String): StoredPredictionEntity?

    @Transaction
    @Query("SELECT * FROM predictions ORDER BY recordedAt DESC")
    fun observeAllRecords(): Flow<List<PredictionRecord>>

    @Transaction
    @Query("SELECT * FROM predictions ORDER BY recordedAt DESC")
    suspend fun getAllRecords(): List<PredictionRecord>

    @Query("DELETE FROM predictions")
    suspend fun deleteAll()
}

@Dao
interface PurchaseDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(purchase: StoredPurchaseEntity)

    @Update
    suspend fun update(purchase: StoredPurchaseEntity)

    @Query("SELECT * FROM purchases WHERE id = :id")
    suspend fun getById(id: String): StoredPurchaseEntity?

    @Query("SELECT * FROM purchases WHERE predictionId = :predictionId")
    suspend fun getByPredictionId(predictionId: String): StoredPurchaseEntity?

    @Query("SELECT * FROM purchases WHERE completedAt IS NULL")
    fun observeIncomplete(): Flow<List<StoredPurchaseEntity>>

    @Query("DELETE FROM purchases")
    suspend fun deleteAll()
}

@Dao
interface ObservationDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(observation: StoredObservationEntity)

    @Query("SELECT * FROM observations WHERE purchaseId = :purchaseId")
    suspend fun getByPurchaseId(purchaseId: String): StoredObservationEntity?

    @Query("DELETE FROM observations")
    suspend fun deleteAll()
}

@Dao
interface MerchantDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertOrUpdate(merchant: StoredMerchantEntity)

    @Query("SELECT * FROM merchants WHERE identifier = :identifier LIMIT 1")
    suspend fun findByIdentifier(identifier: String): StoredMerchantEntity?

    @Query("SELECT * FROM merchants WHERE LOWER(name) = LOWER(:name) LIMIT 1")
    suspend fun findByName(name: String): StoredMerchantEntity?

    @Query("SELECT * FROM merchants ORDER BY lastSeenAt DESC")
    fun observeAll(): Flow<List<StoredMerchantEntity>>

    @Query("SELECT * FROM merchants ORDER BY lastSeenAt DESC")
    suspend fun getAll(): List<StoredMerchantEntity>

    @Query("DELETE FROM merchants")
    suspend fun deleteAll()
}

@Dao
interface DiscoveryCacheDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(cache: DiscoveryCacheEntity)

    @Query("SELECT * FROM discovery_cache WHERE cellKey = :cellKey LIMIT 1")
    suspend fun getByCellKey(cellKey: String): DiscoveryCacheEntity?

    @Query("SELECT COUNT(*) FROM discovery_cache WHERE queriedAt >= :sinceTimestamp")
    suspend fun countQueriesSince(sinceTimestamp: Long): Int

    @Query("DELETE FROM discovery_cache")
    suspend fun deleteAll()
}
