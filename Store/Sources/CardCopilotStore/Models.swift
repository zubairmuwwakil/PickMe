import Foundation
import SwiftData

/// Where a category prediction came from, in descending confidence.
/// Mirrors the prediction ladder in the MVP design doc (§6).
public enum ConfidenceSource: String, Codable, Sendable, CaseIterable {
    case ownerConfirmedTerminal   // this exact location/terminal, previously confirmed
    case repeatedTerminal         // repeated reconciled result at the same terminal
    case issuerOverride           // issuer-specific known-merchant rule
    case observedMcc              // MCC read off the owner's own posted transaction
    case brandPrior               // brand/location seed plus MapKit category
    case mapKitCategory           // MapKit POI category alone
    case fallback                 // unknown

    /// Whether this source is strong enough to call a merchant "verified" in the UI.
    public var isVerified: Bool {
        self == .ownerConfirmedTerminal || self == .repeatedTerminal
    }
}

/// How a prediction went wrong. Chosen during the weekly reconcile ritual so that a failed
/// experiment says *which* thing failed — the taxonomy in the MVP design doc (§6).
public enum MissClass: String, Codable, Sendable, CaseIterable {
    case wrongCategory
    case capExceeded
    case staleRule
    case processorWeirdness
    case networkNotAccepted
}

/// Where a recorded fact came from. The distinction is not bookkeeping: a card named at the till
/// and a card recalled a week later are different evidence, and averaging them into one
/// confidence is how a log starts lying about itself.
public enum CaptureSource: String, Codable, Sendable, CaseIterable {
    /// Stated during the visit — fresh, and the strongest a manual record gets.
    case atTill
    /// Stated later, during reconcile. Recalled rather than observed.
    case recalledLater
    /// Read off an Apple Wallet transaction by the Shortcut (Path B).
    case walletCapture
}

// The persisted models of schema version 2 — the shapes the app writes today. Declared as an
// extension of `CardCopilotSchemaV2` (see Schema.swift) rather than at file scope, so that V1 can
// hold its own, differently shaped `StoredPrediction` of the same name; V1's copies are frozen in
// `SchemaV1Models.swift`. The unqualified names remain available through the typealiases in
// Schema.swift, so call sites are unchanged.
//
// Unqualified `StoredPurchase` below means `CardCopilotSchemaV2`'s own member: an enclosing type's
// members shadow the module-level typealias. That is what keeps each version's relationships inside
// that version once two of them exist.
extension CardCopilotSchemaV2 {

    /// What the app said at the moment of payment.
    ///
    /// Very nearly append-only, and the one exception is deliberate: `predictedCategory` is
    /// rewritten by `PredictionLog.updateCategory` when the owner corrects a misread merchant.
    /// Accuracy measured against a log that can be rewritten would measure nothing, so that path
    /// stamps `categoryCorrectedAt` and every other field here is settable only from its
    /// initialiser. Corrections otherwise arrive as a separate `StoredObservation`.
    @Model
    public final class StoredPrediction {
        public private(set) var id: UUID = UUID()
        public private(set) var recordedAt: Date = Date()
        public private(set) var merchantName: String = ""
        public private(set) var merchantIdentifier: String?
        /// Mutable, but only from inside this module: `PredictionLog.updateCategory` is the single
        /// path, and it stamps `categoryCorrectedAt`. A public setter would let any caller rewrite
        /// the category without leaving the trace the accuracy math depends on — which is the whole
        /// reason the stamp exists rather than being advisory.
        public internal(set) var predictedCategory: String = ""
        /// When the owner reclassified this prediction's category, if they ever did.
        ///
        /// Once `predictedCategory` has been rewritten it matches the observation, and a miss
        /// becomes indistinguishable from a hit — the accuracy number degrades silently, exactly
        /// the failure provenance exists to prevent. `categoryCorrectedAt != nil` is the queryable
        /// predicate that keeps a rewritten row out of a hit-rate figure, the same way
        /// `contractRelease == nil` keeps a pre-provenance row out of a per-release one.
        ///
        /// It does not recover what was originally predicted; that value is gone once overwritten.
        /// Excluding corrected rows is the honest floor here, not a repair.
        public internal(set) var categoryCorrectedAt: Date?
        public private(set) var confidenceSourceRaw: String = ConfidenceSource.fallback.rawValue
        public private(set) var winnerCardId: String = ""
        public private(set) var winnerValueCad: Double = 0
        /// Reward units the engine predicted the winning card would earn — points, cash-back
        /// dollars, CT Money, whatever the program pays in. Snapshotted so the arithmetic bar can
        /// be checked against the advice as given; optional so rows written before this field
        /// existed are excluded from the arithmetic metric rather than guessed at.
        public private(set) var predictedRewardUnits: Double?
        /// The winning program's unit ("point", "cad", "ctDollar", "cro") at prediction time.
        /// Decides the comparison tolerance: points post as integers, cash back posts to the cent.
        public private(set) var predictedRewardUnitKind: String?
        /// The value the designated default card would have earned on the same purchase.
        /// Optional so predictions written before Task 6 are excluded from value-recovered math.
        public private(set) var defaultCardValueCad: Double?
        public private(set) var winnerRuleId: String?
        public private(set) var runnerUpCardId: String?
        public private(set) var runnerUpValueCad: Double?
        /// The amount the engine scored against, stated by the owner before paying — nil when they
        /// skipped and a category estimate was used instead. NOT what the purchase cost: that is
        /// `StoredPurchase.amountCad`, and conflating the two is what let value-recovered quietly
        /// multiply through a preset button.
        public private(set) var scoredAmountCad: Double?
        /// The point valuation in force when this advice was given — without it, a later
        /// valuation change would silently invalidate the arithmetic check.
        public private(set) var valuationCentsPerPoint: Double?
        /// The contract release that scored this prediction, e.g. `card-contracts@1.6`.
        ///
        /// Flat rather than inside `frozenInputs` because the accuracy claim aggregates over it —
        /// "what was our hit rate under 1.6?" is a predicate across many rows, and a blob would
        /// force decoding every one. Nil means the row predates provenance; it is never backfilled.
        public private(set) var contractRelease: String?
        /// The digest of the contract bytes, recorded alongside the release id so the row is
        /// self-verifying against RELEASE.json rather than trusting a version string.
        public private(set) var contractDigest: String?
        /// The winning card's `ScoredRuleSnapshot`, JSON-encoded. Opaque here on purpose: the
        /// snapshot's shape is contract semantics and versions itself, so widening it must never
        /// require a store migration.
        public private(set) var frozenInputs: Data?
        public private(set) var headline: String = ""

        /// The till record, created when the owner states they bought something here. A prediction
        /// with no purchase is advice that was given and not acted on — which is a real outcome, not
        /// a missing row.
        @Relationship(deleteRule: .cascade, inverse: \StoredPurchase.prediction)
        public var purchase: StoredPurchase?

        public var confidenceSource: ConfidenceSource {
            ConfidenceSource(rawValue: confidenceSourceRaw) ?? .fallback
        }

        public init(merchantName: String, merchantIdentifier: String? = nil,
                    predictedCategory: String, confidenceSource: ConfidenceSource,
                    winnerCardId: String, winnerValueCad: Double,
                    predictedRewardUnits: Double? = nil, predictedRewardUnitKind: String? = nil,
                    defaultCardValueCad: Double? = nil, winnerRuleId: String? = nil,
                    runnerUpCardId: String? = nil, runnerUpValueCad: Double? = nil,
                    scoredAmountCad: Double? = nil, valuationCentsPerPoint: Double? = nil,
                    contractRelease: String? = nil, contractDigest: String? = nil,
                    frozenInputs: Data? = nil,
                    headline: String, recordedAt: Date = Date()) {
            self.id = UUID()
            self.recordedAt = recordedAt
            self.merchantName = merchantName
            self.merchantIdentifier = merchantIdentifier
            self.predictedCategory = predictedCategory
            self.confidenceSourceRaw = confidenceSource.rawValue
            self.winnerCardId = winnerCardId
            self.winnerValueCad = winnerValueCad
            self.predictedRewardUnits = predictedRewardUnits
            self.predictedRewardUnitKind = predictedRewardUnitKind
            self.defaultCardValueCad = defaultCardValueCad
            self.winnerRuleId = winnerRuleId
            self.runnerUpCardId = runnerUpCardId
            self.runnerUpValueCad = runnerUpValueCad
            self.scoredAmountCad = scoredAmountCad
            self.valuationCentsPerPoint = valuationCentsPerPoint
            self.contractRelease = contractRelease
            self.contractDigest = contractDigest
            self.frozenInputs = frozenInputs
            self.headline = headline
        }
    }

    /// The till: what the owner tapped, and what it came to.
    ///
    /// This exists because the world has three moments and the model had two. At the till the card
    /// is certain and the amount is on the terminal screen; neither is knowable from a statement that
    /// does not exist yet, and both are guesses by the time one does. Path B's `WalletEvent` is this
    /// same record captured automatically — which is why the shape is source-agnostic.
    ///
    /// Unlike its neighbours this record is mutable, and deliberately so: it is the one thing here
    /// that is *incomplete* rather than merely unknown. The advice is whole the instant it is given
    /// and the statement is whole the instant it is read, but a purchase legitimately arrives in two
    /// pieces, sometimes days apart.
    @Model
    public final class StoredPurchase {
        public private(set) var id: UUID = UUID()
        public private(set) var createdAt: Date = Date()

        /// nil until stated. Never defaulted to the recommended card — that assumption is exactly
        /// what made value-recovered credit advice the owner ignored.
        public var cardUsedId: String?
        public var cardSourceRaw: String?

        /// What the charge actually came to.
        public var amountCad: Double?
        public var amountSourceRaw: String?

        /// Set once both facts are known. Drives the "finish these" queue, and gates entry to the
        /// reconcile queue — a purchase missing its card cannot be checked against a statement.
        public var completedAt: Date?

        public var prediction: StoredPrediction?

        @Relationship(deleteRule: .cascade, inverse: \StoredObservation.purchase)
        public var observation: StoredObservation?

        public var cardSource: CaptureSource? { cardSourceRaw.flatMap(CaptureSource.init(rawValue:)) }
        public var amountSource: CaptureSource? { amountSourceRaw.flatMap(CaptureSource.init(rawValue:)) }
        public var isComplete: Bool { completedAt != nil }

        public init(createdAt: Date = Date()) {
            self.id = UUID()
            self.createdAt = createdAt
        }
    }

    /// What the statement says: how the charge coded, and what it paid. Purely statement-derived
    /// since the card moved to `StoredPurchase` — this type now means exactly one thing.
    @Model
    public final class StoredObservation {
        public private(set) var id: UUID = UUID()
        public private(set) var confirmedAt: Date = Date()
        /// Module-internal setter for the same reason as `StoredPrediction.predictedCategory`:
        /// `PredictionLog.updateCategory` keeps the observation in step with the correction, and
        /// nothing outside this package should be able to restate what a statement said.
        public internal(set) var observedCategory: String = ""
        /// Reward units the statement actually posted for this transaction — points for a points
        /// card, dollars for cash back. Optional and never inferred: a statement that shows no
        /// per-transaction reward line leaves this unknown, which excludes the row from the
        /// arithmetic bar rather than fabricating evidence for it.
        public private(set) var observedRewardUnits: Double?
        public private(set) var missClassRaw: String?
        public private(set) var note: String?
        public var purchase: StoredPurchase?

        public var missClass: MissClass? { missClassRaw.flatMap(MissClass.init(rawValue:)) }
        /// A confirmation with no miss class is a correct prediction.
        public var wasCorrect: Bool { missClassRaw == nil }

        public init(observedCategory: String, observedRewardUnits: Double? = nil,
                    missClass: MissClass? = nil,
                    note: String? = nil, confirmedAt: Date = Date()) {
            self.id = UUID()
            self.confirmedAt = confirmedAt
            self.observedCategory = observedCategory
            self.observedRewardUnits = observedRewardUnits
            self.missClassRaw = missClass?.rawValue
            self.note = note
        }
    }

    /// A merchant the owner has confirmed at least once — the basis for instant repeats and
    /// the embryo of the Merchant Truth Graph. Deliberately terminal-specific: a confirmation
    /// at one Walmart says nothing about another.
    @Model
    public final class StoredMerchant {
        public private(set) var id: UUID = UUID()
        public private(set) var name: String = ""
        public private(set) var identifier: String?
        public var poiCategoryRaw: String?
        public private(set) var latitude: Double = 0
        public private(set) var longitude: Double = 0
        public var confirmedCategory: String?
        public var confirmationCount: Int = 0
        public var lastSeenAt: Date = Date()

        public init(name: String, identifier: String? = nil, poiCategoryRaw: String? = nil,
                    latitude: Double, longitude: Double,
                    confirmedCategory: String? = nil, confirmationCount: Int = 0,
                    lastSeenAt: Date = Date()) {
            self.id = UUID()
            self.name = name
            self.identifier = identifier
            self.poiCategoryRaw = poiCategoryRaw
            self.latitude = latitude
            self.longitude = longitude
            self.confirmedCategory = confirmedCategory
            self.confirmationCount = confirmationCount
            self.lastSeenAt = lastSeenAt
        }
    }
}

// The persisted models of schema version 3 — the shapes the app writes today. `StoredPrediction`,
// `StoredObservation`, and `StoredMerchant` are byte-identical to `CardCopilotSchemaV2`'s; only
// `StoredPurchase` changes (see `Schema.swift`'s doc comment on `CardCopilotSchemaV3` for why: two
// optional provenance fields for Path B captures logged with no live checkout behind them). Kept
// as full, independent redeclarations rather than reusing V2's classes for the same reason V2 did
// not reuse V1's — see `SchemaVersionTests.testV2AndV3DeclareDistinctModelTypes`.
extension CardCopilotSchemaV3 {

    /// Byte-identical to `CardCopilotSchemaV2.StoredPrediction`. See that type's doc comment.
    @Model
    public final class StoredPrediction {
        public private(set) var id: UUID = UUID()
        public private(set) var recordedAt: Date = Date()
        public private(set) var merchantName: String = ""
        public private(set) var merchantIdentifier: String?
        public internal(set) var predictedCategory: String = ""
        public internal(set) var categoryCorrectedAt: Date?
        public private(set) var confidenceSourceRaw: String = ConfidenceSource.fallback.rawValue
        public private(set) var winnerCardId: String = ""
        public private(set) var winnerValueCad: Double = 0
        public private(set) var predictedRewardUnits: Double?
        public private(set) var predictedRewardUnitKind: String?
        public private(set) var defaultCardValueCad: Double?
        public private(set) var winnerRuleId: String?
        public private(set) var runnerUpCardId: String?
        public private(set) var runnerUpValueCad: Double?
        public private(set) var scoredAmountCad: Double?
        public private(set) var valuationCentsPerPoint: Double?
        public private(set) var contractRelease: String?
        public private(set) var contractDigest: String?
        public private(set) var frozenInputs: Data?
        public private(set) var headline: String = ""

        @Relationship(deleteRule: .cascade, inverse: \StoredPurchase.prediction)
        public var purchase: StoredPurchase?

        public var confidenceSource: ConfidenceSource {
            ConfidenceSource(rawValue: confidenceSourceRaw) ?? .fallback
        }

        public init(merchantName: String, merchantIdentifier: String? = nil,
                    predictedCategory: String, confidenceSource: ConfidenceSource,
                    winnerCardId: String, winnerValueCad: Double,
                    predictedRewardUnits: Double? = nil, predictedRewardUnitKind: String? = nil,
                    defaultCardValueCad: Double? = nil, winnerRuleId: String? = nil,
                    runnerUpCardId: String? = nil, runnerUpValueCad: Double? = nil,
                    scoredAmountCad: Double? = nil, valuationCentsPerPoint: Double? = nil,
                    contractRelease: String? = nil, contractDigest: String? = nil,
                    frozenInputs: Data? = nil,
                    headline: String, recordedAt: Date = Date()) {
            self.id = UUID()
            self.recordedAt = recordedAt
            self.merchantName = merchantName
            self.merchantIdentifier = merchantIdentifier
            self.predictedCategory = predictedCategory
            self.confidenceSourceRaw = confidenceSource.rawValue
            self.winnerCardId = winnerCardId
            self.winnerValueCad = winnerValueCad
            self.predictedRewardUnits = predictedRewardUnits
            self.predictedRewardUnitKind = predictedRewardUnitKind
            self.defaultCardValueCad = defaultCardValueCad
            self.winnerRuleId = winnerRuleId
            self.runnerUpCardId = runnerUpCardId
            self.runnerUpValueCad = runnerUpValueCad
            self.scoredAmountCad = scoredAmountCad
            self.valuationCentsPerPoint = valuationCentsPerPoint
            self.contractRelease = contractRelease
            self.contractDigest = contractDigest
            self.frozenInputs = frozenInputs
            self.headline = headline
        }
    }

    /// The till: what the owner tapped, and what it came to. See `CardCopilotSchemaV2.StoredPurchase`
    /// for the original doc comment; `walletEventId` and `merchantLabel` are new in V3 — see
    /// `Schema.swift`'s doc comment on `CardCopilotSchemaV3` for why.
    @Model
    public final class StoredPurchase {
        public private(set) var id: UUID = UUID()
        public private(set) var createdAt: Date = Date()

        /// nil until stated. Never defaulted to the recommended card — that assumption is exactly
        /// what made value-recovered credit advice the owner ignored.
        public var cardUsedId: String?
        public var cardSourceRaw: String?

        /// What the charge actually came to.
        public var amountCad: Double?
        public var amountSourceRaw: String?

        /// Set once both facts are known. Drives the "finish these" queue, and gates entry to the
        /// reconcile queue — a purchase missing its card cannot be checked against a statement.
        public var completedAt: Date?

        public var prediction: StoredPrediction?

        /// The server `WalletEvent.eventId` whose facts landed on this purchase — set by
        /// `AutoCaptureLog` when it writes a purchase with no checkout behind it, and ALSO by
        /// `PredictionLog.recordPurchase` when a checkout's owner accepts a `CaptureProposal`. Both
        /// producers matter: `AutoCaptureLog.loggedEventIds()` reads this across every purchase to
        /// stay idempotent, and a tap accepted into a checkout must be just as "already logged" as
        /// one `AutoCaptureLog` wrote directly — otherwise, once that checkout completes and its
        /// prediction drops out of the open set, a later sync would see the very same tap as
        /// orphaned and log it a second time as a standalone purchase. `internal(set)`: any file in
        /// this module may stamp it, but the app layer never mutates it directly.
        public internal(set) var walletEventId: String?
        /// The merchant name, for a purchase with no `prediction` to read it from. A purchase
        /// created through `PredictionLog.recordPurchase` leaves this nil and reads
        /// `prediction?.merchantName` instead — see `displayMerchant`.
        public private(set) var merchantLabel: String?

        @Relationship(deleteRule: .cascade, inverse: \StoredObservation.purchase)
        public var observation: StoredObservation?

        public var cardSource: CaptureSource? { cardSourceRaw.flatMap(CaptureSource.init(rawValue:)) }
        public var amountSource: CaptureSource? { amountSourceRaw.flatMap(CaptureSource.init(rawValue:)) }
        public var isComplete: Bool { completedAt != nil }

        public init(createdAt: Date = Date(), merchantLabel: String? = nil, walletEventId: String? = nil) {
            self.id = UUID()
            self.createdAt = createdAt
            self.merchantLabel = merchantLabel
            self.walletEventId = walletEventId
        }
    }

    /// Byte-identical to `CardCopilotSchemaV2.StoredObservation`. See that type's doc comment.
    @Model
    public final class StoredObservation {
        public private(set) var id: UUID = UUID()
        public private(set) var confirmedAt: Date = Date()
        public var observedCategory: String = ""
        public private(set) var observedRewardUnits: Double?
        public private(set) var missClassRaw: String?
        public private(set) var note: String?
        public var purchase: StoredPurchase?

        public var missClass: MissClass? { missClassRaw.flatMap(MissClass.init(rawValue:)) }
        public var wasCorrect: Bool { missClassRaw == nil }

        public init(observedCategory: String, observedRewardUnits: Double? = nil,
                    missClass: MissClass? = nil,
                    note: String? = nil, confirmedAt: Date = Date()) {
            self.id = UUID()
            self.confirmedAt = confirmedAt
            self.observedCategory = observedCategory
            self.observedRewardUnits = observedRewardUnits
            self.missClassRaw = missClass?.rawValue
            self.note = note
        }
    }

    /// Byte-identical to `CardCopilotSchemaV2.StoredMerchant`. See that type's doc comment.
    @Model
    public final class StoredMerchant {
        public private(set) var id: UUID = UUID()
        public private(set) var name: String = ""
        public private(set) var identifier: String?
        public var poiCategoryRaw: String?
        public private(set) var latitude: Double = 0
        public private(set) var longitude: Double = 0
        public var confirmedCategory: String?
        public var confirmationCount: Int = 0
        public var lastSeenAt: Date = Date()

        public init(name: String, identifier: String? = nil, poiCategoryRaw: String? = nil,
                    latitude: Double, longitude: Double,
                    confirmedCategory: String? = nil, confirmationCount: Int = 0,
                    lastSeenAt: Date = Date()) {
            self.id = UUID()
            self.name = name
            self.identifier = identifier
            self.poiCategoryRaw = poiCategoryRaw
            self.latitude = latitude
            self.longitude = longitude
            self.confirmedCategory = confirmedCategory
            self.confirmationCount = confirmationCount
            self.lastSeenAt = lastSeenAt
        }
    }
}

/// A fact a purchase is still missing. Derived from the record rather than tracked alongside it,
/// so the finish queue and the finish screen can never disagree about what is outstanding.
public enum MissingPurchaseFact: String, Sendable, CaseIterable {
    case card
    case amount
}

extension StoredPurchase {
    /// Empty exactly when `isComplete`. Both derive from the same two optionals rather than from
    /// a stored flag, because a flag is a second source of truth that gets to be wrong.
    public var missingFacts: Set<MissingPurchaseFact> {
        var missing: Set<MissingPurchaseFact> = []
        if cardUsedId == nil { missing.insert(.card) }
        if amountCad == nil { missing.insert(.amount) }
        return missing
    }

    /// The merchant name to show, whichever kind of purchase this is: one asked about at checkout
    /// reads it from the `StoredPrediction`; one `AutoCaptureLog` wrote directly reads its own
    /// `merchantLabel`, since it has no prediction to read from.
    public var displayMerchant: String {
        merchantLabel ?? prediction?.merchantName ?? "Unknown merchant"
    }

    /// Source for legacy rows is derived from whether advice exists; V4 rows carry it explicitly.
    public var resolvedActivitySource: PurchaseActivitySource {
        activitySource ?? (prediction == nil ? .walletCapture : .pickMeCheckout)
    }

    public var displayCategory: String? {
        observation?.observedCategory ?? categoryAtPurchase ?? prediction?.predictedCategory
    }

    public var categoryConfidence: ConfidenceSource? {
        categoryConfidenceRaw.flatMap(ConfidenceSource.init(rawValue:))
    }

    public var hasPreciseLocation: Bool {
        guard let merchantLatitude, let merchantLongitude else { return false }
        return merchantLatitude != 0 || merchantLongitude != 0
    }

    /// True for a purchase with no `StoredPrediction` behind it — `AutoCaptureLog` wrote it
    /// directly from a Wallet capture that matched no open checkout, so there is no predicted
    /// category to grade it against.
    ///
    /// Deliberately `prediction == nil`, not `walletEventId != nil`: a checkout-originated
    /// purchase can ALSO carry a `walletEventId` once its owner accepts a `CaptureProposal` (see
    /// that property's doc comment), and such a purchase is emphatically not auto-logged — it was
    /// asked about live, at a real checkout, with a real graded prediction behind it.
    public var isAutoLogged: Bool { prediction == nil }
}
