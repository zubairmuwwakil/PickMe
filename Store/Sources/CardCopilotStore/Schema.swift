import Foundation
import SwiftData

/// Version 1 of the on-device store — the shape already written to installed devices.
///
/// Its seven `@Model` classes live in `SchemaV1Models.swift`, frozen. They were declared inline
/// alongside the live models until V2 arrived; keeping a version's shapes after they stop being
/// the current ones is the whole reason the models were namespaced under their schema version in
/// the first place. `SchemaVersionTests.v1Shape` is the baseline that proves they stayed still.
///
/// Nesting is shape-preserving: SwiftData names an entity after the type's simple name, so
/// `CardCopilotSchemaV1.StoredPrediction` persists as `StoredPrediction`, exactly as the flat
/// declaration did — and so does `CardCopilotSchemaV2.StoredPrediction`. Same table, two Swift
/// types, which is precisely what lets a migration be tested rather than assumed.
///
/// Why this exists at all: the app previously built its container from a literal list of seven
/// types at the call site, with no version attached. SwiftData will silently perform a lightweight
/// migration when it can, and refuse to open the store when it cannot — and "cannot" includes
/// every rename and retype. The store holds `StoredPrediction`, the append-only log the accuracy
/// claim is measured against and the one record here that cannot be recomputed from anything else.
public enum CardCopilotSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    /// Every persisted type of V1, in one place. Deliberately V1's own frozen classes and not the
    /// live ones: were these the live types, `Schema(versionedSchema:)` would report V2's shape for
    /// V1 and the migration test would stop testing a migration.
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

/// Version 2 of the on-device store: provenance on `StoredPrediction`.
///
/// Adds `contractRelease`, `contractDigest`, and `frozenInputs`. All three are optional, which is
/// what makes the stage `.lightweight` — SwiftData can add a nullable column without rewriting
/// rows. Rows written under V1 arrive here with all three nil, and that is their correct value:
/// they were scored before provenance existed, and `contractRelease == nil` is the queryable
/// predicate that keeps them out of any per-release accuracy figure.
///
/// These are the live classes — the ones `Models.swift` and `DiscoveryCache.swift` declare and the
/// typealiases below name. Every other entity is byte-identical to V1;
/// `SchemaVersionTests.testV2ChangesOnlyStoredPrediction` is what keeps anything else from riding
/// along in this migration.
public enum CardCopilotSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

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

/// The version every container opens at.
///
/// One name, so moving to a new version is one edit rather than a grep across the app target, this
/// package, and both test suites — and so a call site left behind is impossible rather than merely
/// unlikely. It matters more than it looks: a container is keyed by the model *types* in its
/// schema, so a container opened at V1 while the unqualified `StoredPrediction` means V2's class is
/// not a version mismatch SwiftData reconciles — it is a container with no table for the type being
/// inserted. `SchemaVersionTests.testCurrentSchemaIsTheNewestInTheMigrationPlan` pins this to the
/// plan's newest entry.
public enum CardCopilotSchema {
    public static var current: any VersionedSchema.Type { CardCopilotSchemaV2.self }
}

/// How owners are carried from one schema version to the next.
///
/// V1 stays listed even though nothing opens at it any more: it is the version installed stores
/// were written at, and a plan that does not name it gives those stores nothing to migrate *from*.
///
/// Prefer `MigrationStage.lightweight` where the change qualifies (adding a property with a
/// default, adding a model, deleting a property). Reach for `.custom` only when data has to be
/// rewritten, and note that `.custom` is the case that genuinely needs both versions' types to
/// exist simultaneously — which is why the models are namespaced under their schema version.
public enum CardCopilotMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [CardCopilotSchemaV1.self, CardCopilotSchemaV2.self]
    }

    /// Lightweight because every added property is optional. `.custom` would be required only if
    /// data had to be rewritten — and there is nothing to rewrite: a pre-provenance row's correct
    /// provenance is "none". Backfilling one would invent the measurement this work exists to
    /// protect.
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: CardCopilotSchemaV1.self, toVersion: CardCopilotSchemaV2.self)]
    }
}

// The current version's models are also reachable unqualified, so the ~195 references across the
// app and this package are unaffected by the nesting. Repointing these seven lines is what "the
// current shape" means for every call site at once — and the only reason that is safe is that no
// call site names a version literally. Containers get theirs from `CardCopilotSchema.current`.
public typealias StoredPrediction = CardCopilotSchemaV2.StoredPrediction
public typealias StoredPurchase = CardCopilotSchemaV2.StoredPurchase
public typealias StoredObservation = CardCopilotSchemaV2.StoredObservation
public typealias StoredMerchant = CardCopilotSchemaV2.StoredMerchant
public typealias ExploredCell = CardCopilotSchemaV2.ExploredCell
public typealias ShoppingArea = CardCopilotSchemaV2.ShoppingArea
public typealias AreaMember = CardCopilotSchemaV2.AreaMember
