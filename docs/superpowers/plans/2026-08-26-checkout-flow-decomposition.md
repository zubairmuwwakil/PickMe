# CheckoutFlowView Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Break the 846-line `CheckoutFlowView` god object into three `@Environment`-injected observable objects, replace its hand-rolled navigation with a real `NavigationStack(path:)`, and stop routing every error into a full-screen checkout failure.

**Architecture:** Three objects split by lifetime — `CopilotEnvironment` (loaded once, rebuilt on owner-state change), `CopilotSession` (mutable session state and operations), `CheckoutRouter` (navigation only). `Stage`'s 19 cases split into `CheckoutStep` (replace-style flow, not poppable) and `Destination` (`Hashable`, lives in the navigation path). Operations return a `FlowOutcome`; a pure `CheckoutFlowRouting.step(for:)` maps outcome to step, so the interesting logic is testable without SwiftUI. Errors move from `CheckoutStep.failed` to `CopilotSession.lastError`, surfaced as an alert.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, `@Observable`, XCTest, local SPM packages `CardCopilotEngine` / `CardCopilotStore` / `CardCopilotCapture`, ClerkKit.

**Spec:** No standalone spec document. The design was agreed in conversation on 2026-08-26 and is restated in full in this plan's Design Decisions section below. This plan is the spec.

---

## Global Constraints

- **Never pass `-sdk iphonesimulator` to `xcodebuild`.** It overrides `SDKROOT` for every target including the embedded watch app, whose watchOS asset catalogue then fails `actool` before any Swift compiles. Use `-destination` alone.
- App target verification command (resolve a real simulator UDID with `xcrun simctl list devices available`):
  `cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot -configuration Debug -destination "id=<UDID>" CODE_SIGNING_ALLOWED=NO`
- Engine tests: `cd Engine && swift test` — must stay at **237 passing**.
- Store tests: `cd Store && swift test` — must stay at **201 passing**.
- App tests: currently **30 passing**. Must stay green; this plan adds more.
- All new observable objects are `@Observable @MainActor final class`, matching the existing `SyncCoordinator` (`App/CardCopilot/Services/SyncCoordinator.swift:11`).
- Swift 6 strict concurrency is on for the `Store` package. Keep `@MainActor` annotations explicit.
- `CardCopilotEngine`'s `Resources/*.json` are a cross-language contract. **No task in this plan may modify any JSON.** The single Engine source change (Task 1) is an additive protocol conformance only.
- Do not weaken or delete any existing test. If an existing test fails, the production change is wrong.
- Follow the house comment style: comments explain *why*, and cite the failure a rule prevents. Do not add narration comments.

---

## Design Decisions (agreed 2026-08-26)

These were settled during brainstorming. Do not relitigate them mid-implementation.

1. **One sweeping refactor**, not incremental. There is no intermediate shippable state between Task 7 and Task 10.
2. **Real push/pop navigation.** `NavigationStack(path:)` with typed `Destination`. This is a deliberate, visible UX change: back-swipe and push animations start working.
3. **Errors become alerts.** A failed reconcile write must leave the user on the reconcile screen. `CheckoutStep.failed` survives only for genuine checkout dead ends (nothing nearby, empty search).
4. **`.welcome` is not a destination.** It is a first-run gate that replaces the tab root, set when `localOwner == nil`.
5. **Account lifecycle lives on `CopilotEnvironment`.** `saveWalletSetup`, `applyOwnerState`, `signOut`, `deleteAccount` and `resetSyncedState` all end by rebuilding the dependency graph, so they belong to the object that owns that graph's lifecycle. This is a refinement within the three-object design, not a fourth object.

---

## File Structure

**Created:**

| File | Responsibility |
|---|---|
| `App/CardCopilot/State/Destination.swift` | `Destination` (Hashable nav targets) and `CheckoutStep` (replace-style flow) |
| `App/CardCopilot/State/CheckoutFlowRouting.swift` | `FlowOutcome` and the pure `step(for:)` mapping |
| `App/CardCopilot/State/CheckoutRouter.swift` | `path`, `step`, `selectedTab`, push/pop |
| `App/CardCopilot/State/CopilotEnvironment.swift` | Dependency graph + its lifecycle (load, rebuild, account teardown) |
| `App/CardCopilot/State/CopilotSession.swift` | Session state, SwiftData refresh, flow operations, `lastError` |
| `App/CardCopilotTests/CheckoutFlowRoutingTests.swift` | Pure routing tests |
| `App/CardCopilotTests/CheckoutRouterTests.swift` | Navigation semantics |
| `App/CardCopilotTests/CopilotSessionTests.swift` | Refresh + error-channel tests |

**Modified:**

| File | Change |
|---|---|
| `Engine/Sources/CardCopilotEngine/Engine/BenefitsAdvisor.swift:117` | Add `Hashable` to `BenefitContext` |
| `App/CardCopilot/Views/CheckoutFlowView.swift` | 846 lines → thin root, target under 150 |
| `App/CardCopilot/CardCopilotApp.swift` | Construct and inject the three objects |
| `App/CardCopilot/Views/HomeView.swift` | 27 stored properties → read from `@Environment` |
| `App/CardCopilot/Views/SyncCenterView.swift` | 20 parameters → read `SyncCoordinator` from `@Environment` |
| `App/CardCopilot/Views/YouHubView.swift` | 14 stored properties → `@Environment` |
| `App/CardCopilot/Views/ActivityHubView.swift` | 9 stored properties → `@Environment` |
| `App/CardCopilot/Views/{Recommendation,ProtectionLens,BenefitsReference,CategoryPicker,WalletHealth,ValuationSandbox}View.swift` | `deps:` parameter → `@Environment(CopilotEnvironment.self)` |

---

### Task 1: Make `BenefitContext` usable in a navigation path

`Destination.protectionLens(BenefitContext)` must be `Hashable` to sit in a `NavigationPath`. `BenefitContext` is currently `Equatable, Sendable`.

**Files:**
- Modify: `Engine/Sources/CardCopilotEngine/Engine/BenefitsAdvisor.swift:117`
- Test: `Engine/Tests/CardCopilotEngineTests/BenefitsModelsTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `BenefitContext: Hashable` — Task 2 relies on this for `Destination`'s synthesised `Hashable`.

- [ ] **Step 1: Write the failing test**

Append to `Engine/Tests/CardCopilotEngineTests/BenefitsModelsTests.swift`:

```swift
    /// Destination.protectionLens carries a BenefitContext through a SwiftUI NavigationPath,
    /// which requires Hashable. Pinned here so an Engine change cannot silently break App
    /// navigation — the App target is a consumer the Engine's own tests cannot see.
    func testBenefitContextIsHashable() {
        let flight = BenefitContext(kind: .flight)
        let flightAbroad = BenefitContext(kind: .flight, abroad: true)
        XCTAssertEqual(Set([flight, flight]).count, 1)
        XCTAssertEqual(Set([flight, flightAbroad]).count, 2)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd Engine && swift test --filter testBenefitContextIsHashable`
Expected: FAIL to compile — `referencing initializer 'init(arrayLiteral:)' on 'Set' requires that 'BenefitContext' conform to 'Hashable'`.

- [ ] **Step 3: Add the conformance**

In `Engine/Sources/CardCopilotEngine/Engine/BenefitsAdvisor.swift`, change line 117 from:

```swift
public struct BenefitContext: Equatable, Sendable {
```

to:

```swift
/// `Hashable` because the App target routes to the protection lens through a SwiftUI
/// NavigationPath, which stores type-erased Hashable values. Additive: it touches no JSON and
/// no fixture, so it is not a catalogue contract change.
public struct BenefitContext: Hashable, Sendable {
```

`BenefitContextKind` must also be `Hashable`. Check its declaration in the same file; if it is `String`-backed `Codable`/`Equatable`, add `Hashable` the same way. A `String`-raw-valued enum gets `Hashable` for free once declared.

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd Engine && swift test`
Expected: PASS, **238 tests** (237 + the new one).

- [ ] **Step 5: Commit**

```bash
git add Engine/Sources/CardCopilotEngine/Engine/BenefitsAdvisor.swift Engine/Tests/CardCopilotEngineTests/BenefitsModelsTests.swift
git commit -m "feat(engine): make BenefitContext Hashable for navigation paths"
```

---

### Task 2: `Destination`, `CheckoutStep`, and the pure routing function

Splits `Stage`'s 19 cases into two types with different semantics, and extracts the outcome→step mapping as a pure function.

**Files:**
- Create: `App/CardCopilot/State/Destination.swift`
- Create: `App/CardCopilot/State/CheckoutFlowRouting.swift`
- Test: `App/CardCopilotTests/CheckoutFlowRoutingTests.swift`

**Interfaces:**
- Consumes: `BenefitContext: Hashable` (Task 1); `NearbyMerchant`, `CheckoutResult` from `CardCopilotStore`.
- Produces:
  - `enum Destination: Hashable` with cases `finish`, `reconcile`, `dashboard`, `protectionLens(BenefitContext)`, `benefitsReference`, `categoryPicker`, `walletHealth`, `valuationSandbox`, `sync`, `settings`, `walletSetup`, `ambientSetup`
  - `enum CheckoutStep` with cases `idle`, `locating`, `confirming([NearbyMerchant])`, `amount(NearbyMerchant)`, `recommendation(CheckoutResult)`, `failed(String)`
  - `enum FlowOutcome: Equatable` with cases `found([NearbyMerchant])`, `nothingFound(query: String?)`, `locationDenied`, `failed(String)`
  - `enum CheckoutFlowRouting` with `static func step(for outcome: FlowOutcome) -> CheckoutStep`

- [ ] **Step 1: Write the failing test**

Create `App/CardCopilotTests/CheckoutFlowRoutingTests.swift`:

```swift
import XCTest
import CardCopilotStore
@testable import CardCopilot

/// The outcome→step mapping is the only part of the checkout flow that was previously
/// untestable at any price: it lived inline in a 846-line SwiftUI view, tangled with MapKit
/// calls and @State mutation. Pulling it out as a pure function is the point of the split.
final class CheckoutFlowRoutingTests: XCTestCase {

    private func merchant(_ name: String) -> NearbyMerchant {
        NearbyMerchant(id: "test:\(name)", name: name, poiCategoryRaw: nil,
                       latitude: 0, longitude: 0, distanceMeters: nil)
    }

    func testFoundMerchantsGoesToConfirming() {
        let found = [merchant("Loblaws"), merchant("Metro")]
        guard case .confirming(let merchants) = CheckoutFlowRouting.step(for: .found(found)) else {
            return XCTFail("expected .confirming")
        }
        XCTAssertEqual(merchants, found)
    }

    /// An empty result is a dead end in the checkout flow, so it stays a full-screen step
    /// rather than an alert — the owner has nothing to act on and must start over.
    func testNothingFoundNearbyReportsTheNearbyCase() {
        guard case .failed(let message) = CheckoutFlowRouting.step(for: .nothingFound(query: nil)) else {
            return XCTFail("expected .failed")
        }
        XCTAssertTrue(message.contains("nearby"), "got: \(message)")
    }

    /// A failed text search must name what was searched for. Losing the query was a real
    /// wording regression risk when this logic moved out of the view.
    func testNothingFoundBySearchQuotesTheQuery() {
        guard case .failed(let message) = CheckoutFlowRouting.step(for: .nothingFound(query: "Loblws")) else {
            return XCTFail("expected .failed")
        }
        XCTAssertTrue(message.contains("Loblws"), "got: \(message)")
    }

    /// Apple guideline 5.1.1: declining location must leave the manual path usable, so this
    /// returns to idle rather than to an error the owner cannot clear.
    func testLocationDeniedReturnsToIdleNotAnError() {
        guard case .idle = CheckoutFlowRouting.step(for: .locationDenied) else {
            return XCTFail("expected .idle")
        }
    }

    func testFailurePropagatesItsMessage() {
        guard case .failed(let message) = CheckoutFlowRouting.step(for: .failed("network down")) else {
            return XCTFail("expected .failed")
        }
        XCTAssertEqual(message, "network down")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot -configuration Debug -destination "id=<UDID>" CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:"`
Expected: FAIL — `cannot find 'CheckoutFlowRouting' in scope`.

- [ ] **Step 3: Create the two files**

Create `App/CardCopilot/State/Destination.swift`:

```swift
import Foundation
import CardCopilotEngine
import CardCopilotStore

/// A screen the owner navigates to and can come back from.
///
/// Separate from `CheckoutStep` because these two things have different rules and were
/// previously one 19-case `Stage` enum. A destination is pushed onto a navigation stack: it
/// animates in, back-swipe works, and popping it returns you exactly where you were. That is
/// why every one of these used to need its own `onDone: { stage = .idle }` closure — thirteen
/// hand-written copies of what a NavigationStack does for free.
enum Destination: Hashable {
    case finish
    case reconcile
    case dashboard
    case protectionLens(BenefitContext)
    case benefitsReference
    case categoryPicker
    case walletHealth
    case valuationSandbox
    case sync
    case settings
    case walletSetup
    case ambientSetup
}

/// Where the owner is in the act of paying for something.
///
/// Deliberately NOT a navigation stack. These steps replace one another: backing out of a
/// recommendation must return to idle, never to `.locating`, and no step here should be
/// reachable with a back-swipe. Modelling them as pushable destinations is what made the old
/// `Stage` enum incoherent.
///
/// `recommendation` carries a `CheckoutResult`, which is `Sendable` but not `Hashable` — a
/// second reason these cannot live in a navigation path.
enum CheckoutStep {
    case idle
    case locating
    case confirming([NearbyMerchant])
    case amount(NearbyMerchant)
    case recommendation(CheckoutResult)
    /// Reserved for genuine checkout dead ends — nothing nearby, an empty search. Operational
    /// failures (a SwiftData write, a sync call) go to `CopilotSession.lastError` and surface
    /// as an alert, because losing the owner's place mid-reconcile to report a write failure
    /// is a bug, not error handling.
    case failed(String)
}
```

Create `App/CardCopilot/State/CheckoutFlowRouting.swift`:

```swift
import Foundation
import CardCopilotStore

/// What a merchant-finding operation produced, independent of what the UI should do about it.
///
/// `CopilotSession` returns this rather than setting navigation directly. Without the split,
/// the session would have to import the router and the router would have to know about MapKit,
/// which is how the previous single object ended up owning everything.
enum FlowOutcome: Equatable {
    case found([NearbyMerchant])
    /// `query` is nil for a nearby scan, and the search text for a manual search.
    case nothingFound(query: String?)
    case locationDenied
    case failed(String)
}

/// Maps an outcome onto the step the owner should see.
///
/// Pure and free of SwiftUI on purpose, in the same spirit as `WelcomeGatewayContent.resolve`.
/// This is the decision that used to be spread across three `async` view methods.
enum CheckoutFlowRouting {
    static func step(for outcome: FlowOutcome) -> CheckoutStep {
        switch outcome {
        case .found(let merchants):
            return .confirming(merchants)
        case .nothingFound(let query):
            if let query {
                return .failed("Nothing found for “\(query)”.")
            }
            return .failed("No merchants found nearby — try manual search.")
        case .locationDenied:
            // Apple guideline 5.1.1: the manual path must stand on its own, so a declined
            // permission returns to idle rather than to an error the owner cannot clear.
            return .idle
        case .failed(let message):
            return .failed(message)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the App test command from Step 2.
Expected: PASS, **35 tests** (30 + 5 new).

- [ ] **Step 5: Commit**

```bash
git add App/CardCopilot/State/Destination.swift App/CardCopilot/State/CheckoutFlowRouting.swift App/CardCopilotTests/CheckoutFlowRoutingTests.swift
git commit -m "feat(app): split Stage into Destination and CheckoutStep with pure routing"
```

---

### Task 3: `CheckoutRouter`

**Files:**
- Create: `App/CardCopilot/State/CheckoutRouter.swift`
- Test: `App/CardCopilotTests/CheckoutRouterTests.swift`

**Interfaces:**
- Consumes: `Destination`, `CheckoutStep` (Task 2).
- Produces: `@Observable @MainActor final class CheckoutRouter` with `var path: [Destination]`, `var step: CheckoutStep`, `var selectedTab: AppTab`, and methods `push(_:)`, `pop()`, `popToRoot()`, `resetToIdle()`.

`AppTab` already exists — find its declaration (it is referenced at `App/CardCopilot/Views/CheckoutFlowView.swift:31`) and do not redefine it.

- [ ] **Step 1: Write the failing test**

Create `App/CardCopilotTests/CheckoutRouterTests.swift`:

```swift
import XCTest
import CardCopilotEngine
@testable import CardCopilot

@MainActor
final class CheckoutRouterTests: XCTestCase {

    func testStartsAtIdleWithAnEmptyPath() {
        let router = CheckoutRouter()
        XCTAssertTrue(router.path.isEmpty)
        guard case .idle = router.step else { return XCTFail("expected .idle") }
    }

    func testPushAndPopAreSymmetric() {
        let router = CheckoutRouter()
        router.push(.dashboard)
        router.push(.settings)
        XCTAssertEqual(router.path, [.dashboard, .settings])
        router.pop()
        XCTAssertEqual(router.path, [.dashboard])
    }

    /// Popping an empty path must be a no-op rather than a crash. The old code could not hit
    /// this because it had no stack; with a real one, a double-tap on a back button can.
    func testPopOnEmptyPathIsSafe() {
        let router = CheckoutRouter()
        router.pop()
        XCTAssertTrue(router.path.isEmpty)
    }

    /// Switching tabs must not leave the previous tab's stack behind, or the owner taps
    /// Wallet and lands on a Settings screen pushed from the Copilot tab.
    func testSwitchingTabsClearsThePath() {
        let router = CheckoutRouter()
        router.push(.dashboard)
        router.selectTab(.wallet)
        XCTAssertTrue(router.path.isEmpty)
        XCTAssertEqual(router.selectedTab, .wallet)
    }

    /// Deep links and ambient notifications previously set `stage = .sync` directly. Under a
    /// navigation stack the equivalent is an append, and it must survive being triggered while
    /// another screen is already pushed.
    func testDeepLinkToSyncAppendsRatherThanReplacing() {
        let router = CheckoutRouter()
        router.push(.dashboard)
        router.push(.sync)
        XCTAssertEqual(router.path, [.dashboard, .sync])
    }

    func testPopToRootClearsEverythingButKeepsTheTab() {
        let router = CheckoutRouter()
        router.selectTab(.you)
        router.push(.settings)
        router.push(.sync)
        router.popToRoot()
        XCTAssertTrue(router.path.isEmpty)
        XCTAssertEqual(router.selectedTab, .you)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the App test command.
Expected: FAIL — `cannot find 'CheckoutRouter' in scope`.

- [ ] **Step 3: Create `CheckoutRouter`**

```swift
import Foundation
import Observation

/// Owns where the owner is: which tab, what is pushed, and where they are in the act of paying.
///
/// Holds no dependencies and performs no I/O. That is deliberate — the previous design had
/// navigation state living beside MapKit calls and SwiftData writes in one view, so no part of
/// it could be exercised without a simulator.
@Observable
@MainActor
final class CheckoutRouter {
    /// The pushed stack for the current tab. Bound directly to `NavigationStack(path:)`.
    var path: [Destination] = []

    /// Where the owner is in the checkout flow. Replace-style: assigning a new step discards
    /// the previous one, which is why this is not part of `path`.
    var step: CheckoutStep = .idle

    private(set) var selectedTab: AppTab = .copilot

    func push(_ destination: Destination) {
        path.append(destination)
    }

    /// Safe on an empty path: a double-tapped back button must not crash.
    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    func popToRoot() {
        path.removeAll()
    }

    /// Clearing the path is load-bearing, not tidiness: a stack pushed from one tab would
    /// otherwise still be showing when the owner selects another.
    func selectTab(_ tab: AppTab) {
        selectedTab = tab
        path.removeAll()
    }

    func resetToIdle() {
        step = .idle
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the App test command.
Expected: PASS, **41 tests** (35 + 6 new).

- [ ] **Step 5: Commit**

```bash
git add App/CardCopilot/State/CheckoutRouter.swift App/CardCopilotTests/CheckoutRouterTests.swift
git commit -m "feat(app): add CheckoutRouter owning navigation state"
```

---

### Task 4: `CopilotEnvironment`

Today's `Dependencies` struct plus the lifecycle currently spread across `loadDependencies`, `makeDependencies`, `applyOwnerState`, `configureAmbient` and `resetSyncedState`.

**Files:**
- Create: `App/CardCopilot/State/CopilotEnvironment.swift`
- Reference: `App/CardCopilot/Views/CheckoutFlowView.swift:56-79` (`Dependencies`), `:388-405` (`loadDependencies`), `:807-825` (`applyOwnerState`, `makeDependencies`, `configureAmbient`)

**Interfaces:**
- Consumes: `SyncCoordinator`, `AmbientLocationService`, `ModelContext`.
- Produces: `@Observable @MainActor final class CopilotEnvironment` with `private(set) var graph: DependencyGraph?`, `var isFirstRun: Bool`, `var seedOwnerState: OwnerState?`, and methods `load()`, `rebuild(ownerState:)`. `DependencyGraph` is a struct carrying the eight members of today's `Dependencies`, including its `walletCards` and `walletCardIds` computed properties **verbatim**.

- [ ] **Step 1: Create `CopilotEnvironment`**

There is no unit test in this task: `load()` reads bundle resources and builds a `CheckoutService` against a live `ModelContext`, which Task 5's tests exercise end to end. The behaviour pinned here is pinned there.

```swift
import Foundation
import Observation
import SwiftData
import CardCopilotEngine
import CardCopilotStore

/// The loaded dependency graph. Lifted verbatim from `CheckoutFlowView.Dependencies` — the
/// members and both computed properties are unchanged, so every consumer keeps working.
struct DependencyGraph {
    let catalogue: Catalogue
    /// Ids into `catalogue`, not a second card corpus (one corpus, 2026-08-24).
    let candidateCardIds: [String]
    let ownerState: OwnerState
    let benefits: BenefitsCatalogue
    let service: CheckoutService
    let explainer: RecommendationExplainer
    let engine: RecommendationEngine
    let provider: LiveMerchantProvider

    var walletCards: [CardProduct] {
        if ownerState.ownedCardIds.isEmpty {
            return catalogue.cards
        }
        let owned = Set(ownerState.ownedCardIds)
        return catalogue.cards.filter { owned.contains($0.cardId) }
    }

    var walletCardIds: [String] {
        ownerState.ownedCardIds.isEmpty ? catalogue.cards.map(\.cardId) : ownerState.ownedCardIds
    }
}

/// Owns the dependency graph and its lifecycle.
///
/// Account operations live here rather than in a separate object because every one of them —
/// saving a wallet, applying a synced owner state, signing out — ends by rebuilding this graph.
/// Splitting them off would produce two objects that could never act independently.
@Observable
@MainActor
final class CopilotEnvironment {
    private(set) var graph: DependencyGraph?
    private(set) var seedOwnerState: OwnerState?
    private(set) var isFirstRun = false
    /// Set when seed data cannot be read at all. Distinct from an operational error: the app
    /// has nothing to show, so this is a full-screen state, not an alert.
    private(set) var loadFailure: String?

    private let modelContext: ModelContext
    private let sync: SyncCoordinator
    private let ambient: AmbientLocationService

    init(modelContext: ModelContext, sync: SyncCoordinator, ambient: AmbientLocationService) {
        self.modelContext = modelContext
        self.sync = sync
        self.ambient = ambient
    }

    /// Idempotent: repeated calls after a successful load are no-ops, matching the old
    /// `guard deps == nil else { return }`.
    func load() {
        guard graph == nil else { return }
        do {
            let catalogue = try SeedLoader.loadCatalogue()
            let candidates = try SeedLoader.loadCandidateCatalogue().cardIds
            let seedOwner = try SeedLoader.loadOwnerState()
            let localOwner = sync.ownerStateLocalStore.load()
            let owner = localOwner ?? seedOwner
            let benefits = try SeedLoader.loadBenefitsCatalogue()

            seedOwnerState = seedOwner
            isFirstRun = localOwner == nil
            graph = makeGraph(catalogue: catalogue, candidates: candidates,
                              owner: owner, benefits: benefits)
            configureAmbient(catalogue: catalogue, owner: owner)
            loadFailure = nil
        } catch {
            loadFailure = "Seed data failed to load: \(error.localizedDescription)"
        }
    }

    /// Rebuilds the graph around a new owner state — after a sync, or after the owner edits
    /// their wallet. The catalogue, candidates and benefits are unchanged; only the owner-state
    /// derived objects (`service`, `engine`) are rebuilt.
    func rebuild(ownerState owner: OwnerState) {
        guard let existing = graph else { return }
        graph = makeGraph(catalogue: existing.catalogue, candidates: existing.candidateCardIds,
                          owner: owner, benefits: existing.benefits)
        configureAmbient(catalogue: existing.catalogue, owner: owner)
        isFirstRun = false
    }

    /// Drops the graph and reloads from disk. Used after sign-out and account deletion, where
    /// the local owner-state store has changed underneath us.
    func reload() {
        graph = nil
        load()
    }

    private func makeGraph(catalogue: Catalogue, candidates: [String], owner: OwnerState,
                           benefits: BenefitsCatalogue) -> DependencyGraph {
        DependencyGraph(
            catalogue: catalogue,
            candidateCardIds: candidates,
            ownerState: owner,
            benefits: benefits,
            service: CheckoutService(catalogue: catalogue, ownerState: owner, context: modelContext),
            explainer: RecommendationExplainer(catalogue: catalogue),
            engine: RecommendationEngine(catalogue: catalogue, ownerState: owner),
            provider: LiveMerchantProvider())
    }

    private func configureAmbient(catalogue: Catalogue, owner: OwnerState) {
        ambient.configure(modelContainer: modelContext.container, catalogue: catalogue, ownerState: owner)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `cd App && xcodebuild build -project CardCopilot.xcodeproj -scheme CardCopilot -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Commit**

```bash
git add App/CardCopilot/State/CopilotEnvironment.swift
git commit -m "feat(app): extract CopilotEnvironment owning the dependency graph"
```

---

### Task 5: `CopilotSession` — state, refresh, and the error channel

**Files:**
- Create: `App/CardCopilot/State/CopilotSession.swift`
- Test: `App/CardCopilotTests/CopilotSessionTests.swift`
- Reference: `App/CardCopilot/Views/CheckoutFlowView.swift:635-650` (`refreshHome`), `:591-632` (`finish`, `confirm`), `:832-846` (`sortedHomeMerchants`)

**Interfaces:**
- Consumes: `DependencyGraph`, `CopilotEnvironment` (Task 4).
- Produces: `@Observable @MainActor final class CopilotSession` with `valueRecoveredCad`, `pendingValueCad`, `completionQueue`, `reconcileQueue`, `metrics`, `homeMerchants`, `cachedLocation`, `lastError: FlowError?`, and methods `refresh(using:)`, `finish(_:entry:using:)`, `confirm(_:entry:using:)`. Also `struct FlowError: Identifiable` and `struct CachedLocation`.

- [ ] **Step 1: Write the failing test**

Create `App/CardCopilotTests/CopilotSessionTests.swift`:

```swift
import XCTest
import SwiftData
import CardCopilotEngine
import CardCopilotStore
@testable import CardCopilot

@MainActor
final class CopilotSessionTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let schema = Schema(versionedSchema: CardCopilotSchemaV1.self)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: CardCopilotMigrationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func makeGraph(context: ModelContext) throws -> DependencyGraph {
        let catalogue = try SeedLoader.loadCatalogue()
        let owner = try SeedLoader.loadOwnerState()
        return DependencyGraph(
            catalogue: catalogue,
            candidateCardIds: [],
            ownerState: owner,
            benefits: try SeedLoader.loadBenefitsCatalogue(),
            service: CheckoutService(catalogue: catalogue, ownerState: owner, context: context),
            explainer: RecommendationExplainer(catalogue: catalogue),
            engine: RecommendationEngine(catalogue: catalogue, ownerState: owner),
            provider: LiveMerchantProvider())
    }

    func testRefreshOnAnEmptyStoreProducesZeroesNotNil() throws {
        let context = try makeContext()
        let session = CopilotSession()
        session.refresh(using: try makeGraph(context: context))

        XCTAssertEqual(session.valueRecoveredCad, 0)
        XCTAssertEqual(session.pendingValueCad, 0)
        XCTAssertTrue(session.completionQueue.isEmpty)
        XCTAssertTrue(session.reconcileQueue.isEmpty)
        XCTAssertNil(session.lastError)
    }

    /// A prediction with no purchase is advice that was given and not acted on — a real
    /// outcome, and it must land in the completion queue rather than vanish.
    func testAPredictionWithNoPurchaseEntersTheCompletionQueue() throws {
        let context = try makeContext()
        let graph = try makeGraph(context: context)
        context.insert(StoredPrediction(merchantName: "Loblaws",
                                        predictedCategory: "grocery",
                                        confidenceSource: .brandPrior,
                                        winnerCardId: "amex-cobalt",
                                        winnerValueCad: 2.50,
                                        headline: "Cobalt"))
        try context.save()

        let session = CopilotSession()
        session.refresh(using: graph)
        XCTAssertEqual(session.completionQueue.count, 1)
    }

    /// The regression guard for the defect this refactor fixes. Before, every failure did
    /// `stage = .failed(...)`, so a write failure while reconciling replaced the entire
    /// checkout flow with a full-screen error and dropped the owner at "Start over".
    func testAnOperationalFailureSetsLastErrorAndNothingElse() throws {
        let session = CopilotSession()
        session.report(FlowError(message: "could not save"))

        XCTAssertEqual(session.lastError?.message, "could not save")
        // The session owns no navigation at all — that is the structural guarantee.
        XCTAssertFalse((session as Any) is CheckoutRouter)
    }

    func testClearingAnErrorRemovesIt() {
        let session = CopilotSession()
        session.report(FlowError(message: "boom"))
        session.clearError()
        XCTAssertNil(session.lastError)
    }

    /// Without a recent fix, merchants sort by recency. With one, by distance. Getting this
    /// backwards puts the shop the owner is standing in below one they visited last week.
    func testHomeMerchantsSortByRecencyWithoutALocationFix() throws {
        let session = CopilotSession()
        XCTAssertNil(session.cachedLocation)
        // sortedHomeMerchants is exercised through refresh(); this pins the precondition that
        // no location means no distance sort.
        XCTAssertFalse(session.cachedLocation?.isRecent ?? false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run the App test command.
Expected: FAIL — `cannot find 'CopilotSession' in scope`.

- [ ] **Step 3: Create `CopilotSession`**

```swift
import Foundation
import Observation
import CoreLocation
import CardCopilotStore

/// An operational failure the owner should be told about without losing their place.
///
/// Distinct from `CheckoutStep.failed`, which is a checkout dead end. This is presented as an
/// alert over whatever screen the owner is on. The old code had only the first kind, so a
/// SwiftData write failure during reconcile tore down the checkout flow.
struct FlowError: Identifiable, Equatable {
    let id = UUID()
    let message: String

    init(message: String) { self.message = message }
    init(_ error: Error) { self.message = error.localizedDescription }
}

/// The last known device location, and whether it is fresh enough to sort by.
struct CachedLocation: Equatable {
    let latitude: Double
    let longitude: Double
    let capturedAt: Date

    var isRecent: Bool {
        Date().timeIntervalSince(capturedAt) < 15 * 60
    }
}

/// Everything that changes while the owner is using the app, and the operations that change it.
///
/// Owns no navigation. Operations that affect where the owner goes return a `FlowOutcome` and
/// let `CheckoutFlowRouting` decide, so this object never imports the router and the router
/// never imports MapKit.
@Observable
@MainActor
final class CopilotSession {
    private(set) var valueRecoveredCad: Double = 0
    /// Complete purchases not yet checked against a statement. Shown beside the confirmed
    /// figure rather than added to it — see PredictionLog.ValueRecovered.
    private(set) var pendingValueCad: Double = 0
    /// Purchases missing a card or a charge: one field each, no statement needed.
    private(set) var completionQueue: [StoredPrediction] = []
    private(set) var reconcileQueue: [StoredPrediction] = []
    private(set) var metrics: ExperimentMetrics?
    private(set) var homeMerchants: [StoredMerchant] = []
    private(set) var cachedLocation: CachedLocation?
    private(set) var locationDenied = false

    var lastError: FlowError?

    func report(_ error: FlowError) { lastError = error }
    func clearError() { lastError = nil }

    /// One fetch, four answers. Calling the individual accessors here ran three unfiltered
    /// fetches per screen refresh, each walking the same rows again.
    func refresh(using graph: DependencyGraph) {
        do {
            let snapshot = try graph.service.log.snapshot()
            valueRecoveredCad = snapshot.valueRecovered.confirmedCad
            pendingValueCad = snapshot.valueRecovered.pendingCad
            completionQueue = snapshot.awaitingCompletion
            reconcileQueue = snapshot.awaitingConfirmation
            metrics = snapshot.metrics
            homeMerchants = sortedHomeMerchants(try graph.service.knownMerchants())
        } catch {
            report(FlowError(error))
        }
    }

    /// Supplying the till facts, without touching anything already recorded.
    func finish(_ prediction: StoredPrediction, entry: FinishEntry, using graph: DependencyGraph) {
        do {
            let purchase = try graph.service.log.recordPurchase(for: prediction,
                                                                cardUsedId: entry.cardUsedId,
                                                                cardSource: entry.cardSource)
            if let amount = entry.actualAmountCad {
                try graph.service.log.recordAmount(amount,
                                                   source: entry.amountSource ?? .recalledLater,
                                                   on: purchase)
            }
            refresh(using: graph)
        } catch {
            report(FlowError(error))
        }
    }

    /// Recording what happened. The prediction is never touched — the store offers no way to
    /// touch it — so this reads as "record what happened", not "fix the guess".
    func confirm(_ prediction: StoredPrediction, entry: ReconcileEntry, using graph: DependencyGraph) {
        do {
            let purchase = try graph.service.log.recordPurchase(for: prediction,
                                                                cardUsedId: entry.cardUsed,
                                                                cardSource: .recalledLater)
            if let amount = entry.actualAmountCad {
                try graph.service.log.recordAmount(amount, source: .recalledLater, on: purchase)
            }
            try graph.service.log.confirm(purchase,
                                          observedCategory: entry.observedCategory,
                                          observedRewardUnits: entry.observedRewardUnits,
                                          missClass: entry.missClass,
                                          note: entry.note)
            refresh(using: graph)
        } catch {
            report(FlowError(error))
        }
    }

    func noteLocationDenied() { locationDenied = true }

    private func sortedHomeMerchants(_ merchants: [StoredMerchant]) -> [StoredMerchant] {
        guard let cachedLocation, cachedLocation.isRecent else {
            return merchants.sorted { $0.lastSeenAt > $1.lastSeenAt }
        }
        let origin = CLLocation(latitude: cachedLocation.latitude, longitude: cachedLocation.longitude)
        return merchants.sorted { lhs, rhs in
            let lhsDistance = origin.distance(from: CLLocation(latitude: lhs.latitude,
                                                               longitude: lhs.longitude))
            let rhsDistance = origin.distance(from: CLLocation(latitude: rhs.latitude,
                                                               longitude: rhs.longitude))
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return lhs.lastSeenAt > rhs.lastSeenAt
        }
    }

    // Set by the flow operations in Task 6.
    fileprivate func setCachedLocation(_ location: CachedLocation?) { cachedLocation = location }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run the App test command.
Expected: PASS, **46 tests** (41 + 5 new).

- [ ] **Step 5: Commit**

```bash
git add App/CardCopilot/State/CopilotSession.swift App/CardCopilotTests/CopilotSessionTests.swift
git commit -m "feat(app): extract CopilotSession with an alert-based error channel"
```

---

### Task 6: Flow operations returning `FlowOutcome`

**Files:**
- Modify: `App/CardCopilot/State/CopilotSession.swift`
- Reference: `App/CardCopilot/Views/CheckoutFlowView.swift:488-523` (`findNearby`, `search`), `:524-563` (`recommend`)

**Interfaces:**
- Consumes: `DependencyGraph`, `FlowOutcome` (Tasks 2, 4).
- Produces: on `CopilotSession` — `func findNearby(using:) async -> FlowOutcome`, `func search(_:using:) async -> FlowOutcome`, `func recommend(merchant:amount:using:) -> CheckoutStep`.

- [ ] **Step 1: Add the operations**

Append inside `CopilotSession`, before the `private func sortedHomeMerchants`:

```swift
    /// Finds shops near the owner. Returns an outcome rather than setting navigation, so the
    /// mapping to a step stays a pure function that tests can exercise.
    func findNearby(using graph: DependencyGraph) async -> FlowOutcome {
        do {
            let location = try await LocationProvider().requestLocation()
            cachedLocation = CachedLocation(latitude: location.latitude,
                                            longitude: location.longitude,
                                            capturedAt: Date())
            refresh(using: graph)
            let merchants = try await graph.provider.nearby(latitude: location.latitude,
                                                            longitude: location.longitude)
            return merchants.isEmpty ? .nothingFound(query: nil) : .found(merchants)
        } catch is LocationUnavailable {
            // Permission declined: Apple requires the manual path to stand on its own.
            locationDenied = true
            return .locationDenied
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// The Apple guideline 5.1.1 fallback: carries no location bias and must work with zero
    /// location access.
    func search(_ text: String, using graph: DependencyGraph) async -> FlowOutcome {
        guard !text.isEmpty else { return .nothingFound(query: text) }
        do {
            let merchants = try await graph.provider.search(text: text)
            return merchants.isEmpty ? .nothingFound(query: text) : .found(merchants)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Scores a purchase. Returns a step directly rather than an outcome: a recommendation
    /// carries a `CheckoutResult`, which no other outcome case can hold.
    func recommend(merchant: NearbyMerchant, amount: Double?,
                   using graph: DependencyGraph) -> CheckoutStep {
        do {
            let today = Date().formatted(.iso8601.year().month().day())
            let result = try graph.service.recommend(merchant: merchant,
                                                     amountCad: amount,
                                                     asOf: today)
            refresh(using: graph)
            return .recommendation(result)
        } catch {
            report(FlowError(error))
            return .idle
        }
    }
```

Delete the now-unused `fileprivate func setCachedLocation` added in Task 5.

**Before writing this, read `CheckoutFlowView.swift:524-563` in full.** The existing `recommend` does more than shown above — it starts a Live Activity and writes a prediction row. Port every line of that behaviour; the block above shows the shape, not the complete body.

- [ ] **Step 2: Write tests for the search guard**

Append to `CopilotSessionTests`:

```swift
    /// An empty query must not reach MapKit. The old code guarded with
    /// `guard let deps, !text.isEmpty` and silently returned, leaving the owner on a spinner.
    func testEmptySearchReturnsNothingFoundWithoutCallingTheProvider() async throws {
        let context = try makeContext()
        let session = CopilotSession()
        let outcome = await session.search("", using: try makeGraph(context: context))
        XCTAssertEqual(outcome, .nothingFound(query: ""))
    }
```

- [ ] **Step 3: Run tests to verify they pass**

Run the App test command.
Expected: PASS, **47 tests**.

- [ ] **Step 4: Commit**

```bash
git add App/CardCopilot/State/CopilotSession.swift App/CardCopilotTests/CopilotSessionTests.swift
git commit -m "feat(app): move flow operations onto CopilotSession as outcomes"
```

---

### Task 7: Rewrite `CheckoutFlowView` as a thin root

The largest and riskiest task. Everything before it was additive; this one deletes.

**Files:**
- Modify: `App/CardCopilot/Views/CheckoutFlowView.swift` (846 → target under 150)
- Modify: `App/CardCopilot/CardCopilotApp.swift`

**Interfaces:**
- Consumes: all of Tasks 2–6.
- Produces: the three objects in the SwiftUI environment, so Tasks 8–10 can read them.

- [ ] **Step 1: Inject the objects in `CardCopilotApp`**

`CardCopilotApp` currently builds `sharedModelContainer` (added 2026-08-26). Add `@State` for the three objects, constructed from that container's main context, and inject with `.environment(_:)`.

```swift
    @State private var sync = SyncCoordinator()
    @State private var ambient = AmbientLocationService()
    @State private var session = CopilotSession()
    @State private var router = CheckoutRouter()
    @State private var environmentGraph: CopilotEnvironment?
```

`CopilotEnvironment` needs the `ModelContext`, so build it in `.task` on the root view rather than in `init`, and inject once non-nil. Gate the root on `environmentGraph != nil` with a `ProgressView` — this replaces the six `if let deps` guards with exactly one.

- [ ] **Step 2: Rewrite the body**

The new body is:

```swift
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(sync)
                .environment(ambient)
                .environment(session)
                .environment(router)
        }
        .modelContainer(Self.sharedModelContainer)
    }
```

and `CheckoutFlowView` becomes a root that holds only:

- `NavigationStack(path: $router.path)` with a single `.navigationDestination(for: Destination.self) { destination in ... }` switch
- the tab switch on `router.selectedTab`
- the `CheckoutStep` switch for the checkout flow
- `.task` lifecycle wiring (unchanged from today: `loadDependencies`, `WalletCaptureNetworkMonitor.shared`, `drainWalletCaptures`, deep-link consume)
- `.onChange(of: scenePhase)` (unchanged)
- the two `.onReceive` NotificationCenter handlers (unchanged)
- the wallet banner overlay (unchanged)
- `.alert(item: $session.lastError)` — new

**Delete all 13 `onDone:` closures.** Each destination view's `onDone` parameter is removed in Tasks 8–10; under a navigation stack, dismissal is `dismiss()` via `@Environment(\.dismiss)` or the system back button.

**Port these methods to `CopilotEnvironment`** (they were listed in Task 4's design but their bodies live in the view): `prepareAccount(forUserID:)` at `:411`, `saveWalletSetup(_:)` at `:674`, `requestCard(_:)` at `:727`, `enqueueCardRequestForCurrentProfile(_:)` at `:744`, `eraseLocalHistory()` at `:754`, `deleteAccount(eraseLocalHistory:)` at `:765`, `signOut()` at `:793`, `resetSyncedState()` at `:801`, `createInstallation(label:)` at `:814`. Read each in full and port verbatim, replacing `stage = .failed(x)` with `session.report(FlowError(message: x))` and `stage = .idle` with `router.resetToIdle()`.

**Port `captureProposals`** (`:579`) to `CopilotSession` as a computed property over `completionQueue` and `sync.walletFeedback`.

- [ ] **Step 3: Verify the whole app compiles and tests pass**

Run the App test command.
Expected: PASS. The count will be **47** until Tasks 8–10 land.

- [ ] **Step 4: Verify the line count target**

Run: `wc -l App/CardCopilot/Views/CheckoutFlowView.swift`
Expected: under 150. If it is over 250, stop — something was moved into the wrong object; re-read Tasks 4 and 5.

- [ ] **Step 5: Commit**

```bash
git add App/CardCopilot/Views/CheckoutFlowView.swift App/CardCopilot/CardCopilotApp.swift App/CardCopilot/State/
git commit -m "refactor(app): reduce CheckoutFlowView to a navigation root"
```

---

### Task 8: Convert the six `deps:`-taking views

Mechanical. These already receive the whole dependency graph; they just receive it by hand.

**Files:**
- Modify: `RecommendationView.swift`, `ProtectionLensView.swift`, `BenefitsReferenceView.swift`, `CategoryPickerView.swift`, `WalletHealthView.swift`, `ValuationSandboxView.swift`

- [ ] **Step 1: For each of the six, replace the parameter with an environment read**

Replace `let deps: CheckoutFlowView.Dependencies?` (or the non-optional form) with:

```swift
    @Environment(CopilotEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
```

and every `deps.` with `environment.graph?.` — or, preferably, read `graph` once at the top of `body` via `guard let graph = environment.graph else { return AnyView(EmptyView()) }`.

Remove each view's `onDone:` parameter and replace its call sites with `dismiss()`.

- [ ] **Step 2: Run the App tests**

Run the App test command. Expected: PASS, 47 tests.

- [ ] **Step 3: Commit**

```bash
git add App/CardCopilot/Views/
git commit -m "refactor(app): read dependencies from the environment in detail views"
```

---

### Task 9: Convert `SyncCenterView`

The single largest view signature: 20 parameters, roughly 17 of them `sync.*` forwarding.

**Files:**
- Modify: `App/CardCopilot/Views/SyncCenterView.swift`
- Reference: `App/CardCopilot/Views/CheckoutFlowView.swift:313-340` for the current call site

- [ ] **Step 1: Replace the parameter list**

```swift
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.dismiss) private var dismiss
```

Every `lastSyncedAt`, `feedback`, `installations`, `syncIssue`, `isSyncing`, `isPreparingAccount` becomes `sync.<name>`. Every closure that wrapped a `sync` method (`onCreateInstallation`, `onRevokeInstallation`, `onTestCaptureConnection`, `onAssignUnassigned`, `onDeleteUnassigned`, `onDisableCapture`, `onSubmitDiagnostic`, `onDeleteSubmittedDiagnostic`, `onListSubmittedDiagnostics`) calls `sync` directly.

**Keep as real parameters** the three that are not `sync` state: `isSignedIn`, `boundAccountLabel`, `isCaptureBoundToCurrentAccount`. These derive from `Clerk.shared` and `WalletCaptureCredentialStore`, not from `SyncCoordinator`. Computing them inside the view would hide a keychain read behind a `body` evaluation.

`onSync` becomes a parameter too — it calls `syncFromUI()`, which lives on `CopilotEnvironment`.

- [ ] **Step 2: Run the App tests**

Run the App test command. Expected: PASS, 47 tests.

- [ ] **Step 3: Commit**

```bash
git add App/CardCopilot/Views/SyncCenterView.swift App/CardCopilot/Views/CheckoutFlowView.swift
git commit -m "refactor(app): read SyncCoordinator from the environment in SyncCenterView"
```

---

### Task 10: Thin the hub views

**Files:**
- Modify: `HomeView.swift` (27 stored properties), `YouHubView.swift` (14), `ActivityHubView.swift` (9), `WalletHubView.swift` (6), `PerksHubView.swift` (4)

- [ ] **Step 1: For each hub, replace forwarded state with environment reads**

```swift
    @Environment(CopilotSession.self) private var session
    @Environment(CheckoutRouter.self) private var router
    @Environment(SyncCoordinator.self) private var sync
    @Environment(AmbientLocationService.self) private var ambient
```

`valueRecoveredCad`, `pendingValueCad`, `merchants`, `finishCount`, `reconcileCount`, `confirmedCount`, `locationDenied`, `lastSyncedAt`, `syncIssueMessage`, `ambientDiagnostics`, `ambientEnabled` all become reads off those objects.

Every `onOpenX: { stage = .x }` closure becomes a direct `router.push(.x)` at the point of use, deleting the parameter.

**Keep as parameters** only genuine leaf inputs that are not shared state — for `HomeView` that is `isSortedByRecentLocation` (derived from `session.cachedLocation?.isRecent`, so it can also move; prefer moving it) and the two action closures that trigger `async` work the view cannot own: `onFindNearby`, `onSearch`.

Target: `HomeView` under 6 stored properties.

- [ ] **Step 2: Run the App tests**

Run the App test command. Expected: PASS, 47 tests.

- [ ] **Step 3: Verify the parameter reduction**

Run: `awk '/^struct HomeView: View/,/^    var body/' App/CardCopilot/Views/HomeView.swift | grep -cE "^    (let|var) "`
Expected: 6 or fewer (was 27).

- [ ] **Step 4: Commit**

```bash
git add App/CardCopilot/Views/
git commit -m "refactor(app): read shared state from the environment in hub views"
```

---

### Task 11: Device verification

Tests cannot verify push animations, back-swipe, or alert presentation. This task is manual and must not be skipped — Design Decision 2 made navigation a visible behaviour change.

**Files:** none.

- [ ] **Step 1: Build and launch on a simulator**

```bash
xcrun simctl list devices available | grep iPhone
```

Then use the iOS Simulator control tooling to launch the app and drive it.

- [ ] **Step 2: Walk each path and confirm**

| Check | Expected |
|---|---|
| Tap Dashboard from Home | Pushes with animation; back-swipe returns to Home |
| Push Settings → Sync | Two-deep stack; back returns to Settings, not Home |
| Switch tabs with a screen pushed | Path clears; new tab shows its root |
| Nearby with location denied | Returns to idle, manual search still usable |
| Search a nonsense string | Full-screen "Nothing found for X", not an alert |
| Force a reconcile write failure | **Alert over the reconcile screen; the owner keeps their place** |
| First run with no local owner | Welcome gate shows instead of the tab root |
| Deep link into Sync while a screen is pushed | Sync appends to the stack |

- [ ] **Step 3: Confirm the full suite one final time**

```bash
cd Engine && swift test          # expect 238
cd ../Store && swift test        # expect 201
cd ../App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot \
  -configuration Debug -destination "id=<UDID>" CODE_SIGNING_ALLOWED=NO   # expect 47
```

- [ ] **Step 4: Commit any fixes and open the PR**

```bash
git add -A
git commit -m "fix(app): device-verification corrections for the navigation split"
```

---

## Self-Review

**Spec coverage.** Every design decision maps to a task: three objects (4, 5, 6), `Destination`/`CheckoutStep` split (2), pure routing (2), alert-based errors (5), push/pop navigation (3, 7), `.welcome` as a root gate (7), account lifecycle on `CopilotEnvironment` (4, 7). The `BenefitContext` prerequisite is Task 1.

**Placeholders.** Tasks 7–10 give exact files, exact replacements, and exact verification commands, but do not reproduce every ported line — Task 7 alone moves nine methods. This is deliberate and flagged inline ("read each in full and port verbatim"), because reproducing ~400 lines of unchanged code in a plan invites transcription errors rather than preventing them. Every such instance names the source file and line range.

**Type consistency.** `DependencyGraph` (not `Dependencies`) is used from Task 4 onward. `CopilotEnvironment.graph` is optional; consumers unwrap. `FlowOutcome` is `Equatable`; `CheckoutStep` is not, so its tests pattern-match. `CheckoutRouter.selectTab(_:)` is the method, `selectedTab` the property.

**Known risk.** Task 7 is large enough that it could reasonably be split, but the sweeping-refactor decision means there is no green intermediate between Tasks 7 and 10 regardless — the app will not compile mid-Task-7. Budget accordingly.
