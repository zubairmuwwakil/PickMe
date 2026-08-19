package com.cardcopilot.store.db

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

@Database(
    entities = [
        StoredPredictionEntity::class,
        StoredPurchaseEntity::class,
        StoredObservationEntity::class,
        StoredMerchantEntity::class,
        DiscoveryCacheEntity::class
    ],
    version = 1,
    exportSchema = false
)
abstract class CardCopilotDatabase : RoomDatabase() {
    abstract fun predictionDao(): PredictionDao
    abstract fun purchaseDao(): PurchaseDao
    abstract fun observationDao(): ObservationDao
    abstract fun merchantDao(): MerchantDao
    abstract fun discoveryCacheDao(): DiscoveryCacheDao

    companion object {
        @Volatile
        private var INSTANCE: CardCopilotDatabase? = null

        fun getInstance(context: Context): CardCopilotDatabase {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: Room.databaseBuilder(
                    context.applicationContext,
                    CardCopilotDatabase::class.java,
                    "card_copilot.db"
                ).build().also { INSTANCE = it }
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
