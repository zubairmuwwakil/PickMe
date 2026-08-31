package com.cardcopilot.store.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [
        StoredPredictionEntity::class,
        StoredPurchaseEntity::class,
        StoredObservationEntity::class,
        StoredMerchantEntity::class,
        DiscoveryCacheEntity::class
    ],
    version = 2,
    exportSchema = false
)
abstract class CardCopilotDatabase : RoomDatabase() {
    abstract fun predictionDao(): PredictionDao
    abstract fun purchaseDao(): PurchaseDao
    abstract fun observationDao(): ObservationDao
    abstract fun merchantDao(): MerchantDao
    abstract fun discoveryCacheDao(): DiscoveryCacheDao

    companion object {
        val MIGRATION_1_2: Migration = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                val additions = listOf(
                    "predictions|rawCategory TEXT", "predictions|categoryTaxonomyVersion TEXT",
                    "predictions|categoryConfidenceScore REAL", "predictions|merchantCategoryCode INTEGER",
                    "predictions|merchantGroupID TEXT", "purchases|rawCategoryAtPurchase TEXT",
                    "purchases|categoryTaxonomyVersion TEXT", "purchases|categoryConfidenceScore REAL",
                    "purchases|merchantCategoryCode INTEGER", "purchases|merchantGroupID TEXT",
                    "observations|rawObservedCategory TEXT", "observations|categoryTaxonomyVersion TEXT",
                    "observations|categorySourceRaw TEXT", "observations|categoryConfidenceScore REAL",
                    "observations|observedMerchantCategoryCode INTEGER", "merchants|rawCategory TEXT",
                    "merchants|merchantCategoryCode INTEGER", "merchants|merchantGroupID TEXT",
                    "merchants|categoryTaxonomyVersion TEXT", "merchants|categoryConfidenceScore REAL",
                    "merchants|lastConfirmedAt INTEGER"
                )
                additions.forEach { addition ->
                    val (table, column) = addition.split('|', limit = 2)
                    db.execSQL("ALTER TABLE $table ADD COLUMN $column")
                }
            }
        }
        @Volatile
        private var INSTANCE: CardCopilotDatabase? = null

        fun getInstance(context: Context): CardCopilotDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    CardCopilotDatabase::class.java,
                    "card_copilot.db"
                ).addMigrations(MIGRATION_1_2).build().also { INSTANCE = it }
            }
        }

        fun createInMemory(context: Context): CardCopilotDatabase {
            return Room.inMemoryDatabaseBuilder(
                context.applicationContext,
                CardCopilotDatabase::class.java
            ).allowMainThreadQueries().build()
        }
    }
}
