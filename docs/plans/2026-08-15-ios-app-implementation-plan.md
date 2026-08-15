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

## Follow-on plans (not this phase)

Weekly reconcile ritual + metrics dashboard · Wallet Report Card · Action Button App Intent · export + rule freshness UI · onboarding and card selection (required before any public release).
