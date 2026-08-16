# Benefits Disclosure & Protection Lens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Zubair's standing preference: inline "chipping" execution for plans whose code is already written out.

**Goal:** Surface card insurance benefits at the checkout moment and provide a declared-context protection lens ("which card protects this flight best"), without touching the scoring pipeline or the prediction log.

**Architecture:** Parallel subsystem (spec B5). A new `benefits-catalogue.json` resource and pure `BenefitsAdvisor` live in the Engine package beside — never inside — the `SeedLoader→RuleMatcher→CapMath→Scorer` pipeline. The App composes earn recommendation and benefits disclosure side by side; they meet only in the UI. Three App surfaces: checkout disclosure lines, protection lens, per-card reference screen.

**Tech Stack:** Swift 5.10 package (`Engine/`, zero dependencies, XCTest), SwiftUI app (`App/`, Xcode 16 synchronized folders — new files under `App/CardCopilot/` are picked up automatically, no pbxproj edits).

**Spec:** `docs/plans/2026-08-15-benefits-disclosure-design.md` — read it first; every decision cited as B1–B9 below is defined there.

## Global Constraints

- **B1 disclose-don't-score:** `BenefitsAdvisor` never imports or feeds `Scorer`/`RecommendationEngine`. No benefit value in CAD anywhere.
- **B2 wording:** benefits UI always says "per certificate"; never "you're covered"/"covered". Every benefits surface shows this exact footer: `Coverage depends on certificate conditions — verify before relying on it.`
- **B6 frozen vocabulary:** no new merchant categories anywhere. Benefit context is a separate enum.
- **B9 experiment integrity:** no changes to `CheckoutService`, the prediction log, or any Store type. The lens computes its earn line via `RecommendationEngine` directly so nothing is logged.
- **B4/B8 stub honesty:** every shipped benefits entry is `"verificationStatus": "stub"` and the UI renders an "Unverified draft" chip wherever stub data appears. Stub coverage numbers are structural placeholders for wiring, not facts — Zubair's certificate dossier replaces the file wholesale.
- Engine tests: `cd Engine && swift test` (all pre-existing tests must stay green). App verification: `xcodebuild -project App/CardCopilot.xcodeproj -scheme CardCopilot -destination 'generic/platform=iOS Simulator' build`.
- Commits: repo style — short imperative sentence ("Add the benefits catalogue models"), **no Co-Authored-By trailer**, commit from the repo root so both `Engine/` and `docs/` paths stage cleanly.
- Model idiom: open `String` vocabularies with enum namespaces for known values (matches `PurchaseContext.category`); unknown `kind`/`family` strings must decode, persist, and round-trip (forward compatibility), and are simply ignored by advisor logic.

---

### Task 1: Benefits catalogue models

**Files:**
- Create: `Engine/Sources/CardCopilotEngine/Models/BenefitsModels.swift`
- Test: `Engine/Tests/CardCopilotEngineTests/BenefitsModelsTests.swift`

**Interfaces:**
- Consumes: nothing new (Foundation only).
- Produces: `BenefitsCatalogue` (root: `benefitsCatalogueVersion: String`, `triggers: BenefitsTriggers`, `cards: [CardBenefits]`, `card(_:) -> CardBenefits?`), `BenefitsTriggers` (`bigTicketThresholdCad: Double`, `consumableCategories: [String]`), `CardBenefits` (`cardId`, `certificate: CertificateProvenance`, `benefits: [Benefit]`), `CertificateProvenance` (`underwriter/sourceUrl/certificateDate/lastVerifiedAt: String?`, `verificationStatus: BenefitVerification`), `Benefit` (`benefitId: String`, `family: String`, `kind: String`, `coverage: BenefitCoverage`, `conditions: [String]`, `exclusions: [String]?`, `certificateQuote: String?`, `notes: String?`, computed `knownKind: BenefitKind?`), `BenefitCoverage` (13 optional typed fields), `BenefitVerification` (`stub|issuerPage|certificateVerified`), `BenefitFamily` and `BenefitKind` enums.

- [ ] **Step 1: Write the failing decode tests**

```swift
// Engine/Tests/CardCopilotEngineTests/BenefitsModelsTests.swift
import XCTest
@testable import CardCopilotEngine

final class BenefitsModelsTests: XCTestCase {
    private let sampleJSON = """
    {
      "benefitsCatalogueVersion": "0.1.0",
      "_provenance": "test fixture",
      "triggers": {
        "bigTicketThresholdCad": 150,
        "consumableCategories": ["dining", "grocery"]
      },
      "cards": [
        {
          "cardId": "amex-cobalt",
          "certificate": {
            "underwriter": "Royal & Sun Alliance",
            "sourceUrl": "https://example.com/cert.pdf",
            "certificateDate": null,
            "lastVerifiedAt": null,
            "verificationStatus": "stub"
          },
          "benefits": [
            {
              "benefitId": "cobalt-purchase-protection",
              "family": "shopping",
              "kind": "purchaseProtection",
              "coverage": { "windowDays": 90, "maxPerOccurrenceCad": 1000 },
              "conditions": ["Full purchase charged to the card"],
              "exclusions": ["Jewellery left unattended"],
              "certificateQuote": null,
              "notes": null
            },
            {
              "benefitId": "cobalt-future-benefit",
              "family": "someFutureFamily",
              "kind": "cellPlanInsurance",
              "coverage": {},
              "conditions": []
            }
          ]
        }
      ]
    }
    """

    private func decodeSample() throws -> BenefitsCatalogue {
        try JSONDecoder().decode(BenefitsCatalogue.self,
                                 from: Data(sampleJSON.utf8))
    }

    func testDecodesRootAndTriggers() throws {
        let catalogue = try decodeSample()
        XCTAssertEqual(catalogue.benefitsCatalogueVersion, "0.1.0")
        XCTAssertEqual(catalogue.triggers.bigTicketThresholdCad, 150, accuracy: 0.005)
        XCTAssertEqual(catalogue.triggers.consumableCategories, ["dining", "grocery"])
    }

    func testDecodesCardCertificateAndBenefit() throws {
        let catalogue = try decodeSample()
        let card = try XCTUnwrap(catalogue.card("amex-cobalt"))
        XCTAssertEqual(card.certificate.verificationStatus, .stub)
        XCTAssertEqual(card.certificate.underwriter, "Royal & Sun Alliance")
        XCTAssertNil(card.certificate.certificateDate)

        let benefit = try XCTUnwrap(card.benefits.first)
        XCTAssertEqual(benefit.kind, "purchaseProtection")
        XCTAssertEqual(benefit.knownKind, .purchaseProtection)
        XCTAssertEqual(benefit.family, "shopping")
        XCTAssertEqual(benefit.coverage.windowDays, 90)
        XCTAssertEqual(benefit.coverage.maxPerOccurrenceCad ?? -1, 1000, accuracy: 0.005)
        XCTAssertNil(benefit.coverage.maxAnnualCad)
        XCTAssertEqual(benefit.conditions, ["Full purchase charged to the card"])
        XCTAssertEqual(benefit.exclusions, ["Jewellery left unattended"])
    }

    func testUnknownKindAndFamilySurviveDecoding() throws {
        // Forward compatibility (spec §4): future families must not break old builds.
        let catalogue = try decodeSample()
        let card = try XCTUnwrap(catalogue.card("amex-cobalt"))
        let future = try XCTUnwrap(card.benefits.last)
        XCTAssertEqual(future.kind, "cellPlanInsurance")
        XCTAssertNil(future.knownKind)
        XCTAssertEqual(future.family, "someFutureFamily")
    }

    func testRoundTripPreservesEverything() throws {
        let catalogue = try decodeSample()
        let data = try JSONEncoder().encode(catalogue)
        let again = try JSONDecoder().decode(BenefitsCatalogue.self, from: data)
        XCTAssertEqual(catalogue, again)
    }

    func testUnknownCardLookupReturnsNil() throws {
        let catalogue = try decodeSample()
        XCTAssertNil(catalogue.card("no-such-card"))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Engine && swift test --filter BenefitsModelsTests`
Expected: compile failure — `BenefitsCatalogue` does not exist.

- [ ] **Step 3: Write the models**

```swift
// Engine/Sources/CardCopilotEngine/Models/BenefitsModels.swift
import Foundation

/// Benefits are card metadata verified only by reading certificates of insurance —
/// a different truth procedure from earn rules (statement reconciliation) — so they live
/// in their own catalogue with their own provenance ladder (spec B5).
public enum BenefitVerification: String, Codable, Sendable {
    case stub               // Claude-drafted scaffolding; never trusted display
    case issuerPage         // matches the public marketing page
    case certificateVerified // checked against the owner's actual cardholder document
}

/// Known families. `Benefit.family` stays an open string (same idiom as
/// `PurchaseContext.category`); this enum is the namespace for known values.
public enum BenefitFamily: String, CaseIterable, Sendable {
    case shopping, travelDisruption, rentalCdw, travelMedical
}

/// The ten known benefit kinds (spec §4). `Benefit.kind` is an open string;
/// unknown kinds decode fine and are ignored by advisor logic.
public enum BenefitKind: String, CaseIterable, Sendable {
    case purchaseProtection, extendedWarranty, mobileDeviceInsurance
    case flightDelay, baggageDelay, baggageLoss, tripCancellation, tripInterruption
    case rentalCdw, travelMedical
}

/// Typed fields exist ONLY for what the comparison table sorts and displays (spec §4).
/// Everything conditional stays verbatim in `conditions`/`exclusions`.
public struct BenefitCoverage: Codable, Equatable, Sendable {
    public var windowDays: Int?
    public var maxPerOccurrenceCad: Double?
    public var maxAnnualCad: Double?
    public var extraYears: Int?
    public var maxOriginalWarrantyYears: Int?
    public var maxCad: Double?
    public var deductibleCad: Double?
    public var delayHours: Int?
    public var perDayCad: Double?
    public var maxTripLengthDays: Int?
    public var maxRentalDays: Int?
    public var maxVehicleValueCad: Double?
    public var ageLimit: Int?

    public init() {}
}

public struct Benefit: Codable, Equatable, Sendable {
    public var benefitId: String
    public var family: String
    public var kind: String
    public var coverage: BenefitCoverage
    public var conditions: [String]
    public var exclusions: [String]?
    public var certificateQuote: String?
    public var notes: String?

    public var knownKind: BenefitKind? { BenefitKind(rawValue: kind) }
    public var knownFamily: BenefitFamily? { BenefitFamily(rawValue: family) }
}

public struct CertificateProvenance: Codable, Equatable, Sendable {
    public var underwriter: String?
    public var sourceUrl: String?
    public var certificateDate: String?
    public var lastVerifiedAt: String?
    public var verificationStatus: BenefitVerification
}

public struct CardBenefits: Codable, Equatable, Identifiable, Sendable {
    public var cardId: String
    public var certificate: CertificateProvenance
    public var benefits: [Benefit]

    public var id: String { cardId }
}

/// Ambient-trigger tuning lives in data, not code (spec §5).
public struct BenefitsTriggers: Codable, Equatable, Sendable {
    public var bigTicketThresholdCad: Double
    public var consumableCategories: [String]
}

public struct BenefitsCatalogue: Codable, Equatable, Sendable {
    public var benefitsCatalogueVersion: String
    public var triggers: BenefitsTriggers
    public var cards: [CardBenefits]

    public func card(_ cardId: String) -> CardBenefits? {
        cards.first { $0.cardId == cardId }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Engine && swift test --filter BenefitsModelsTests`
Expected: 5 tests PASS. (`_provenance` is an unknown key; `JSONDecoder` skips it — no code needed.)

- [ ] **Step 5: Commit**

```bash
git add Engine/Sources/CardCopilotEngine/Models/BenefitsModels.swift Engine/Tests/CardCopilotEngineTests/BenefitsModelsTests.swift
git commit -m "Add the benefits catalogue models"
```

---

### Task 2: Loader + stub benefits catalogue for the 10 wallet cards

**Files:**
- Modify: `Engine/Sources/CardCopilotEngine/Loading/SeedLoader.swift` (add one method; the spec's "BenefitsLoader" is folded into `SeedLoader` — same pattern, DRY, identical behavior)
- Create: `Engine/Sources/CardCopilotEngine/Resources/benefits-catalogue.json`
- Test: `Engine/Tests/CardCopilotEngineTests/BenefitsLoaderTests.swift`

**Interfaces:**
- Consumes: Task 1 models; existing `SeedLoader.load(_:)` private generic and `SeedLoader.loadCatalogue()`.
- Produces: `SeedLoader.loadBenefitsCatalogue() throws -> BenefitsCatalogue`.

- [ ] **Step 1: Write the failing loader tests**

```swift
// Engine/Tests/CardCopilotEngineTests/BenefitsLoaderTests.swift
import XCTest
@testable import CardCopilotEngine

final class BenefitsLoaderTests: XCTestCase {
    func testLoadsBenefitsCatalogue() throws {
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        XCTAssertEqual(benefits.cards.count, 10)
        XCTAssertGreaterThan(benefits.triggers.bigTicketThresholdCad, 0)
        XCTAssertFalse(benefits.triggers.consumableCategories.isEmpty)
    }

    func testEveryWalletCardHasABenefitsEntry() throws {
        // Cross-file consistency: the benefits catalogue mirrors the earn catalogue's wallet.
        let wallet = try SeedLoader.loadCatalogue().cards.map(\.cardId)
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        XCTAssertEqual(Set(benefits.cards.map(\.cardId)), Set(wallet))
    }

    func testEveryShippedEntryIsStub() throws {
        // Spec B4: the shipped file is scaffolding. The day this test fails is the day
        // Zubair's verified dossier landed — then DELETE this test, don't weaken it.
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        for card in benefits.cards {
            XCTAssertEqual(card.certificate.verificationStatus, .stub,
                           "\(card.cardId) must remain stub until the certificate dossier lands")
        }
    }

    func testEveryBenefitKindAndFamilyIsKnown() throws {
        // The shipped file uses only the ten known kinds; the OPEN vocabulary is for
        // future data, not for typos in our own stub.
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        for card in benefits.cards {
            for benefit in card.benefits {
                XCTAssertNotNil(benefit.knownKind,
                                "\(card.cardId)/\(benefit.benefitId): unknown kind \(benefit.kind)")
                XCTAssertNotNil(benefit.knownFamily,
                                "\(card.cardId)/\(benefit.benefitId): unknown family \(benefit.family)")
            }
        }
    }

    func testConsumableCategoriesUseTheFrozenVocabulary() throws {
        // Spec B6: triggers reference existing earn categories only.
        let allowed: Set<String> = ["dining", "grocery", "foodDelivery", "gasStation",
                                    "transit", "drugStore", "entertainment", "fitness"]
        let benefits = try SeedLoader.loadBenefitsCatalogue()
        for category in benefits.triggers.consumableCategories {
            XCTAssertTrue(allowed.contains(category), "unexpected category \(category)")
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Engine && swift test --filter BenefitsLoaderTests`
Expected: compile failure — `loadBenefitsCatalogue` does not exist.

- [ ] **Step 3: Add the loader method**

In `Engine/Sources/CardCopilotEngine/Loading/SeedLoader.swift`, after `loadOwnerState()`:

```swift
    public static func loadBenefitsCatalogue() throws -> BenefitsCatalogue {
        try load("benefits-catalogue")
    }
```

- [ ] **Step 4: Create the stub catalogue**

Create `Engine/Sources/CardCopilotEngine/Resources/benefits-catalogue.json`. Every number below is a **structural placeholder** (typical Canadian card values) so the UI has realistic shapes to render; the `stub` status is what keeps them honest. Zubair's dossier replaces this file wholesale.

```json
{
  "benefitsCatalogueVersion": "0.1.0-stub",
  "_provenance": "STUB drafted 2026-08-16 by Claude from public issuer pages, NOT verified against any certificate of insurance. Every entry carries verificationStatus=stub and renders as an unverified draft. Zubair's certificate dossier replaces this file wholesale (spec B4). Absence of a kind on a card means UNKNOWN at stub level, not 'no coverage' (spec B8).",
  "triggers": {
    "bigTicketThresholdCad": 150,
    "consumableCategories": ["dining", "grocery", "foodDelivery", "gasStation", "transit", "drugStore", "entertainment", "fitness"]
  },
  "cards": [
    {
      "cardId": "amex-platinum",
      "certificate": { "underwriter": null, "sourceUrl": "https://www.americanexpress.com/ca/en/benefits/insurance/", "certificateDate": null, "lastVerifiedAt": null, "verificationStatus": "stub" },
      "benefits": [
        { "benefitId": "platinum-purchase-protection", "family": "shopping", "kind": "purchaseProtection",
          "coverage": { "windowDays": 90, "maxPerOccurrenceCad": 1000 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "platinum-extended-warranty", "family": "shopping", "kind": "extendedWarranty",
          "coverage": { "extraYears": 1, "maxOriginalWarrantyYears": 5 },
          "conditions": ["Full purchase charged to the card", "Original manufacturer warranty valid in Canada"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "platinum-flight-delay", "family": "travelDisruption", "kind": "flightDelay",
          "coverage": { "delayHours": 4, "maxCad": 1000 },
          "conditions": ["Round trip charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "platinum-baggage-delay", "family": "travelDisruption", "kind": "baggageDelay",
          "coverage": { "delayHours": 6, "maxCad": 1000 },
          "conditions": ["Round trip charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "platinum-baggage-loss", "family": "travelDisruption", "kind": "baggageLoss",
          "coverage": { "maxCad": 1000 },
          "conditions": ["Round trip charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "platinum-trip-cancellation", "family": "travelDisruption", "kind": "tripCancellation",
          "coverage": { "maxCad": 2500 },
          "conditions": ["Trip charged to the card before the cause of cancellation arose"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "platinum-trip-interruption", "family": "travelDisruption", "kind": "tripInterruption",
          "coverage": { "maxCad": 2500 },
          "conditions": ["Trip charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "platinum-rental-cdw", "family": "rentalCdw", "kind": "rentalCdw",
          "coverage": { "maxRentalDays": 48, "maxVehicleValueCad": 85000 },
          "conditions": ["Full rental charged to the card", "Decline the rental agency's CDW"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "platinum-travel-medical", "family": "travelMedical", "kind": "travelMedical",
          "coverage": { "maxCad": 5000000, "maxTripLengthDays": 15, "ageLimit": 65 },
          "conditions": ["Coverage for the first portion of each trip only"], "exclusions": [], "certificateQuote": null, "notes": null }
      ]
    },
    {
      "cardId": "amex-cobalt",
      "certificate": { "underwriter": null, "sourceUrl": "https://www.americanexpress.com/ca/en/benefits/insurance/", "certificateDate": null, "lastVerifiedAt": null, "verificationStatus": "stub" },
      "benefits": [
        { "benefitId": "cobalt-purchase-protection", "family": "shopping", "kind": "purchaseProtection",
          "coverage": { "windowDays": 90, "maxPerOccurrenceCad": 1000 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "cobalt-extended-warranty", "family": "shopping", "kind": "extendedWarranty",
          "coverage": { "extraYears": 1, "maxOriginalWarrantyYears": 5 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "cobalt-mobile-device", "family": "shopping", "kind": "mobileDeviceInsurance",
          "coverage": { "maxCad": 1000, "deductibleCad": 100 },
          "conditions": ["Device purchased with the card, or monthly plan billed to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "cobalt-flight-delay", "family": "travelDisruption", "kind": "flightDelay",
          "coverage": { "delayHours": 4, "maxCad": 500 },
          "conditions": ["Round trip charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "cobalt-baggage-delay", "family": "travelDisruption", "kind": "baggageDelay",
          "coverage": { "delayHours": 6, "maxCad": 500 },
          "conditions": ["Round trip charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "cobalt-baggage-loss", "family": "travelDisruption", "kind": "baggageLoss",
          "coverage": { "maxCad": 500 },
          "conditions": ["Round trip charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null }
      ]
    },
    {
      "cardId": "amex-bonvoy",
      "certificate": { "underwriter": null, "sourceUrl": "https://www.americanexpress.com/ca/en/benefits/insurance/", "certificateDate": null, "lastVerifiedAt": null, "verificationStatus": "stub" },
      "benefits": [
        { "benefitId": "bonvoy-purchase-protection", "family": "shopping", "kind": "purchaseProtection",
          "coverage": { "windowDays": 90, "maxPerOccurrenceCad": 1000 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "bonvoy-extended-warranty", "family": "shopping", "kind": "extendedWarranty",
          "coverage": { "extraYears": 1, "maxOriginalWarrantyYears": 5 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "bonvoy-flight-delay", "family": "travelDisruption", "kind": "flightDelay",
          "coverage": { "delayHours": 4, "maxCad": 500 },
          "conditions": ["Round trip charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "bonvoy-baggage-delay", "family": "travelDisruption", "kind": "baggageDelay",
          "coverage": { "delayHours": 6, "maxCad": 500 },
          "conditions": ["Round trip charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "bonvoy-rental-cdw", "family": "rentalCdw", "kind": "rentalCdw",
          "coverage": { "maxRentalDays": 48, "maxVehicleValueCad": 85000 },
          "conditions": ["Full rental charged to the card", "Decline the rental agency's CDW"], "exclusions": [], "certificateQuote": null, "notes": null }
      ]
    },
    {
      "cardId": "mbna-rewards-we",
      "certificate": { "underwriter": null, "sourceUrl": "https://www.mbna.ca/", "certificateDate": null, "lastVerifiedAt": null, "verificationStatus": "stub" },
      "benefits": [
        { "benefitId": "mbna-purchase-protection", "family": "shopping", "kind": "purchaseProtection",
          "coverage": { "windowDays": 90, "maxPerOccurrenceCad": 1000 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "mbna-extended-warranty", "family": "shopping", "kind": "extendedWarranty",
          "coverage": { "extraYears": 1 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "mbna-mobile-device", "family": "shopping", "kind": "mobileDeviceInsurance",
          "coverage": { "maxCad": 1000 },
          "conditions": ["Device purchased with the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "mbna-baggage-delay", "family": "travelDisruption", "kind": "baggageDelay",
          "coverage": { "delayHours": 6, "maxCad": 500 },
          "conditions": ["Trip charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null }
      ]
    },
    {
      "cardId": "scotia-momentum-vi-plus",
      "certificate": { "underwriter": null, "sourceUrl": "https://www.scotiabank.com/ca/en/personal/credit-cards/", "certificateDate": null, "lastVerifiedAt": null, "verificationStatus": "stub" },
      "benefits": [
        { "benefitId": "scotia-purchase-security", "family": "shopping", "kind": "purchaseProtection",
          "coverage": { "windowDays": 90, "maxPerOccurrenceCad": 1000 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "scotia-extended-warranty", "family": "shopping", "kind": "extendedWarranty",
          "coverage": { "extraYears": 1, "maxOriginalWarrantyYears": 5 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "scotia-flight-delay", "family": "travelDisruption", "kind": "flightDelay",
          "coverage": { "delayHours": 4, "maxCad": 500 },
          "conditions": ["Fare charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "scotia-baggage-delay", "family": "travelDisruption", "kind": "baggageDelay",
          "coverage": { "delayHours": 4, "maxCad": 500 },
          "conditions": ["Fare charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "scotia-trip-interruption", "family": "travelDisruption", "kind": "tripInterruption",
          "coverage": { "maxCad": 1500 },
          "conditions": ["Trip charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "scotia-rental-cdw", "family": "rentalCdw", "kind": "rentalCdw",
          "coverage": { "maxRentalDays": 48, "maxVehicleValueCad": 65000 },
          "conditions": ["Full rental charged to the card", "Decline the rental agency's CDW"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "scotia-travel-medical", "family": "travelMedical", "kind": "travelMedical",
          "coverage": { "maxCad": 1000000, "maxTripLengthDays": 25, "ageLimit": 65 },
          "conditions": ["Coverage for the first portion of each trip only"], "exclusions": [], "certificateQuote": null, "notes": null }
      ]
    },
    {
      "cardId": "tangerine-moneyback-world",
      "certificate": { "underwriter": null, "sourceUrl": "https://www.tangerine.ca/en/products/spending/creditcard/", "certificateDate": null, "lastVerifiedAt": null, "verificationStatus": "stub" },
      "benefits": [
        { "benefitId": "tangerine-purchase-assurance", "family": "shopping", "kind": "purchaseProtection",
          "coverage": { "windowDays": 90, "maxPerOccurrenceCad": 1000 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "tangerine-extended-warranty", "family": "shopping", "kind": "extendedWarranty",
          "coverage": { "extraYears": 1 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "tangerine-mobile-device", "family": "shopping", "kind": "mobileDeviceInsurance",
          "coverage": { "maxCad": 1000 },
          "conditions": ["Device purchased with the card"], "exclusions": [], "certificateQuote": null, "notes": null }
      ]
    },
    {
      "cardId": "rogers-red-we",
      "certificate": { "underwriter": null, "sourceUrl": "https://www.rogersbank.com/", "certificateDate": null, "lastVerifiedAt": null, "verificationStatus": "stub" },
      "benefits": [
        { "benefitId": "rogers-purchase-protection", "family": "shopping", "kind": "purchaseProtection",
          "coverage": { "windowDays": 90, "maxPerOccurrenceCad": 1000 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "rogers-extended-warranty", "family": "shopping", "kind": "extendedWarranty",
          "coverage": { "extraYears": 1 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null }
      ]
    },
    {
      "cardId": "triangle-we",
      "certificate": { "underwriter": null, "sourceUrl": "https://www.canadiantire.ca/en/triangle.html", "certificateDate": null, "lastVerifiedAt": null, "verificationStatus": "stub" },
      "benefits": [
        { "benefitId": "triangle-purchase-security", "family": "shopping", "kind": "purchaseProtection",
          "coverage": { "windowDays": 90, "maxPerOccurrenceCad": 1000 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null },
        { "benefitId": "triangle-extended-warranty", "family": "shopping", "kind": "extendedWarranty",
          "coverage": { "extraYears": 1 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null, "notes": null }
      ]
    },
    {
      "cardId": "wealthsimple-vip",
      "certificate": { "underwriter": null, "sourceUrl": null, "certificateDate": null, "lastVerifiedAt": null, "verificationStatus": "stub" },
      "benefits": [
        { "benefitId": "wsvip-purchase-protection", "family": "shopping", "kind": "purchaseProtection",
          "coverage": { "windowDays": 90, "maxPerOccurrenceCad": 1000 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null,
          "notes": "Public page unclear — certificate needed before even issuerPage status" },
        { "benefitId": "wsvip-extended-warranty", "family": "shopping", "kind": "extendedWarranty",
          "coverage": { "extraYears": 1 },
          "conditions": ["Full purchase charged to the card"], "exclusions": [], "certificateQuote": null,
          "notes": "Public page unclear — certificate needed before even issuerPage status" }
      ]
    },
    {
      "cardId": "cryptocom-royal-indigo",
      "certificate": { "underwriter": null, "sourceUrl": null, "certificateDate": null, "lastVerifiedAt": null, "verificationStatus": "stub" },
      "benefits": []
    }
  ]
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd Engine && swift test --filter BenefitsLoaderTests`
Expected: 5 tests PASS. If `testEveryWalletCardHasABenefitsEntry` fails, a `cardId` is misspelled — the earn catalogue is the authority.

- [ ] **Step 6: Run the full engine suite (regression gate)**

Run: `cd Engine && swift test`
Expected: all pre-existing tests still PASS (the new resource must not disturb `SeedLoaderTests`).

- [ ] **Step 7: Commit**

```bash
git add Engine/Sources/CardCopilotEngine/Loading/SeedLoader.swift Engine/Sources/CardCopilotEngine/Resources/benefits-catalogue.json Engine/Tests/CardCopilotEngineTests/BenefitsLoaderTests.swift
git commit -m "Load a stub benefits catalogue for the wallet"
```

---

### Task 3: BenefitsAdvisor path 1 — ambient checkout disclosures

**Files:**
- Create: `Engine/Sources/CardCopilotEngine/Engine/BenefitsAdvisor.swift`
- Test: `Engine/Tests/CardCopilotEngineTests/BenefitsAdvisorDisclosureTests.swift`

**Interfaces:**
- Consumes: Task 1 models; existing `PurchaseContext`.
- Produces: `BenefitDisclosure` (`cardId: String`, `kind: String`, `coverage: BenefitCoverage`, `conditions: [String]`, `exclusions: [String]`, `verification: BenefitVerification`), `CrossCardNudge` (`cardId: String`, `kind: String`), `DisclosureResult` (`recommended: [BenefitDisclosure]`, `nudges: [CrossCardNudge]`), `BenefitsAdvisor.disclosures(purchase:recommendedCardId:wallet:catalogue:) -> DisclosureResult`. (Task 4 adds `comparison` to the same enum.)

- [ ] **Step 1: Write the failing disclosure tests**

```swift
// Engine/Tests/CardCopilotEngineTests/BenefitsAdvisorDisclosureTests.swift
import XCTest
@testable import CardCopilotEngine

final class BenefitsAdvisorDisclosureTests: XCTestCase {

    // MARK: - Fixture builders (in-code, no JSON)

    private func benefit(_ id: String, family: String, kind: String,
                         configure: (inout BenefitCoverage) -> Void = { _ in }) -> Benefit {
        var coverage = BenefitCoverage()
        configure(&coverage)
        return Benefit(benefitId: id, family: family, kind: kind, coverage: coverage,
                       conditions: ["Full purchase charged to the card"],
                       exclusions: nil, certificateQuote: nil, notes: nil)
    }

    private func card(_ cardId: String, status: BenefitVerification = .stub,
                      benefits: [Benefit]) -> CardBenefits {
        CardBenefits(cardId: cardId,
                     certificate: CertificateProvenance(underwriter: nil, sourceUrl: nil,
                                                        certificateDate: nil, lastVerifiedAt: nil,
                                                        verificationStatus: status),
                     benefits: benefits)
    }

    private func catalogue(_ cards: [CardBenefits],
                           threshold: Double = 150,
                           consumables: [String] = ["dining", "grocery", "gasStation"]) -> BenefitsCatalogue {
        BenefitsCatalogue(benefitsCatalogueVersion: "test",
                          triggers: BenefitsTriggers(bigTicketThresholdCad: threshold,
                                                     consumableCategories: consumables),
                          cards: cards)
    }

    private var shoppingPair: [Benefit] {
        [benefit("a-pp", family: "shopping", kind: "purchaseProtection") { $0.windowDays = 90 },
         benefit("a-ew", family: "shopping", kind: "extendedWarranty") { $0.extraYears = 1 }]
    }

    private func purchase(amount: Double, category: String,
                          country: String = "CA", currency: String = "CAD") -> PurchaseContext {
        PurchaseContext(amountCad: amount, currency: currency, category: category, country: country)
    }

    // MARK: - Big-ticket shopping trigger

    func testBigTicketTriggersShoppingDisclosuresForRecommendedCard() {
        let cat = catalogue([card("winner", benefits: shoppingPair)])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 500, category: "other"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner"], catalogue: cat)
        XCTAssertEqual(result.recommended.map(\.kind).sorted(),
                       ["extendedWarranty", "purchaseProtection"])
        XCTAssertEqual(result.recommended.first?.verification, .stub)
    }

    func testExactlyAtThresholdTriggers() {
        let cat = catalogue([card("winner", benefits: shoppingPair)])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 150, category: "other"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner"], catalogue: cat)
        XCTAssertFalse(result.recommended.isEmpty)
    }

    func testBelowThresholdStaysQuiet() {
        let cat = catalogue([card("winner", benefits: shoppingPair)])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 149.99, category: "other"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner"], catalogue: cat)
        XCTAssertTrue(result.recommended.isEmpty)
        XCTAssertTrue(result.nudges.isEmpty)
    }

    func testConsumableCategoryNeverTriggersShopping() {
        let cat = catalogue([card("winner", benefits: shoppingPair)])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 500, category: "grocery"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner"], catalogue: cat)
        XCTAssertTrue(result.recommended.isEmpty)
    }

    // MARK: - Travel triggers

    func testHotelCategoryTriggersTravelKinds() {
        let travel = [benefit("a-fd", family: "travelDisruption", kind: "flightDelay") { $0.delayHours = 4 },
                      benefit("a-tm", family: "travelMedical", kind: "travelMedical") { $0.maxCad = 1_000_000 }]
        let cat = catalogue([card("winner", benefits: travel + shoppingPair)])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 80, category: "hotel"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner"], catalogue: cat)
        // Amount is under the big-ticket threshold: travel families only, no shopping kinds.
        XCTAssertEqual(result.recommended.map(\.kind).sorted(), ["flightDelay", "travelMedical"])
    }

    func testForeignCountryTriggersTravelKinds() {
        let travel = [benefit("a-tm", family: "travelMedical", kind: "travelMedical") { $0.maxCad = 1_000_000 }]
        let cat = catalogue([card("winner", benefits: travel)])
        let result = BenefitsAdvisor.disclosures(
            purchase: purchase(amount: 40, category: "dining", country: "US"),
            recommendedCardId: "winner", wallet: ["winner"], catalogue: cat)
        XCTAssertEqual(result.recommended.map(\.kind), ["travelMedical"])
    }

    func testForeignCurrencyTriggersTravelKinds() {
        let travel = [benefit("a-tm", family: "travelMedical", kind: "travelMedical") { $0.maxCad = 1_000_000 }]
        let cat = catalogue([card("winner", benefits: travel)])
        let result = BenefitsAdvisor.disclosures(
            purchase: purchase(amount: 40, category: "dining", currency: "USD"),
            recommendedCardId: "winner", wallet: ["winner"], catalogue: cat)
        XCTAssertEqual(result.recommended.map(\.kind), ["travelMedical"])
    }

    // MARK: - Cross-card nudges

    func testNudgeWhenAnotherCardHasAKindTheWinnerLacks() {
        let other = card("other", benefits: [
            benefit("o-md", family: "shopping", kind: "mobileDeviceInsurance") { $0.maxCad = 1000 }])
        let cat = catalogue([card("winner", benefits: shoppingPair), other])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 500, category: "other"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner", "other"], catalogue: cat)
        XCTAssertEqual(result.nudges, [CrossCardNudge(cardId: "other", kind: "mobileDeviceInsurance")])
    }

    func testNoNudgeForKindsTheWinnerAlreadyHas() {
        let other = card("other", benefits: shoppingPair.map {
            var b = $0; b.benefitId = "other-" + b.benefitId; return b
        })
        let cat = catalogue([card("winner", benefits: shoppingPair), other])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 500, category: "other"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner", "other"], catalogue: cat)
        XCTAssertTrue(result.nudges.isEmpty)
    }

    func testNudgesDedupeByKindInWalletOrder() {
        let second = card("second", benefits: [
            benefit("s-md", family: "shopping", kind: "mobileDeviceInsurance") { $0.maxCad = 800 }])
        let third = card("third", benefits: [
            benefit("t-md", family: "shopping", kind: "mobileDeviceInsurance") { $0.maxCad = 1000 }])
        let cat = catalogue([card("winner", benefits: shoppingPair), second, third])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 500, category: "other"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner", "second", "third"], catalogue: cat)
        XCTAssertEqual(result.nudges, [CrossCardNudge(cardId: "second", kind: "mobileDeviceInsurance")])
    }

    func testNoTriggerMeansNoNudges() {
        let other = card("other", benefits: [
            benefit("o-md", family: "shopping", kind: "mobileDeviceInsurance") { $0.maxCad = 1000 }])
        let cat = catalogue([card("winner", benefits: []), other])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 20, category: "dining"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner", "other"], catalogue: cat)
        XCTAssertTrue(result.recommended.isEmpty)
        XCTAssertTrue(result.nudges.isEmpty)
    }

    func testUnknownKindsAreIgnored() {
        let weird = [benefit("w-x", family: "shopping", kind: "cellPlanInsurance")]
        let cat = catalogue([card("winner", benefits: weird)])
        let result = BenefitsAdvisor.disclosures(purchase: purchase(amount: 500, category: "other"),
                                                 recommendedCardId: "winner",
                                                 wallet: ["winner"], catalogue: cat)
        XCTAssertTrue(result.recommended.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Engine && swift test --filter BenefitsAdvisorDisclosureTests`
Expected: compile failure — `BenefitsAdvisor` does not exist.

- [ ] **Step 3: Implement the advisor's disclosure path**

```swift
// Engine/Sources/CardCopilotEngine/Engine/BenefitsAdvisor.swift
import Foundation

/// Pure benefits logic — the disclosure half of spec §5. Deliberately has no path into the
/// scoring pipeline and is never called by it (spec B1): earn advice and protection facts
/// meet only in the UI, side by side. Nothing here is a value judgement; every output is a
/// fact from a certificate, carried with its verification status.
public struct BenefitDisclosure: Equatable, Sendable, Identifiable {
    public let cardId: String
    public let kind: String
    public let coverage: BenefitCoverage
    public let conditions: [String]
    public let exclusions: [String]
    public let verification: BenefitVerification

    /// Stable identity for SwiftUI sheets/lists.
    public var id: String { cardId + "/" + kind }

    public init(cardId: String, kind: String, coverage: BenefitCoverage,
                conditions: [String], exclusions: [String],
                verification: BenefitVerification) {
        self.cardId = cardId
        self.kind = kind
        self.coverage = coverage
        self.conditions = conditions
        self.exclusions = exclusions
        self.verification = verification
    }
}

/// "Another wallet card has coverage the recommended card lacks entirely." Never re-ranks —
/// the UI renders it as a compare link into the protection lens (spec §6).
public struct CrossCardNudge: Equatable, Sendable {
    public let cardId: String
    public let kind: String

    public init(cardId: String, kind: String) {
        self.cardId = cardId
        self.kind = kind
    }
}

public struct DisclosureResult: Equatable, Sendable {
    public let recommended: [BenefitDisclosure]
    public let nudges: [CrossCardNudge]
}

public enum BenefitsAdvisor {

    /// Path 1 — ambient disclosure at checkout. Conservative triggers over the checkout's
    /// existing facts (spec §5): big-ticket non-consumable spend surfaces the shopping
    /// family; hotel category or foreign country/currency surfaces the travel families.
    public static func disclosures(purchase: PurchaseContext,
                                   recommendedCardId: String,
                                   wallet: [String],
                                   catalogue: BenefitsCatalogue) -> DisclosureResult {
        let families = triggeredFamilies(purchase: purchase, triggers: catalogue.triggers)
        guard !families.isEmpty else { return DisclosureResult(recommended: [], nudges: []) }

        let recommended = relevantBenefits(of: recommendedCardId, families: families,
                                           catalogue: catalogue)
        let recommendedKinds = Set(recommended.map(\.kind))

        var nudges: [CrossCardNudge] = []
        var nudgedKinds: Set<String> = []
        for cardId in wallet where cardId != recommendedCardId {
            for disclosure in relevantBenefits(of: cardId, families: families, catalogue: catalogue)
            where !recommendedKinds.contains(disclosure.kind) && !nudgedKinds.contains(disclosure.kind) {
                nudges.append(CrossCardNudge(cardId: cardId, kind: disclosure.kind))
                nudgedKinds.insert(disclosure.kind)
            }
        }
        return DisclosureResult(recommended: recommended, nudges: nudges)
    }

    // MARK: - Shared internals (Task 4 reuses these)

    static func triggeredFamilies(purchase: PurchaseContext,
                                  triggers: BenefitsTriggers) -> Set<BenefitFamily> {
        var families: Set<BenefitFamily> = []
        if purchase.amountCad >= triggers.bigTicketThresholdCad
            && !triggers.consumableCategories.contains(purchase.category) {
            families.insert(.shopping)
        }
        if purchase.category == "hotel" || purchase.country != "CA" || purchase.currency != "CAD" {
            families.insert(.travelDisruption)
            families.insert(.travelMedical)
        }
        return families
    }

    static func relevantBenefits(of cardId: String, families: Set<BenefitFamily>,
                                 catalogue: BenefitsCatalogue) -> [BenefitDisclosure] {
        guard let card = catalogue.card(cardId) else { return [] }
        return card.benefits.compactMap { benefit in
            guard benefit.knownKind != nil,
                  let family = benefit.knownFamily, families.contains(family) else { return nil }
            return disclosure(benefit, cardId: cardId,
                              verification: card.certificate.verificationStatus)
        }
    }

    static func disclosure(_ benefit: Benefit, cardId: String,
                           verification: BenefitVerification) -> BenefitDisclosure {
        BenefitDisclosure(cardId: cardId, kind: benefit.kind, coverage: benefit.coverage,
                          conditions: benefit.conditions, exclusions: benefit.exclusions ?? [],
                          verification: verification)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Engine && swift test --filter BenefitsAdvisorDisclosureTests`
Expected: 12 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add Engine/Sources/CardCopilotEngine/Engine/BenefitsAdvisor.swift Engine/Tests/CardCopilotEngineTests/BenefitsAdvisorDisclosureTests.swift
git commit -m "Trigger ambient benefit disclosures at checkout"
```

---

### Task 4: BenefitsAdvisor path 2 — protection comparison with Pareto dominance

**Files:**
- Modify: `Engine/Sources/CardCopilotEngine/Engine/BenefitsAdvisor.swift` (append types + `comparison`)
- Test: `Engine/Tests/CardCopilotEngineTests/BenefitsComparisonTests.swift`

**Interfaces:**
- Consumes: Task 1 models; Task 3's `BenefitDisclosure` and internals `relevantBenefits`/`disclosure`.
- Produces: `BenefitContextKind` (`flight|trip|carRental|electronics|mobileDevice|applianceFurniture`), `BenefitContext` (`kind`, `abroad: Bool`, `relevantKinds: [BenefitKind]`), `ProtectionComparison` (`relevantKinds: [BenefitKind]`, `columns: [Column]` where `Column` = `cardId`, `verification`, `byKind: [String: BenefitDisclosure]`; `absent: [AbsentCard]` where `AbsentCard` = `cardId`, `verification`; `dominantCardId: String?`), `BenefitsAdvisor.comparison(context:wallet:catalogue:) -> ProtectionComparison`.

- [ ] **Step 1: Write the failing comparison tests**

```swift
// Engine/Tests/CardCopilotEngineTests/BenefitsComparisonTests.swift
import XCTest
@testable import CardCopilotEngine

final class BenefitsComparisonTests: XCTestCase {

    private func benefit(_ id: String, family: String, kind: String,
                         configure: (inout BenefitCoverage) -> Void = { _ in }) -> Benefit {
        var coverage = BenefitCoverage()
        configure(&coverage)
        return Benefit(benefitId: id, family: family, kind: kind, coverage: coverage,
                       conditions: [], exclusions: nil, certificateQuote: nil, notes: nil)
    }

    private func card(_ cardId: String, status: BenefitVerification = .stub,
                      benefits: [Benefit]) -> CardBenefits {
        CardBenefits(cardId: cardId,
                     certificate: CertificateProvenance(underwriter: nil, sourceUrl: nil,
                                                        certificateDate: nil, lastVerifiedAt: nil,
                                                        verificationStatus: status),
                     benefits: benefits)
    }

    private func catalogue(_ cards: [CardBenefits]) -> BenefitsCatalogue {
        BenefitsCatalogue(benefitsCatalogueVersion: "test",
                          triggers: BenefitsTriggers(bigTicketThresholdCad: 150,
                                                     consumableCategories: []),
                          cards: cards)
    }

    // MARK: - Context → relevant kinds (spec §5 table)

    func testFlightContextPullsDisruptionKindsOnly() {
        let context = BenefitContext(kind: .flight)
        XCTAssertEqual(context.relevantKinds, [.flightDelay, .baggageDelay, .baggageLoss,
                                               .tripCancellation, .tripInterruption])
    }

    func testAbroadAddsTravelMedical() {
        XCTAssertTrue(BenefitContext(kind: .trip, abroad: true).relevantKinds.contains(.travelMedical))
        XCTAssertEqual(BenefitContext(kind: .carRental, abroad: true).relevantKinds,
                       [.rentalCdw, .travelMedical])
    }

    func testDeviceContextsPullShoppingKinds() {
        XCTAssertEqual(BenefitContext(kind: .electronics).relevantKinds,
                       [.purchaseProtection, .extendedWarranty])
        XCTAssertEqual(BenefitContext(kind: .mobileDevice).relevantKinds,
                       [.purchaseProtection, .extendedWarranty, .mobileDeviceInsurance])
    }

    // MARK: - Column assembly

    func testOnlyCardsWithRelevantCoverageBecomeColumns() {
        let flighty = card("flighty", benefits: [
            benefit("f-fd", family: "travelDisruption", kind: "flightDelay") { $0.delayHours = 4 }])
        let shopper = card("shopper", benefits: [
            benefit("s-pp", family: "shopping", kind: "purchaseProtection") { $0.windowDays = 90 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["flighty", "shopper"],
                                                    catalogue: catalogue([flighty, shopper]))
        XCTAssertEqual(comparison.columns.map(\.cardId), ["flighty"])
        XCTAssertEqual(comparison.absent.map(\.cardId), ["shopper"])
    }

    func testAbsentCardsCarryVerificationStatus() {
        // Spec B8: absence at stub = "unknown"; absence at certificateVerified = "no coverage".
        // The engine reports the status; the UI renders the difference.
        let covered = card("covered", benefits: [
            benefit("c-fd", family: "travelDisruption", kind: "flightDelay") { $0.delayHours = 4 }])
        let verified = card("verifiedEmpty", status: .certificateVerified, benefits: [])
        let stubby = card("stubEmpty", status: .stub, benefits: [])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["covered", "verifiedEmpty", "stubEmpty"],
                                                    catalogue: catalogue([covered, verified, stubby]))
        XCTAssertEqual(comparison.absent.map(\.cardId), ["verifiedEmpty", "stubEmpty"])
        XCTAssertEqual(comparison.absent.map(\.verification), [.certificateVerified, .stub])
    }

    // MARK: - Dominance (spec B7)

    func testUniqueDominantGetsBadge() {
        let strong = card("strong", benefits: [
            benefit("st-fd", family: "travelDisruption", kind: "flightDelay") {
                $0.delayHours = 4; $0.maxCad = 1000 }])
        let weak = card("weak", benefits: [
            benefit("w-fd", family: "travelDisruption", kind: "flightDelay") {
                $0.delayHours = 4; $0.maxCad = 500 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["strong", "weak"],
                                                    catalogue: catalogue([strong, weak]))
        XCTAssertEqual(comparison.dominantCardId, "strong")
    }

    func testIdenticalCoverageIsATieAndNoBadge() {
        let a = card("a", benefits: [
            benefit("a-fd", family: "travelDisruption", kind: "flightDelay") { $0.delayHours = 4 }])
        let b = card("b", benefits: [
            benefit("b-fd", family: "travelDisruption", kind: "flightDelay") { $0.delayHours = 4 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["a", "b"],
                                                    catalogue: catalogue([a, b]))
        XCTAssertNil(comparison.dominantCardId)
    }

    func testGenuineTradeoffIsNoBadge() {
        // a pays out sooner (3h); b pays out more ($1000). Neither dominates.
        let a = card("a", benefits: [
            benefit("a-fd", family: "travelDisruption", kind: "flightDelay") {
                $0.delayHours = 3; $0.maxCad = 500 }])
        let b = card("b", benefits: [
            benefit("b-fd", family: "travelDisruption", kind: "flightDelay") {
                $0.delayHours = 6; $0.maxCad = 1000 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["a", "b"],
                                                    catalogue: catalogue([a, b]))
        XCTAssertNil(comparison.dominantCardId)
    }

    func testLowerDelayHoursIsBetter() {
        let fast = card("fast", benefits: [
            benefit("f-fd", family: "travelDisruption", kind: "flightDelay") {
                $0.delayHours = 3; $0.maxCad = 500 }])
        let slow = card("slow", benefits: [
            benefit("s-fd", family: "travelDisruption", kind: "flightDelay") {
                $0.delayHours = 6; $0.maxCad = 500 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["fast", "slow"],
                                                    catalogue: catalogue([fast, slow]))
        XCTAssertEqual(comparison.dominantCardId, "fast")
    }

    func testLowerDeductibleIsBetter() {
        let cheap = card("cheap", benefits: [
            benefit("c-md", family: "shopping", kind: "mobileDeviceInsurance") {
                $0.maxCad = 1000; $0.deductibleCad = 50 }])
        let dear = card("dear", benefits: [
            benefit("d-md", family: "shopping", kind: "mobileDeviceInsurance") {
                $0.maxCad = 1000; $0.deductibleCad = 100 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .mobileDevice),
                                                    wallet: ["cheap", "dear"],
                                                    catalogue: catalogue([cheap, dear]))
        XCTAssertEqual(comparison.dominantCardId, "cheap")
    }

    func testMissingKindIsWorstSoFullerCardDominates() {
        let full = card("full", benefits: [
            benefit("f-fd", family: "travelDisruption", kind: "flightDelay") { $0.delayHours = 4 },
            benefit("f-bl", family: "travelDisruption", kind: "baggageLoss") { $0.maxCad = 500 }])
        let partial = card("partial", benefits: [
            benefit("p-fd", family: "travelDisruption", kind: "flightDelay") { $0.delayHours = 4 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["full", "partial"],
                                                    catalogue: catalogue([full, partial]))
        XCTAssertEqual(comparison.dominantCardId, "full")
    }

    func testOnlyCoveredCardGetsBadge() {
        let only = card("only", benefits: [
            benefit("o-cdw", family: "rentalCdw", kind: "rentalCdw") { $0.maxRentalDays = 48 }])
        let none = card("none", benefits: [])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .carRental),
                                                    wallet: ["only", "none"],
                                                    catalogue: catalogue([only, none]))
        XCTAssertEqual(comparison.dominantCardId, "only")
    }

    func testNoCoverageAnywhereMeansNoColumnsNoBadge() {
        let a = card("a", benefits: [])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["a"], catalogue: catalogue([a]))
        XCTAssertTrue(comparison.columns.isEmpty)
        XCTAssertNil(comparison.dominantCardId)
    }

    func testUnknownKindEntriesNeverEnterComparison() {
        let a = card("a", benefits: [
            benefit("a-x", family: "travelDisruption", kind: "teleportationDelay") { $0.maxCad = 9999 }])
        let comparison = BenefitsAdvisor.comparison(context: BenefitContext(kind: .flight),
                                                    wallet: ["a"], catalogue: catalogue([a]))
        XCTAssertTrue(comparison.columns.isEmpty)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd Engine && swift test --filter BenefitsComparisonTests`
Expected: compile failure — `BenefitContext` does not exist.

- [ ] **Step 3: Append the comparison path to BenefitsAdvisor.swift**

```swift
// Append to Engine/Sources/CardCopilotEngine/Engine/BenefitsAdvisor.swift

/// The purchase kinds a user can declare in the protection lens. Deliberately NOT merchant
/// categories (spec B6): earn categories describe the merchant and are statement-verifiable;
/// these describe the purchase and only the buyer knows them.
public enum BenefitContextKind: String, CaseIterable, Sendable {
    case flight, trip, carRental, electronics, mobileDevice, applianceFurniture
}

public struct BenefitContext: Equatable, Sendable {
    public var kind: BenefitContextKind
    public var abroad: Bool

    public init(kind: BenefitContextKind, abroad: Bool = false) {
        self.kind = kind
        self.abroad = abroad
    }

    /// Spec §5 declared-context → relevant-kinds table.
    public var relevantKinds: [BenefitKind] {
        let base: [BenefitKind]
        switch kind {
        case .flight, .trip:
            base = [.flightDelay, .baggageDelay, .baggageLoss, .tripCancellation, .tripInterruption]
        case .carRental:
            base = [.rentalCdw]
        case .electronics, .applianceFurniture:
            return [.purchaseProtection, .extendedWarranty]
        case .mobileDevice:
            return [.purchaseProtection, .extendedWarranty, .mobileDeviceInsurance]
        }
        return abroad ? base + [.travelMedical] : base
    }
}

public struct ProtectionComparison: Equatable, Sendable {
    public struct Column: Equatable, Sendable {
        public let cardId: String
        public let verification: BenefitVerification
        /// Keyed by `BenefitKind.rawValue`; only relevant kinds appear.
        public let byKind: [String: BenefitDisclosure]
    }

    /// A wallet card with no relevant coverage. Absence semantics depend on verification
    /// (spec B8): stub = "unknown", certificateVerified = "no coverage". UI renders the difference.
    public struct AbsentCard: Equatable, Sendable {
        public let cardId: String
        public let verification: BenefitVerification
    }

    public let relevantKinds: [BenefitKind]
    public let columns: [Column]
    public let absent: [AbsentCard]
    /// Spec B7: set iff exactly one card is Pareto-maximal over every displayed coverage row.
    /// nil = genuine trade-off (or nothing to compare); UI shows "trade-off — your call".
    public let dominantCardId: String?
}

extension BenefitsAdvisor {

    /// Path 2 — the protection lens (spec §5). Facts per card for a declared purchase kind,
    /// plus a dominance verdict that only ever claims what the table beneath it shows.
    public static func comparison(context: BenefitContext,
                                  wallet: [String],
                                  catalogue: BenefitsCatalogue) -> ProtectionComparison {
        let kinds = context.relevantKinds
        let kindKeys = Set(kinds.map(\.rawValue))

        var columns: [ProtectionComparison.Column] = []
        var absent: [ProtectionComparison.AbsentCard] = []
        for cardId in wallet {
            guard let card = catalogue.card(cardId) else { continue }
            let relevant = card.benefits.filter {
                $0.knownKind != nil && kindKeys.contains($0.kind)
            }
            if relevant.isEmpty {
                absent.append(.init(cardId: cardId,
                                    verification: card.certificate.verificationStatus))
            } else {
                let byKind = Dictionary(relevant.map {
                    ($0.kind, disclosure($0, cardId: cardId,
                                         verification: card.certificate.verificationStatus))
                }, uniquingKeysWith: { first, _ in first })
                columns.append(.init(cardId: cardId,
                                     verification: card.certificate.verificationStatus,
                                     byKind: byKind))
            }
        }

        return ProtectionComparison(relevantKinds: kinds, columns: columns, absent: absent,
                                    dominantCardId: dominant(columns: columns, kinds: kinds))
    }

    // MARK: - Dominance internals

    /// Comparable coverage fields and their direction. Higher is better except where a
    /// lower number pays out sooner or costs less.
    private struct FieldSpec {
        let name: String
        let lowerIsBetter: Bool
        let value: (BenefitCoverage) -> Double?
    }

    private static let fieldSpecs: [FieldSpec] = [
        .init(name: "windowDays", lowerIsBetter: false) { $0.windowDays.map(Double.init) },
        .init(name: "maxPerOccurrenceCad", lowerIsBetter: false) { $0.maxPerOccurrenceCad },
        .init(name: "maxAnnualCad", lowerIsBetter: false) { $0.maxAnnualCad },
        .init(name: "extraYears", lowerIsBetter: false) { $0.extraYears.map(Double.init) },
        .init(name: "maxOriginalWarrantyYears", lowerIsBetter: false) { $0.maxOriginalWarrantyYears.map(Double.init) },
        .init(name: "maxCad", lowerIsBetter: false) { $0.maxCad },
        .init(name: "deductibleCad", lowerIsBetter: true) { $0.deductibleCad },
        .init(name: "delayHours", lowerIsBetter: true) { $0.delayHours.map(Double.init) },
        .init(name: "perDayCad", lowerIsBetter: false) { $0.perDayCad },
        .init(name: "maxTripLengthDays", lowerIsBetter: false) { $0.maxTripLengthDays.map(Double.init) },
        .init(name: "maxRentalDays", lowerIsBetter: false) { $0.maxRentalDays.map(Double.init) },
        .init(name: "maxVehicleValueCad", lowerIsBetter: false) { $0.maxVehicleValueCad },
        .init(name: "ageLimit", lowerIsBetter: false) { $0.ageLimit.map(Double.init) },
    ]

    /// Spec B7. Rows = every (relevant kind, coverage field) pair that any column has a
    /// value for. Scores are normalized so higher always means better; a card missing the
    /// kind or the field scores worst (-infinity). Badge iff exactly one maximal column.
    private static func dominant(columns: [ProtectionComparison.Column],
                                 kinds: [BenefitKind]) -> String? {
        guard !columns.isEmpty else { return nil }

        var rows: [[Double]] = []   // rows[r][columnIndex] = normalized score
        for kind in kinds {
            for spec in fieldSpecs {
                let raw = columns.map { column -> Double? in
                    column.byKind[kind.rawValue].flatMap { spec.value($0.coverage) }
                }
                guard raw.contains(where: { $0 != nil }) else { continue }
                rows.append(raw.map { value in
                    guard let value else { return -Double.infinity }
                    return spec.lowerIsBetter ? -value : value
                })
            }
        }
        // Presence itself is a row: covering a kind at all beats not covering it, even when
        // the certificate states no comparable number for it.
        for kind in kinds {
            let presence = columns.map { $0.byKind[kind.rawValue] != nil ? 1.0 : -Double.infinity }
            if presence.contains(1.0) { rows.append(presence) }
        }
        guard !rows.isEmpty else { return nil }

        func dominates(_ a: Int, _ b: Int) -> Bool {
            var strictlyBetterSomewhere = false
            for row in rows {
                if row[a] < row[b] { return false }
                if row[a] > row[b] { strictlyBetterSomewhere = true }
            }
            return strictlyBetterSomewhere
        }

        let maximal = columns.indices.filter { candidate in
            !columns.indices.contains { other in
                other != candidate && dominates(other, candidate)
            }
        }
        // A tie (identical rows) leaves every tied column maximal → no badge, exactly as
        // spec B7 requires "exactly one maximal card".
        guard maximal.count == 1 else { return nil }
        return columns[maximal[0]].cardId
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd Engine && swift test --filter BenefitsComparisonTests`
Expected: 14 tests PASS. Watch `testIdenticalCoverageIsATieAndNoBadge` — if it fails, the maximal-set logic is treating ties as dominance.

- [ ] **Step 5: Run the full engine suite**

Run: `cd Engine && swift test`
Expected: everything green (existing 67+ engine tests plus the new benefits tests).

- [ ] **Step 6: Commit**

```bash
git add Engine/Sources/CardCopilotEngine/Engine/BenefitsAdvisor.swift Engine/Tests/CardCopilotEngineTests/BenefitsComparisonTests.swift
git commit -m "Compare protection facts with a Pareto dominance verdict"
```

---

### Task 5: App wiring + checkout disclosure surface

**Files:**
- Create: `App/CardCopilot/Views/BenefitsFormatting.swift`
- Create: `App/CardCopilot/Views/BenefitsDisclosureSection.swift`
- Modify: `App/CardCopilot/Views/CheckoutFlowView.swift` (Dependencies + loadDependencies)
- Modify: `App/CardCopilot/Views/RecommendationView.swift` (compose the section into `singleView`)

**Interfaces:**
- Consumes: `SeedLoader.loadBenefitsCatalogue()`, `BenefitsAdvisor.disclosures(...)`, `DisclosureResult`, `BenefitDisclosure`, `CrossCardNudge`, `BenefitVerification`, `BenefitContext(Kind)`, `RecommendationEngine(catalogue:ownerState:)`; existing `CheckoutResult` (`.outcome`, `.prediction.category`, `.effectiveAmountCad`), `Recommendation.winner.cardId`.
- Produces: `CheckoutFlowView.Dependencies` gains `let benefits: BenefitsCatalogue` and `let engine: RecommendationEngine` (Tasks 6–7 rely on both); `BenefitsFormatting` helpers (`kindDisplayName(_: String) -> String`, `factsLine(for: BenefitCoverage, kind: String) -> String`, `contextKind(forNudgedKind: String) -> BenefitContextKind`, `certificateFooter: String`); `BenefitsDisclosureSection(result:deps:onCompare:)` view; `BenefitDetailSheet(disclosure:cardName:)` view (lives in BenefitsDisclosureSection.swift, reused by Tasks 6–7).

- [ ] **Step 1: Extend Dependencies and loadDependencies**

In `App/CardCopilot/Views/CheckoutFlowView.swift`, change the `Dependencies` struct to:

```swift
    struct Dependencies {
        let catalogue: Catalogue
        let benefits: BenefitsCatalogue
        let service: CheckoutService
        let explainer: RecommendationExplainer
        let engine: RecommendationEngine
        let provider: LiveMerchantProvider
    }
```

and in `loadDependencies()`, replace the `deps = Dependencies(...)` construction with:

```swift
            let benefits = try SeedLoader.loadBenefitsCatalogue()
            deps = Dependencies(
                catalogue: catalogue,
                benefits: benefits,
                service: CheckoutService(catalogue: catalogue, ownerState: owner,
                                         context: modelContext),
                explainer: RecommendationExplainer(catalogue: catalogue),
                // The lens computes its earn line through the engine directly — NEVER through
                // CheckoutService — so a lens query can't write a prediction (spec B9).
                engine: RecommendationEngine(catalogue: catalogue, ownerState: owner),
                provider: LiveMerchantProvider())
```

- [ ] **Step 2: Create the formatting helpers**

```swift
// App/CardCopilot/Views/BenefitsFormatting.swift
import Foundation
import CardCopilotEngine

/// Copy rules for every benefits surface (spec B2): facts from the certificate, stated as
/// facts — "per certificate", never "you're covered".
enum BenefitsFormatting {
    static let certificateFooter =
        "Coverage depends on certificate conditions — verify before relying on it."

    static func kindDisplayName(_ kind: String) -> String {
        switch BenefitKind(rawValue: kind) {
        case .purchaseProtection: return "Purchase protection"
        case .extendedWarranty: return "Extended warranty"
        case .mobileDeviceInsurance: return "Mobile device insurance"
        case .flightDelay: return "Flight delay"
        case .baggageDelay: return "Baggage delay"
        case .baggageLoss: return "Lost baggage"
        case .tripCancellation: return "Trip cancellation"
        case .tripInterruption: return "Trip interruption"
        case .rentalCdw: return "Rental car damage/theft"
        case .travelMedical: return "Emergency travel medical"
        case nil: return kind   // unknown kinds render raw, never crash
        }
    }

    /// Short factual fragment for a coverage block, e.g. "90 days · up to $1,000".
    static func factsLine(for coverage: BenefitCoverage, kind: String) -> String {
        var parts: [String] = []
        if let hours = coverage.delayHours { parts.append("\(hours) h+ delay") }
        if let days = coverage.windowDays { parts.append("\(days) days") }
        if let years = coverage.extraYears { parts.append("+\(years) yr warranty") }
        if let max = coverage.maxPerOccurrenceCad { parts.append("up to \(cad(max))") }
        if let max = coverage.maxCad { parts.append("up to \(cad(max))") }
        if let perDay = coverage.perDayCad { parts.append("\(cad(perDay))/day") }
        if let deductible = coverage.deductibleCad { parts.append("\(cad(deductible)) deductible") }
        if let days = coverage.maxTripLengthDays { parts.append("trips ≤ \(days) days") }
        if let days = coverage.maxRentalDays { parts.append("rentals ≤ \(days) days") }
        if let value = coverage.maxVehicleValueCad { parts.append("vehicles ≤ \(cad(value))") }
        if let age = coverage.ageLimit { parts.append("under \(age)") }
        return parts.isEmpty ? "see certificate" : parts.joined(separator: " · ")
    }

    /// Which lens context a cross-card nudge should open (kind → closest declared context).
    static func contextKind(forNudgedKind kind: String) -> BenefitContextKind {
        switch BenefitKind(rawValue: kind) {
        case .mobileDeviceInsurance: return .mobileDevice
        case .rentalCdw: return .carRental
        case .flightDelay, .baggageDelay, .baggageLoss,
             .tripCancellation, .tripInterruption, .travelMedical: return .trip
        default: return .electronics
        }
    }

    static func verificationLabel(_ verification: BenefitVerification) -> String {
        switch verification {
        case .stub: return "Unverified draft"
        case .issuerPage: return "Issuer page"
        case .certificateVerified: return "Certificate verified"
        }
    }

    private static func cad(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CAD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        return formatter.string(from: value as NSNumber) ?? "$\(Int(value))"
    }
}
```

- [ ] **Step 3: Create the disclosure section + detail sheet**

```swift
// App/CardCopilot/Views/BenefitsDisclosureSection.swift
import SwiftUI
import CardCopilotEngine
import CardCopilotStore

/// Quiet benefit facts under a single recommendation (spec §6.1): at most two lines for the
/// winning card, one compare-nudge when another card covers something the winner doesn't.
/// Facts only — this section never re-ranks and never says "covered".
struct BenefitsDisclosureSection: View {
    let result: CheckoutResult
    let deps: CheckoutFlowView.Dependencies
    let winnerCardId: String
    let onCompare: (BenefitContextKind) -> Void

    @State private var selectedDisclosure: BenefitDisclosure?

    private var disclosureResult: DisclosureResult {
        BenefitsAdvisor.disclosures(
            purchase: PurchaseContext(amountCad: result.effectiveAmountCad,
                                      category: result.prediction.category),
            recommendedCardId: winnerCardId,
            wallet: deps.catalogue.cards.map(\.cardId),
            catalogue: deps.benefits)
    }

    var body: some View {
        let disclosures = disclosureResult
        if !disclosures.recommended.isEmpty || !disclosures.nudges.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Divider()
                ForEach(disclosures.recommended.prefix(2), id: \.kind) { disclosure in
                    Button {
                        selectedDisclosure = disclosure
                    } label: {
                        Label {
                            Text("\(BenefitsFormatting.kindDisplayName(disclosure.kind)) · \(BenefitsFormatting.factsLine(for: disclosure.coverage, kind: disclosure.kind)) — per certificate")
                                .multilineTextAlignment(.leading)
                        } icon: {
                            Image(systemName: "checkmark.shield")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(disclosures.nudges.prefix(1), id: \.kind) { nudge in
                    Button {
                        onCompare(BenefitsFormatting.contextKind(forNudgedKind: nudge.kind))
                    } label: {
                        Label("\(cardName(nudge.cardId)) adds \(BenefitsFormatting.kindDisplayName(nudge.kind).lowercased()) — compare",
                              systemImage: "shield.lefthalf.filled")
                            .font(.footnote)
                    }
                    .buttonStyle(.plain)
                }

                Text(BenefitsFormatting.certificateFooter)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .sheet(item: $selectedDisclosure) { disclosure in
                BenefitDetailSheet(disclosure: disclosure, cardName: cardName(disclosure.cardId))
            }
        }
    }

    private func cardName(_ cardId: String) -> String {
        deps.catalogue.cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }
}

/// Full facts for one benefit: coverage numbers, then the certificate's own conditions and
/// exclusions verbatim (spec B2 — quoted, never summarized into promises).
struct BenefitDetailSheet: View {
    let disclosure: BenefitDisclosure
    let cardName: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Card", value: cardName)
                    LabeledContent("Coverage",
                                   value: BenefitsFormatting.factsLine(for: disclosure.coverage,
                                                                       kind: disclosure.kind))
                    LabeledContent("Status",
                                   value: BenefitsFormatting.verificationLabel(disclosure.verification))
                }
                if !disclosure.conditions.isEmpty {
                    Section("Conditions (per certificate)") {
                        ForEach(disclosure.conditions, id: \.self) { Text($0).font(.footnote) }
                    }
                }
                if !disclosure.exclusions.isEmpty {
                    Section("Exclusions (per certificate)") {
                        ForEach(disclosure.exclusions, id: \.self) { Text($0).font(.footnote) }
                    }
                }
                Section {
                    Text(BenefitsFormatting.certificateFooter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle(BenefitsFormatting.kindDisplayName(disclosure.kind))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 4: Compose into RecommendationView**

In `App/CardCopilot/Views/RecommendationView.swift`:

Add the callback **between `let deps` and `let onDone`** — position matters, because CheckoutFlowView uses the memberwise initializer and its argument order follows property order:

```swift
    let onCompare: ((BenefitContextKind) -> Void)?
```

(`import CardCopilotEngine` is already present in this file.) In `singleView(_:)`, after the `ForEach(explanation?.warningLines ...)` block and inside the same `VStack`, append:

```swift
            if let deps {
                BenefitsDisclosureSection(result: result,
                                          deps: deps,
                                          winnerCardId: recommendation.winner.cardId,
                                          onCompare: { onCompare?($0) })
            }
```

The fork view gets **no** disclosure section: an ambiguous category means the ambient trigger's category test has nothing honest to bind to (spec §6.1 applies to the single verdict).

In `CheckoutFlowView.swift`, update the `RecommendationView` construction to pass the new parameter (the lens stage arrives in Task 6; until then it's nil):

```swift
        case .recommendation(let result):
            RecommendationView(result: result,
                               deps: deps,
                               onCompare: nil,
                               onDone: {
                                   refreshHome()
                                   stage = .idle
                               })
```

- [ ] **Step 5: Build to verify**

Run: `xcodebuild -project App/CardCopilot.xcodeproj -scheme CardCopilot -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`. (Synchronized folders pick the new files up automatically.)

- [ ] **Step 6: Commit**

```bash
git add App/CardCopilot/Views/BenefitsFormatting.swift App/CardCopilot/Views/BenefitsDisclosureSection.swift App/CardCopilot/Views/CheckoutFlowView.swift App/CardCopilot/Views/RecommendationView.swift
git commit -m "Disclose the winning card's benefits at checkout"
```

---

### Task 6: Protection lens

**Files:**
- Create: `App/CardCopilot/Views/ProtectionLensView.swift`
- Modify: `App/CardCopilot/Views/CheckoutFlowView.swift` (new stage + Home callback + lens-from-checkout)
- Modify: `App/CardCopilot/Views/HomeView.swift` (add "Big purchase or trip" button)
- Modify: `App/CardCopilot/Views/RecommendationView.swift` (no change beyond Task 5's `onCompare` — listed for the wiring test below)

**Interfaces:**
- Consumes: `BenefitsAdvisor.comparison(context:wallet:catalogue:)`, `ProtectionComparison(.columns/.absent/.dominantCardId/.relevantKinds)`, `BenefitContext(Kind)`, `deps.engine.recommend(_:asOf:)` → `Recommendation.winner` (`.cardId`, `.netValueCad`), `BenefitsFormatting`, `BenefitDetailSheet`.
- Produces: `ProtectionLensView(deps:initialContext:onDone:)`; `CheckoutFlowView.Stage.protectionLens(BenefitContext)`; `HomeView` gains `onProtectionLens: () -> Void`.

- [ ] **Step 1: Create the lens view**

```swift
// App/CardCopilot/Views/ProtectionLensView.swift
import SwiftUI
import CardCopilotEngine

/// The "two runs" screen (spec §6.2): declare a planned purchase, see which card earns best
/// and — separately — what each card's certificate says about protecting it. The two rankings
/// are never merged; when certificates genuinely trade off, the screen says so instead of
/// hiding the judgement inside a weight nobody chose (spec B7).
struct ProtectionLensView: View {
    let deps: CheckoutFlowView.Dependencies
    let initialContext: BenefitContext
    let onDone: () -> Void

    @State private var contextKind: BenefitContextKind
    @State private var abroad: Bool
    @State private var amountText = ""
    @State private var selectedDisclosure: BenefitDisclosure?

    init(deps: CheckoutFlowView.Dependencies,
         initialContext: BenefitContext = BenefitContext(kind: .flight),
         onDone: @escaping () -> Void) {
        self.deps = deps
        self.initialContext = initialContext
        self.onDone = onDone
        _contextKind = State(initialValue: initialContext.kind)
        _abroad = State(initialValue: initialContext.abroad)
    }

    private var context: BenefitContext { BenefitContext(kind: contextKind, abroad: abroad) }

    private var comparison: ProtectionComparison {
        BenefitsAdvisor.comparison(context: context,
                                   wallet: deps.catalogue.cards.map(\.cardId),
                                   catalogue: deps.benefits)
    }

    private var amountCad: Double? {
        Double(amountText.replacingOccurrences(of: "$", with: "")
                         .replacingOccurrences(of: ",", with: ""))
            .flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        List {
            contextSection
            earnSection
            verdictSection
            ForEach(comparison.columns, id: \.cardId) { column in
                cardSection(column)
            }
            absentSection
            Section {
                Text(BenefitsFormatting.certificateFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Big purchase or trip")
        .toolbar { Button("Done") { onDone() } }
        .sheet(item: $selectedDisclosure) { disclosure in
            BenefitDetailSheet(disclosure: disclosure, cardName: cardName(disclosure.cardId))
        }
    }

    private var contextSection: some View {
        Section("What are you buying?") {
            Picker("Kind", selection: $contextKind) {
                Text("Flight").tag(BenefitContextKind.flight)
                Text("Trip").tag(BenefitContextKind.trip)
                Text("Car rental").tag(BenefitContextKind.carRental)
                Text("Electronics").tag(BenefitContextKind.electronics)
                Text("Phone").tag(BenefitContextKind.mobileDevice)
                Text("Appliance/furniture").tag(BenefitContextKind.applianceFurniture)
            }
            Toggle("Outside Canada", isOn: $abroad)
            TextField("Amount (optional)", text: $amountText)
                .keyboardType(.decimalPad)
        }
    }

    /// The earn run — computed by the engine directly so nothing is logged (spec B9).
    @ViewBuilder
    private var earnSection: some View {
        if let amount = amountCad {
            let today = Date().formatted(.iso8601.year().month().day())
            let recommendation = deps.engine.recommend(
                PurchaseContext(amountCad: amount, category: "other"), asOf: today)
            Section("Best earn") {
                LabeledContent(cardName(recommendation.winner.cardId),
                               value: String(format: "≈ $%.2f back", recommendation.winner.netValueCad))
                Text("Earn and protection are separate calls — the best earner isn't always the best protector.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var verdictSection: some View {
        if comparison.columns.isEmpty {
            Section("Protection") {
                Text("No relevant coverage found in your wallet for this purchase kind.")
                    .foregroundStyle(.secondary)
            }
        } else if let dominant = comparison.dominantCardId {
            Section("Protection") {
                Label("\(cardName(dominant)) — equal or better on every line below",
                      systemImage: "shield.checkerboard")
                    .font(.headline)
            }
        } else {
            Section("Protection") {
                Label("Trade-off — your call. No card wins every line below.",
                      systemImage: "scalemass")
                    .font(.headline)
            }
        }
    }

    private func cardSection(_ column: ProtectionComparison.Column) -> some View {
        Section {
            ForEach(comparison.relevantKinds, id: \.rawValue) { kind in
                if let disclosure = column.byKind[kind.rawValue] {
                    Button { selectedDisclosure = disclosure } label: {
                        LabeledContent(BenefitsFormatting.kindDisplayName(kind.rawValue),
                                       value: BenefitsFormatting.factsLine(for: disclosure.coverage,
                                                                           kind: kind.rawValue))
                            .font(.footnote)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            HStack {
                Text(cardName(column.cardId))
                Spacer()
                Text(BenefitsFormatting.verificationLabel(column.verification))
                    .font(.caption2)
                    .foregroundStyle(column.verification == .certificateVerified ? .green : .orange)
            }
        }
    }

    /// Spec B8: absence only means "no coverage" once the certificate proved the negative.
    @ViewBuilder
    private var absentSection: some View {
        if !comparison.absent.isEmpty {
            Section("Not covering this") {
                ForEach(comparison.absent, id: \.cardId) { absent in
                    LabeledContent(cardName(absent.cardId),
                                   value: absent.verification == .certificateVerified
                                       ? "No coverage"
                                       : "Unknown — unverified")
                        .font(.footnote)
                }
            }
        }
    }

    private func cardName(_ cardId: String) -> String {
        deps.catalogue.cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }
}
```

- [ ] **Step 2: Wire the stage, Home button, and checkout nudge**

In `App/CardCopilot/Views/CheckoutFlowView.swift`:

1. Add a case to `Stage`:

```swift
        case protectionLens(BenefitContext)
```

2. In the `content` switch, add before `case .failed`:

```swift
        case .protectionLens(let context):
            if let deps {
                ProtectionLensView(deps: deps,
                                   initialContext: context,
                                   onDone: { stage = .idle })
            }
```

3. In `case .idle`, pass the new HomeView callback (after `onDashboard`):

```swift
                     onProtectionLens: { stage = .protectionLens(BenefitContext(kind: .flight)) })
```

4. In `case .recommendation`, replace `onCompare: nil` (from Task 5) with:

```swift
                               onCompare: { kind in stage = .protectionLens(BenefitContext(kind: kind)) },
```

In `App/CardCopilot/Views/HomeView.swift`:

1. Add the property after `let onDashboard: () -> Void`:

```swift
    let onProtectionLens: () -> Void
```

2. Append a button at the end of `primaryActions`'s `VStack` (after the search `HStack`):

```swift
            Button(action: onProtectionLens) {
                Label("Big purchase or trip", systemImage: "shield.lefthalf.filled")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project App/CardCopilot.xcodeproj -scheme CardCopilot -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`. If HomeView call sites fail to compile, the new `onProtectionLens` argument is missing where `HomeView(` is constructed — CheckoutFlowView is the only call site.

- [ ] **Step 4: Commit**

```bash
git add App/CardCopilot/Views/ProtectionLensView.swift App/CardCopilot/Views/CheckoutFlowView.swift App/CardCopilot/Views/HomeView.swift
git commit -m "Add the protection lens for planned purchases"
```

---

### Task 7: Benefits reference screen (doubles as the verification checklist)

**Files:**
- Create: `App/CardCopilot/Views/BenefitsReferenceView.swift`
- Modify: `App/CardCopilot/Views/CheckoutFlowView.swift` (stage + Home callback)
- Modify: `App/CardCopilot/Views/HomeView.swift` (row near the dashboard row)

**Interfaces:**
- Consumes: `deps.benefits` (`BenefitsCatalogue.cards`), `deps.catalogue` (card names), `BenefitsFormatting`, `BenefitDetailSheet`, `BenefitFamily`.
- Produces: `BenefitsReferenceView(deps:onDone:)`; `CheckoutFlowView.Stage.benefitsReference`; `HomeView` gains `onBenefits: () -> Void`.

- [ ] **Step 1: Create the reference view**

```swift
// App/CardCopilot/Views/BenefitsReferenceView.swift
import SwiftUI
import CardCopilotEngine

/// Per-card benefits browser (spec §6.3) — and, deliberately, Zubair's verification
/// checklist: the day every chip on this screen reads "Certificate verified", the benefits
/// data phase is done. The JSON file stays the single source of truth; nothing edits here.
struct BenefitsReferenceView: View {
    let deps: CheckoutFlowView.Dependencies
    let onDone: () -> Void

    var body: some View {
        List(deps.benefits.cards) { card in
            NavigationLink {
                CardBenefitsDetailView(card: card, cardName: cardName(card.cardId))
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cardName(card.cardId))
                        Text(card.benefits.isEmpty
                             ? (card.certificate.verificationStatus == .certificateVerified
                                ? "No coverage" : "Unknown — unverified")
                             : "\(card.benefits.count) benefits")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(BenefitsFormatting.verificationLabel(card.certificate.verificationStatus))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(chipColor(card.certificate.verificationStatus).opacity(0.15),
                                    in: Capsule())
                        .foregroundStyle(chipColor(card.certificate.verificationStatus))
                }
            }
        }
        .navigationTitle("Card benefits")
        .toolbar { Button("Done") { onDone() } }
    }

    private func cardName(_ cardId: String) -> String {
        deps.catalogue.cards.first { $0.cardId == cardId }?.officialName ?? cardId
    }

    private func chipColor(_ verification: BenefitVerification) -> Color {
        switch verification {
        case .stub: return .orange
        case .issuerPage: return .blue
        case .certificateVerified: return .green
        }
    }
}

struct CardBenefitsDetailView: View {
    let card: CardBenefits
    let cardName: String

    @State private var selectedDisclosure: BenefitDisclosure?

    private var families: [(name: String, benefits: [Benefit])] {
        let order = ["shopping", "travelDisruption", "rentalCdw", "travelMedical"]
        let grouped = Dictionary(grouping: card.benefits, by: \.family)
        let known = order.compactMap { family in
            grouped[family].map { (familyDisplayName(family), $0) }
        }
        let unknown = grouped.filter { !order.contains($0.key) }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }   // future families render raw, never crash
        return known + unknown
    }

    var body: some View {
        List {
            if card.benefits.isEmpty {
                Section {
                    Text(card.certificate.verificationStatus == .certificateVerified
                         ? "The certificate confirms no coverage on this card."
                         : "No coverage found yet — unverified. The certificate pass will settle it.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(families, id: \.name) { family in
                Section(family.name) {
                    ForEach(family.benefits, id: \.benefitId) { benefit in
                        Button {
                            selectedDisclosure = BenefitDisclosure(
                                cardId: card.cardId, kind: benefit.kind,
                                coverage: benefit.coverage, conditions: benefit.conditions,
                                exclusions: benefit.exclusions ?? [],
                                verification: card.certificate.verificationStatus)
                        } label: {
                            LabeledContent(BenefitsFormatting.kindDisplayName(benefit.kind),
                                           value: BenefitsFormatting.factsLine(for: benefit.coverage,
                                                                               kind: benefit.kind))
                                .font(.footnote)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section {
                Text(BenefitsFormatting.certificateFooter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(cardName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedDisclosure) { disclosure in
            BenefitDetailSheet(disclosure: disclosure, cardName: cardName)
        }
    }

    private func familyDisplayName(_ family: String) -> String {
        switch BenefitFamily(rawValue: family) {
        case .shopping: return "Shopping"
        case .travelDisruption: return "Travel disruption"
        case .rentalCdw: return "Rental car"
        case .travelMedical: return "Travel medical"
        case nil: return family
        }
    }
}
```

- [ ] **Step 2: Wire the stage and Home row**

In `App/CardCopilot/Views/CheckoutFlowView.swift`:

1. Add to `Stage`:

```swift
        case benefitsReference
```

2. In `content`, before `case .failed`:

```swift
        case .benefitsReference:
            if let deps {
                BenefitsReferenceView(deps: deps, onDone: { stage = .idle })
            }
```

3. In `case .idle`, pass (after `onProtectionLens`):

```swift
                     onBenefits: { stage = .benefitsReference })
```

In `App/CardCopilot/Views/HomeView.swift`:

1. Add the property after `let onProtectionLens: () -> Void`:

```swift
    let onBenefits: () -> Void
```

2. In `experimentRows`, after the dashboard row's `Button`, add a row using the existing private helper `homeRow(icon:tint:title:subtitle:)` (defined at `HomeView.swift:98`; all four arguments are required):

```swift
            Button(action: onBenefits) {
                homeRow(icon: "shield.lefthalf.filled",
                        tint: .secondary,
                        title: "Card benefits",
                        subtitle: "What your cards cover — per certificate")
            }
            .buttonStyle(.plain)
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild -project App/CardCopilot.xcodeproj -scheme CardCopilot -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Run the full engine suite one more time (nothing engine-side should have moved)**

Run: `cd Engine && swift test`
Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add App/CardCopilot/Views/BenefitsReferenceView.swift App/CardCopilot/Views/CheckoutFlowView.swift App/CardCopilot/Views/HomeView.swift
git commit -m "Browse card benefits with verification status"
```

---

### Task 8: Extraction template for the certificate dossier

**Files:**
- Create: `docs/research/benefits-extraction-template.md`

**Interfaces:**
- Consumes: the schema from Task 1 and the stub file from Task 2 (the skeleton Zubair edits IS `Engine/Sources/CardCopilotEngine/Resources/benefits-catalogue.json`).
- Produces: a self-contained instruction doc for the certificate-reading session.

- [ ] **Step 1: Write the template**

```markdown
# Benefits Extraction Template — Certificate Dossier Session

**Who:** Zubair, with each card's actual cardholder documents (certificates of insurance).
**What you edit:** `Engine/Sources/CardCopilotEngine/Resources/benefits-catalogue.json` — directly. It ships pre-filled with stub entries so you correct values instead of typing structure.
**Definition of done:** every card's `verificationStatus` is `certificateVerified`, then delete the loader test `testEveryShippedEntryIsStub` (it exists to keep the stub honest, not to survive your dossier).

## Per-card workflow

1. Find the card's **certificate of insurance** (the PDF in your cardholder agreement package — NOT the marketing page). Record its URL in `certificate.sourceUrl` and its printed date in `certificate.certificateDate` (`YYYY-MM` is fine). Certificates vary by issue date — yours is the ground truth, not the current public one.
2. Record the **underwriter** (named on the certificate's first page).
3. For each benefit the certificate grants, fill the matching entry (or add one; `benefitId` = `<card>-<kind>` kebab-case). Delete stub entries the certificate does not support — **absence after verification means "no coverage" and the app will say so** (spec B8).
4. Copy 1–3 load-bearing **conditions** verbatim into `conditions` (the ones that decide whether coverage applies: "full amount charged", trip-length limits, "decline the agency's CDW"). Same for `exclusions` that would surprise you (vehicle classes, unattended items, age limits).
5. Set `verificationStatus` to `certificateVerified` (or `issuerPage` if you only checked the public page — the UI will keep showing it as unverified-ish orange until certificate level).
6. Run `cd Engine && swift test --filter BenefitsLoaderTests` — it checks card-ID consistency and vocabulary; it will also tell you (via `testEveryShippedEntryIsStub` failing) that it's time to delete that test.

## Field guide by kind (units matter)

| Kind | Coverage fields to extract | Where it hides in the certificate |
|---|---|---|
| `purchaseProtection` | `windowDays` (days from purchase), `maxPerOccurrenceCad`, `maxAnnualCad` | "Purchase Security/Protection" section; window is usually 90–120 days |
| `extendedWarranty` | `extraYears`, `maxOriginalWarrantyYears` (doubles/extends up to N years original) | "Extended Warranty"; note the cap on the ORIGINAL warranty length |
| `mobileDeviceInsurance` | `maxCad`, `deductibleCad` | Standalone section; check whether financing/monthly-plan billing also qualifies — that's a condition |
| `flightDelay` | `delayHours` (threshold), `maxCad` | "Flight/Travel Delay"; the hour threshold is the load-bearing number |
| `baggageDelay` | `delayHours`, `maxCad` | Often shares a section with flight delay; usually essentials-only — quote that condition |
| `baggageLoss` | `maxCad` | "Lost/Stolen Baggage"; per-trip vs per-person matters — note it |
| `tripCancellation` | `maxCad` | Pre-departure causes; "charged before cause arose" is the classic condition |
| `tripInterruption` | `maxCad` | Post-departure; often a different max than cancellation |
| `rentalCdw` | `maxRentalDays`, `maxVehicleValueCad` | "Rental Vehicle Damage/Theft"; the MSRP cap and rental-length cap are the two numbers that void claims |
| `travelMedical` | `maxCad`, `maxTripLengthDays`, `ageLimit` | Emergency medical; trip-length and age limits are the coverage-voiding numbers — extract exactly |

## Rules that keep the feature honest

- Numbers you can't find: leave the field `null` and note it in `notes` — a missing number renders as "see certificate", never as a guess.
- Never paraphrase a condition into the coverage numbers. If the certificate says "up to $500 per insured person per trip", `maxCad: 500` plus the verbatim condition string.
- The engine treats `delayHours` and `deductibleCad` as lower-is-better and everything else as higher-is-better when computing the dominance badge — if a field doesn't fit that reading for some certificate, put the number in `notes`/`conditions` instead of the typed field.
```

- [ ] **Step 2: Verify the referenced paths exist**

Run: `ls Engine/Sources/CardCopilotEngine/Resources/benefits-catalogue.json docs/research/`
Expected: both exist (Task 2 created the JSON; `docs/research/` already holds the earn-rules dossier).

- [ ] **Step 3: Commit**

```bash
git add docs/research/benefits-extraction-template.md
git commit -m "Add the certificate extraction template"
```

---

### Task 9: Simulator smoke pass + plan closeout

**Files:**
- Modify: `docs/plans/2026-08-16-benefits-implementation-plan.md` (tick checkboxes as completed)

- [ ] **Step 1: Full test gate**

Run: `cd Engine && swift test && cd ../Store && swift test`
Expected: every suite green (Engine now ≈96+ tests including ~36 new benefits tests; Store's 29 untouched).

- [ ] **Step 2: Simulator smoke pass**

Launch the app in the iOS simulator (use the project's run tooling). Verify, in order:
1. Home shows the "Big purchase or trip" button and the "Card benefits" row.
2. A manual-search checkout ≥ $150 at a non-consumable merchant shows benefit lines under the single recommendation with the "per certificate" suffix and the footer; tapping a line opens the detail sheet with conditions and an "Unverified draft" status.
3. The lens: Flight context lists disruption kinds per covered card; toggling "Outside Canada" adds travel medical; the verdict line reads either a dominance badge or "Trade-off — your call"; entering an amount adds the "Best earn" section; crypto.com appears under "Not covering this" as "Unknown — unverified".
4. Card benefits screen: 10 cards, orange "Unverified draft" chips everywhere, crypto.com reads "Unknown — unverified".
5. A checkout under $150 at a grocery merchant shows **no** benefits section (quiet by default).
6. Reconcile and dashboard flows still behave exactly as before (no regression from the HomeView signature change).

- [ ] **Step 3: Tick all checkboxes in this plan and commit**

```bash
git add docs/plans/2026-08-16-benefits-implementation-plan.md
git commit -m "Record the benefits plan execution"
```
