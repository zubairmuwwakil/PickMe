# iOS App Implementation Plan — Phase 1 (core checkout loop)

> **For agentic workers:** Steps use checkbox (`- [ ]`) syntax for tracking. Follow TDD where the code is testable logic; UI work is verified by building and driving the simulator.

**Goal:** A SwiftUI iPhone app that detects the merchant you're standing in, recommends a card with an explanation, and records the prediction so accuracy can be measured.

**Architecture:** Thin SwiftUI + SwiftData app over the finished `CardCopilotEngine` package. The engine stays pure and untouched — the app supplies owner state and purchase context, and persists predictions. Boundaries follow the design doc: `MerchantProvider`, `CardRepository`, `MerchantKnowledgeRepository`, `RecommendationEngine`, `RecommendationExplainer`, `ObservationRecorder`.

**Tech Stack:** Swift 6.2, Xcode 26.3, iOS 18.0 deployment target, SwiftUI, SwiftData, MapKit, CoreLocation, App Intents.

**Spec:** `docs/plans/2026-08-15-canadian-card-copilot-mvp-design.md`

## Global Constraints

- **Engine is a local package dependency, never copied.** All scoring stays in `Engine/`; the app never reimplements rules.
- **Deployment target iOS 18.0.** Broad enough for a future public release; the machine's SDK is iOS 26.2.
- **No project-file churn:** the `.xcodeproj` uses `PBXFileSystemSynchronizedRootGroup`, so adding Swift files requires no project edits.
- **Predictions are immutable.** Corrections create observations; they never rewrite what the app said at the time (design §6).
- **Location is one-time only.** `requestLocation()`, never `startUpdatingLocation`; off by default with express consent (Quebec Law 25, decision-table regulatory row).
- **Manual merchant search is mandatory**, not optional — Apple requires a manual alternative when location is declined (guideline 5.1.1).
- **No network calls.** Local-only; MapKit POI search is the sole external dependency.
- `swift test` in `Engine/` must stay green throughout.

## File Structure

```
App/
  CardCopilot.xcodeproj/            hand-written, synchronized groups
  CardCopilot/
    CardCopilotApp.swift            @main, SwiftData container
    Persistence/
      Models.swift                  SwiftData: StoredPrediction, StoredObservation, StoredMerchant
      OwnerStateStore.swift         loads seed owner state, persists edits
    Services/
      LocationProvider.swift        one-time CoreLocation fix
      MerchantProvider.swift        MapKit POI search + manual search (protocol + live impl)
      CategoryMapper.swift          MapKit POI category -> engine category + confidence
      RecommendationService.swift   glue: purchase context -> engine -> stored prediction
    Views/
      HomeView.swift                instant repeats + "somewhere new"
      MerchantConfirmView.swift     ranked nearby list, manual search fallback
      RecommendationView.swift      winner, $, why, runner-up, valuation line, warnings
      AmountCaptureView.swift       preset chips
    Resources/
      Info.plist                    NSLocationWhenInUseUsageDescription
```

## Tasks

### Task 1: Project skeleton that builds

**Files:** Create `App/CardCopilot.xcodeproj/project.pbxproj`, `App/CardCopilot/CardCopilotApp.swift`, `App/CardCopilot/Resources/Info.plist`

- [ ] Hand-write `project.pbxproj` with one app target, a `PBXFileSystemSynchronizedRootGroup` for `CardCopilot/`, and an `XCLocalSwiftPackageReference` to `../Engine`
- [ ] Minimal `@main` App rendering a view that loads the seed catalogue and prints the card count — proves the engine links
- [ ] Verify: `xcodebuild -project App/CardCopilot.xcodeproj -scheme CardCopilot -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build` succeeds
- [x] Commit

### Task 2: SwiftData persistence layer

**Files:** Create `Persistence/Models.swift`, `Persistence/OwnerStateStore.swift`

- [ ] `StoredPrediction`: merchant name/id, predicted category, confidence source, winner cardId, winner value, runner-up, amount, timestamp, valuation used — all immutable after write
- [ ] `StoredObservation`: links to a prediction, records card used, observed category/multiplier, miss class, notes, confirmation date
- [ ] `StoredMerchant`: brand, MapKit id, coordinates, confirmed category, observation count, last seen
- [ ] Miss-class enum matching design §6 (wrongCategory, capExceeded, staleRule, processorWeirdness, networkNotAccepted)
- [ ] Test: round-trip each model through an in-memory `ModelContainer`
- [x] Commit

### Task 3: Category mapping with honest confidence

**Files:** Create `Services/CategoryMapper.swift`, test file

- [x] Map `MKPointOfInterestCategory` → engine category, returning `(category, confidence, source)` per the design's prediction ladder
- [x] High-confidence brand priors only (CT-family, Costco, owner-known recurring) — no speculative 50-chain table
- [x] Ambiguous POIs (gasStation, generic store) return low confidence and a candidate list, feeding the fork view
- [x] Test: `foodMarket` → grocery high; `gasStation` → ambiguous with both pump and kiosk candidates; unknown → fallback
- [x] Commit

### Task 4: Merchant detection

**Files:** Create `Services/LocationProvider.swift`, `Services/MerchantProvider.swift`

- [x] `MerchantProviding` protocol so the engine-facing code never depends on MapKit directly
- [x] One-time location fix; graceful denial path straight to manual search
- [x] `MKLocalPointsOfInterestRequest` within a small radius, ranked by distance
- [x] Manual text search fallback via `MKLocalSearch`
- [x] Test with a stub provider; live provider verified in the simulator with a simulated location
- [x] Commit

### Task 5: Recommendation flow end to end

**Files:** Create `Services/RecommendationService.swift`, `Views/MerchantConfirmView.swift`, `Views/RecommendationView.swift`, `Views/AmountCaptureView.swift`

- [x] Assemble `PurchaseContext` from confirmed merchant + mapped category + captured amount
- [x] Call engine, render `Explanation` — headline, why, runner-up, **valuation line**, warnings
- [x] Fork view when category confidence is low: show both branches with their winners
- [x] Amount capture: preset chips ($10/$25/$50/$100/custom), skippable
- [x] Persist the prediction immutably on display
- [x] Verify in simulator: launch → confirm merchant → see recommendation (nearby, search, amount, single, and fork paths all exercised live)
- [x] Commit

### Task 6: Home screen with instant repeats

**Files:** Create `Views/HomeView.swift`

- [x] Confirmed merchants sorted by proximity; one tap → recommendation with no location fix
- [x] "Somewhere new" button runs the full detection flow
- [x] Value-recovered counter in the header
- [x] Verify in simulator
- [x] Commit

### Task 7: Weekly reconcile ritual + experiment dashboard

**Files:** Extend `Store/Sources/CardCopilotStore/{Models,PredictionLog,CheckoutService,CategoryMapper}.swift`; create `Views/ReconcileView.swift`, `Views/DashboardView.swift`; extend `Views/HomeView.swift`, `Views/CheckoutFlowView.swift`

Schema evolution for arithmetic verification:

- [x] `StoredPrediction.predictedRewardUnits` + `predictedRewardUnitKind`, written at prediction time from the winning card's program — metric #2 was unmeasurable without them
- [x] `StoredObservation.observedRewardUnits`, entered at reconcile from the statement
- [x] Both optional and never inferred: rows predating the fields are excluded from arithmetic metrics rather than guessed
- [x] Test: predictions still immutable under confirmation; reward units round-trip; a statement with no reward line records as unknown, not zero

Metrics:

- [x] Eligibility rule as both a doc comment on `StoredPrediction.arithmeticVerdict` and a test per clause — a row enters the arithmetic check only when the observed category equals the predicted one, the amount was real, the card tapped is the card recommended, and both reward-unit figures exist
- [x] `arithmeticCorrectRate: Double?` (nil without evidence), `meetsArithmeticBar: Bool?` (rate == 1.0)
- [x] Unit-aware tolerance: 1.0 for points (46.47 posts as 46), one cent for cash back and CT Money, whose units are dollars. Verified by mutation — a flat 1.0 tolerance makes a $2.00-predicted / $1.50-posted row read as correct, and four of ten catalogue cards pay in dollars, including the default
- [x] Comparison uses the prediction's own snapshot; today's engine is never re-run against an old row

Truth graph:

- [x] `confirm` promotes the merchant named by the prediction's `merchantIdentifier` at terminal level, never brand-wide
- [x] `confirmationCount` is a streak, not a total: a terminal that re-codes resets to 1, so `.repeatedTerminal` keeps meaning "this same result repeated here"
- [x] `CheckoutService.recommend` consults the terminal before the mapper — ladder rungs 1–2 beat brand priors and POI guesses, with a single candidate and no fork
- [x] Test: confirmed merchant skips the fork; a different Walmart id still forks; recommend → confirm → recommend the same id yields one outcome sourced `ownerConfirmedTerminal`
- [x] `observableCategories(in:)` derives the reconcile picker's vocabulary from the catalogue, so no category can be predictable but not correctable

UI:

- [x] `ReconcileView`: the `awaitingConfirmation()` queue as a list, one sheet per row — card used, coded-as, rewards posted, miss class (auto-preselects `wrongCategory` when the category changed), note
- [x] The entry field names the unit but never the predicted figure — showing "we expected 500" beside the box would anchor the number copied off the statement, and metric #2 only means something while the two are independent
- [x] `DashboardView`: progress to 30, both metrics against their bars, miss breakdown, value recovered, with "Not enough evidence yet" instead of 0% — and, when confirmations exist but none are checkable, a line saying why
- [x] `HomeView`: "N to reconcile" row and a dashboard entry point
- [x] Verify in simulator: searched Walmart at $100 forked → reconciled as grocery / Cobalt / 500 points → dashboard read 1 of 30, category 100%, arithmetic 100%, $3.00 recovered → the same Walmart answered instantly with a single Cobalt verdict and no fork. SwiftData migrated the new optional fields on the existing container; no reinstall was needed
- [x] Commit

**Known limitation (deliberate, not deferred by accident):** cap progress is not persisted back into owner state. The seed's `capProgress` figures are static for the duration of the experiment, so a purchase that pushes the Cobalt monthly cap over its limit will still be scored against the seeded usage. This is exactly the failure metric #2 is built to expose: such a row keeps its correct category, enters the arithmetic check, and fails it — which is why eligibility keys on the observed category rather than on the absence of a miss class. Reconcile it with `capExceeded` and the dashboard will show both the miss and the arithmetic failure.

## Follow-on plans (not this phase)

Cap-progress persistence into owner state · Wallet Report Card · Action Button App Intent · export + rule freshness UI · onboarding and card selection (required before any public release).
