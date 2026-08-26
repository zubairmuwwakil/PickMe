import Foundation
import SwiftData

/// Version 1 of the on-device store.
///
/// The models themselves are declared where they always were — `Models.swift` for the prediction
/// spine, `DiscoveryCache.swift` for the spatial cache — as extensions of this enum. Nesting them
/// is what lets a future V2 hold a *differently shaped* `StoredPrediction` at the same time as
/// this one, which is the prerequisite for any migration that is not purely additive. Declaring
/// V1 flat and namespacing later would mean performing that move under a shipped store.
///
/// Nesting is shape-preserving: SwiftData names an entity after the type's simple name, so
/// `CardCopilotSchemaV1.StoredPrediction` persists as `StoredPrediction`, exactly as the flat
/// declaration did. `SchemaVersionTests` pins that, against a baseline captured from the running
/// schema before the move.
///
/// Why this exists at all: the app previously built its container from a literal list of seven
/// types at the call site, with no version attached. SwiftData will silently perform a lightweight
/// migration when it can, and refuse to open the store when it cannot — and "cannot" includes
/// every rename and retype. The store holds `StoredPrediction`, the append-only log the accuracy
/// claim is measured against and the one record here that cannot be recomputed from anything else.
public enum CardCopilotSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    /// Every persisted type, in one place. The app builds its container from this rather than
    /// from a literal list, so there is exactly one thing to update when a model is added — and
    /// `SchemaVersionTests.testV1RegistersEveryModel` fails when it is not updated.
    public static var models: [any PersistentModel.Type] {
        [
            StoredPrediction.self,
            StoredPurchase.self,
            StoredObservation.self,
            StoredMerchant.self,
            ExploredCell.self,
            ShoppingArea.self,
            AreaMember.self,
        ]
    }
}

/// How owners are carried from one schema version to the next.
///
/// Empty `stages` is correct and not a placeholder: V1 is the first declared version, so there is
/// nothing to migrate *from*. It becomes load-bearing at V2, when a stage must be added here in
/// the same change that adds the new schema — a V2 with no stage is how a store gets orphaned.
///
/// Prefer `MigrationStage.lightweight` where the change qualifies (adding a property with a
/// default, adding a model, deleting a property). Reach for `.custom` only when data has to be
/// rewritten, and note that `.custom` is the case that genuinely needs both versions' types to
/// exist simultaneously — which is why the models are namespaced under their schema version.
public enum CardCopilotMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [CardCopilotSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}

// The current version's models are also reachable unqualified, so the ~195 references across the
// app and this package are unaffected by the nesting. When V2 arrives these aliases move to point
// at it, and that single edit is what "the current shape" means for every call site at once.
public typealias StoredPrediction = CardCopilotSchemaV1.StoredPrediction
public typealias StoredPurchase = CardCopilotSchemaV1.StoredPurchase
public typealias StoredObservation = CardCopilotSchemaV1.StoredObservation
public typealias StoredMerchant = CardCopilotSchemaV1.StoredMerchant
public typealias ExploredCell = CardCopilotSchemaV1.ExploredCell
public typealias ShoppingArea = CardCopilotSchemaV1.ShoppingArea
public typealias AreaMember = CardCopilotSchemaV1.AreaMember
