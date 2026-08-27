# Merchant Patronage Owner Surface (T4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the owner see which merchants PickMe has learned they frequent, forget one, or block a merchant from ever being learned — closing the loop on the ambient patronage machinery that already infers `.frequented` standing silently.

**Architecture:** Extend `MerchantPatronageStore` (Store package) with `forget`, a block list (`block`/`unblock`/`isBlocked`/`blockedKeys`), and a `learnedMerchants(asOf:calendar:)` read model. A new SwiftUI view in the App target lists that read model, with swipe-to-forget and a block action, reached from Settings' Ambient section.

**Tech Stack:** Swift, XCTest, SwiftUI. No new dependencies.

**Spec:** Task description in the conversation that produced this plan (owner-facing surface for merchant patronage, "T4"), 2026-08-27.

## Global Constraints

- TDD: write the failing test before the implementation, for every Store change.
- Policy/storage decisions live in `Store`; the App target is a thin adapter. See header comment in `Store/Sources/CardCopilotStore/DiscoveryPolicy.swift`.
- Keep `Engine`, `Store`, `App` suites green: `cd Store && swift test`, `cd Engine && swift test`.
- `AmbientMerchantMuteStore` (post-hoc, arrival-key-based) and the new patronage block list (pre-learning, pre-index-key-based) stay separate keyspaces — do not merge them.
- `String(localized:defaultValue:)` for all owner-facing copy.
- Never `git add -A`; stage explicitly. No `Co-Authored-By` trailer.
- Do not pass `-sdk iphonesimulator` to `xcodebuild`.

---

## Task 1: `forget(merchantKey:)`

**Files:**
- Modify: `Store/Sources/CardCopilotStore/MerchantPatronageStore.swift`
- Test: `Store/Tests/CardCopilotStoreTests/MerchantPatronageStoreTests.swift`

**Interfaces:**
- Produces: `func forget(merchantKey: String)` — drops one merchant's visit days, leaves others untouched.

- [ ] Write failing test `testForgetOneMerchantOnlyClearsThatMerchant`:
```swift
func testForgetOneMerchantOnlyClearsThatMerchant() {
    record("loblaws", [now, daysAgo(7), daysAgo(20)])
    record("sobeys", [now, daysAgo(7), daysAgo(20)])
    store.forget(merchantKey: "loblaws")
    XCTAssertTrue(store.visitDayKeys(for: "loblaws").isEmpty)
    XCTAssertFalse(store.visitDayKeys(for: "sobeys").isEmpty)
}
```
- [ ] Run `cd Store && swift test --filter MerchantPatronageStoreTests` — expect FAIL (`forget` undefined).
- [ ] Implement in `MerchantPatronageStore`:
```swift
/// Drops one merchant's visit history without touching any other.
public func forget(merchantKey: String) {
    var all = load()
    all.removeValue(forKey: merchantKey)
    save(all)
}
```
- [ ] Run tests again — expect PASS.
- [ ] Commit: `git add Store/Sources/CardCopilotStore/MerchantPatronageStore.swift Store/Tests/CardCopilotStoreTests/MerchantPatronageStoreTests.swift && git commit -m "feat(store): forget one patronage merchant"`

## Task 2: Block list

**Files:**
- Modify: `Store/Sources/CardCopilotStore/MerchantPatronageStore.swift`
- Test: `Store/Tests/CardCopilotStoreTests/MerchantPatronageStoreTests.swift`

**Interfaces:**
- Consumes: `forget(merchantKey:)` from Task 1.
- Produces: `block(merchantKey:)`, `unblock(merchantKey:)`, `isBlocked(merchantKey:) -> Bool`, `blockedKeys() -> Set<String>`. `block` wipes any existing accrued visits for that key (blocking is "forget and never relearn", not just "hide"). `recordVisit` refuses to accrue for a blocked key. `frequentedKeys` excludes blocked keys defensively.

- [ ] Write failing tests:
```swift
func testBlockingAMerchantStopsFutureVisitsFromAccruing() {
    store.block(merchantKey: "esso")
    record("esso", [now, daysAgo(7), daysAgo(20)])
    XCTAssertTrue(store.visitDayKeys(for: "esso").isEmpty)
    XCTAssertFalse(store.isFrequented(merchantKey: "esso", asOf: now, calendar: calendar))
}

func testBlockingAnAlreadyFrequentedMerchantRemovesItFromStanding() {
    record("loblaws", [now, daysAgo(7), daysAgo(20)])
    XCTAssertTrue(store.isFrequented(merchantKey: "loblaws", asOf: now, calendar: calendar))
    store.block(merchantKey: "loblaws")
    XCTAssertFalse(store.isFrequented(merchantKey: "loblaws", asOf: now, calendar: calendar))
    XCTAssertTrue(store.frequentedKeys(asOf: now, calendar: calendar).isEmpty)
}

func testUnblockingAllowsVisitsToAccrueAgain() {
    store.block(merchantKey: "esso")
    store.unblock(merchantKey: "esso")
    record("esso", [now, daysAgo(7), daysAgo(20)])
    XCTAssertTrue(store.isFrequented(merchantKey: "esso", asOf: now, calendar: calendar))
}

func testIsBlockedAndBlockedKeys() {
    store.block(merchantKey: "esso")
    XCTAssertTrue(store.isBlocked(merchantKey: "esso"))
    XCTAssertEqual(store.blockedKeys(), ["esso"])
    store.unblock(merchantKey: "esso")
    XCTAssertFalse(store.isBlocked(merchantKey: "esso"))
    XCTAssertTrue(store.blockedKeys().isEmpty)
}
```
- [ ] Run — expect FAIL.
- [ ] Implement:
```swift
private var blockedKeysKey: String { key + ".blocked" }

/// Stops a merchant from ever earning patronage standing again. Wipes any visits already
/// accrued — blocking means "never learn this place", not "hide what was already learned".
public func block(merchantKey: String) {
    forget(merchantKey: merchantKey)
    var blocked = loadBlocked()
    blocked.insert(merchantKey)
    saveBlocked(blocked)
}

public func unblock(merchantKey: String) {
    var blocked = loadBlocked()
    blocked.remove(merchantKey)
    saveBlocked(blocked)
}

public func isBlocked(merchantKey: String) -> Bool {
    loadBlocked().contains(merchantKey)
}

public func blockedKeys() -> Set<String> {
    loadBlocked()
}

private func loadBlocked() -> Set<String> {
    Set(defaults.stringArray(forKey: blockedKeysKey) ?? [])
}

private func saveBlocked(_ value: Set<String>) {
    defaults.set(Array(value), forKey: blockedKeysKey)
}
```
Modify `recordVisit` to guard at the top:
```swift
public func recordVisit(merchantKey: String, at date: Date = Date(), calendar: Calendar = .current) {
    guard !isBlocked(merchantKey: merchantKey) else { return }
    var all = load()
    ...
}
```
Modify `frequentedKeys` to subtract blocked keys:
```swift
public func frequentedKeys(asOf date: Date = Date(), calendar: Calendar = .current) -> Set<String> {
    let blocked = loadBlocked()
    return Set(load().filter {
        !blocked.contains($0.key) &&
        CardCopilotStore.isFrequented(visitDayKeys: $0.value, asOf: date, calendar: calendar)
    }.keys)
}
```
- [ ] Run tests — expect PASS.
- [ ] Commit: `git add Store/Sources/CardCopilotStore/MerchantPatronageStore.swift Store/Tests/CardCopilotStoreTests/MerchantPatronageStoreTests.swift && git commit -m "feat(store): patronage block list"`

## Task 3: `forgetAll()` clears the block list

**Files:**
- Modify: `Store/Sources/CardCopilotStore/MerchantPatronageStore.swift`
- Test: `Store/Tests/CardCopilotStoreTests/MerchantPatronageStoreTests.swift`

**Decision (pinned):** `forgetAll()` clears the block list too. "Erase this iPhone's history" is the owner reaching for a full wipe; a block silently surviving it would keep suppressing a merchant for a reason the owner can no longer see.

- [ ] Write failing test:
```swift
func testForgetAllClearsTheBlockListToo() {
    // "Erase this iPhone's history" is a full wipe. Leaving the block list behind would
    // silently keep suppressing a merchant the owner has no remaining way to see or reverse.
    store.block(merchantKey: "esso")
    store.forgetAll()
    XCTAssertTrue(store.blockedKeys().isEmpty)
    XCTAssertFalse(store.isBlocked(merchantKey: "esso"))
}
```
- [ ] Run — expect FAIL.
- [ ] Implement — modify `forgetAll()`:
```swift
public func forgetAll() {
    defaults.removeObject(forKey: key)
    defaults.removeObject(forKey: blockedKeysKey)
}
```
- [ ] Run tests — expect PASS.
- [ ] Commit: `git add -u Store && git commit -m "fix(store): forgetAll also clears the patronage block list"`

## Task 4: `learnedMerchants(asOf:calendar:)` read model

**Files:**
- Modify: `Store/Sources/CardCopilotStore/MerchantPatronageStore.swift`
- Test: `Store/Tests/CardCopilotStoreTests/MerchantPatronageStoreTests.swift`

**Interfaces:**
- Produces:
```swift
public struct LearnedMerchant: Identifiable, Equatable, Sendable {
    public var id: String { merchantKey }
    public let merchantKey: String
    public let displayName: String
    public let visitCount: Int
    public let earliestDayKey: String
    public let latestDayKey: String
    public let qualifies: Bool
}
public func learnedMerchants(asOf date: Date = Date(), calendar: Calendar = .current) -> [LearnedMerchant]
```
Display name resolves via `CanadianMerchantPreIndex.all.first { $0.id == key }?.name`, falling back to the raw key. Only days within the window count toward `visitCount`/`qualifies`/earliest/latest — blocked merchants have no data by construction (Task 2) so nothing extra to filter here.

- [ ] Write failing tests:
```swift
func testLearnedMerchantsReturnsCountsAndQualification() {
    record("loblaws", [daysAgo(20), daysAgo(7), now])
    record("sobeys", [daysAgo(7), now])
    let learned = store.learnedMerchants(asOf: now, calendar: calendar)
    let loblaws = learned.first { $0.merchantKey == "loblaws" }
    let sobeys = learned.first { $0.merchantKey == "sobeys" }
    XCTAssertEqual(loblaws?.visitCount, 3)
    XCTAssertEqual(loblaws?.qualifies, true)
    XCTAssertEqual(loblaws?.displayName, "Loblaws")
    XCTAssertEqual(loblaws?.earliestDayKey, patronageDayKey(for: daysAgo(20), calendar: calendar))
    XCTAssertEqual(loblaws?.latestDayKey, patronageDayKey(for: now, calendar: calendar))
    XCTAssertEqual(sobeys?.visitCount, 2)
    XCTAssertEqual(sobeys?.qualifies, false)
    XCTAssertEqual(sobeys?.displayName, "Sobeys")
}

func testLearnedMerchantsFallsBackToRawKeyWhenUnindexed() {
    record("some-unindexed-place", [now])
    let learned = store.learnedMerchants(asOf: now, calendar: calendar)
    XCTAssertEqual(learned.first?.displayName, "some-unindexed-place")
}

func testLearnedMerchantsOnlyCountsDaysInsideTheWindow() {
    record("loblaws", [daysAgo(200), daysAgo(150), now, daysAgo(7), daysAgo(20)])
    let learned = store.learnedMerchants(asOf: now, calendar: calendar)
    XCTAssertEqual(learned.first { $0.merchantKey == "loblaws" }?.visitCount, 3)
}
```
- [ ] Run — expect FAIL.
- [ ] Implement:
```swift
public struct LearnedMerchant: Identifiable, Equatable, Sendable {
    public var id: String { merchantKey }
    public let merchantKey: String
    public let displayName: String
    public let visitCount: Int
    public let earliestDayKey: String
    public let latestDayKey: String
    public let qualifies: Bool
}

/// Everything the owner-facing screen needs, resolved once rather than re-derived per row.
public func learnedMerchants(asOf date: Date = Date(), calendar: Calendar = .current) -> [LearnedMerchant] {
    load().compactMap { key, days in
        let live = patronageDaysWithinWindow(days, asOf: date, calendar: calendar)
        guard let earliest = live.min(), let latest = live.max() else { return nil }
        let displayName = CanadianMerchantPreIndex.all.first { $0.id == key }?.name ?? key
        return LearnedMerchant(merchantKey: key, displayName: displayName, visitCount: live.count,
                               earliestDayKey: earliest, latestDayKey: latest,
                               qualifies: live.count >= patronageVisitDaysRequired)
    }
}
```
- [ ] Run tests — expect PASS.
- [ ] Run the full Store suite: `cd Store && swift test` — expect all green (baseline 287 + new tests).
- [ ] Commit: `git add -u Store && git commit -m "feat(store): learnedMerchants read model for the owner surface"`

## Task 5: Wire the destination and navigation entry point

**Files:**
- Modify: `App/CardCopilot/State/Destination.swift`
- Modify: `App/CardCopilot/Views/SettingsView.swift`
- Modify: `App/CardCopilot/Views/CheckoutFlowView.swift`

**Interfaces:**
- Consumes: `Destination` enum, `router.push(_:)` (existing pattern, see `.ambientSetup`).
- Produces: `Destination.learnedMerchants` case; `SettingsView.onOpenLearnedMerchants: () -> Void`.

- [ ] In `Destination.swift`, add a case after `ambientSetup`:
```swift
    case ambientSetup
    case learnedMerchants
```
- [ ] In `SettingsView.swift`, add a parameter `let onOpenLearnedMerchants: () -> Void` alongside `onOpenAmbient`, and in the `Section("Ambient")` block add a second button:
```swift
Section("Ambient") {
    Button(ambientEnabled ? "Arrival alerts" : "Ambient arrival setup", action: onOpenAmbient)
    Button("Learned merchants", action: onOpenLearnedMerchants)
}
```
- [ ] In `CheckoutFlowView.swift`, pass the closure at the `.settings` call site (near `onOpenAmbient: { router.push(.ambientSetup) }`):
```swift
onOpenLearnedMerchants: { router.push(.learnedMerchants) },
```
- [ ] Add the routing case near `.ambientSetup`, once `LearnedMerchantsView` exists (Task 6) — placeholder for now is fine since Task 6 lands in the same PR before any build/test run:
```swift
case .learnedMerchants:
    LearnedMerchantsView(onDone: { router.pop() })
```
- [ ] Commit deferred to end of Task 6 (this task doesn't compile alone without the view).

## Task 6: `LearnedMerchantsView`

**Files:**
- Create: `App/CardCopilot/Views/LearnedMerchantsView.swift`

**Interfaces:**
- Consumes: `MerchantPatronageStore` (Store package, existing), `.learnedMerchants(asOf:calendar:) -> [LearnedMerchant]`, `.forget(merchantKey:)`, `.block(merchantKey:)`.
- Produces: `struct LearnedMerchantsView: View { let onDone: () -> Void }` — no other init params; it owns its own `MerchantPatronageStore()` instance, matching how `WalletCaptureIntent` instantiates one ad hoc rather than threading it through the environment.

- [ ] Write the view:
```swift
import SwiftUI
import CardCopilotStore

/// Lists every merchant PickMe has learned the owner frequents, from Wallet captures alone —
/// no amount, no card, no coordinate, per `MerchantPatronageStore`'s retention promise.
/// Swiping a row forgets it; "Never learn this place" additionally stops it from ever
/// re-accruing standing.
struct LearnedMerchantsView: View {
    let onDone: () -> Void

    @State private var merchants: [LearnedMerchant] = []
    private let store = MerchantPatronageStore()

    var body: some View {
        List {
            if merchants.isEmpty {
                Section {
                    Text("learned-merchants.empty",
                         defaultValue: "PickMe hasn't learned any merchants yet. Arrival alerts get more confident once you've paid at the same place a few times.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(merchants) { merchant in
                        row(for: merchant)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    forget(merchant)
                                } label: {
                                    Label(String(localized: "learned-merchants.forget",
                                                defaultValue: "Forget"), systemImage: "trash")
                                }
                                Button {
                                    block(merchant)
                                } label: {
                                    Label(String(localized: "learned-merchants.never-learn",
                                                defaultValue: "Never learn this place"),
                                         systemImage: "hand.raised.slash")
                                }
                                .tint(.orange)
                            }
                    }
                } footer: {
                    Text("learned-merchants.footer",
                         defaultValue: "Standing is based only on which days you paid there — never the amount, the card, or where you were.")
                }
            }
        }
        .navigationTitle(String(localized: "learned-merchants.title", defaultValue: "Learned merchants"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "common.done", defaultValue: "Done"), action: onDone)
                    .font(.headline)
            }
        }
        .onAppear(perform: reload)
    }

    private func row(for merchant: LearnedMerchant) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(merchant.displayName)
                .font(.body.weight(.semibold))
            HStack(spacing: 6) {
                if merchant.qualifies {
                    Label(String(localized: "learned-merchants.qualifies",
                                defaultValue: "Recognized"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    let template = String(localized: "learned-merchants.progress",
                                          defaultValue: "%d of %d visits")
                    Label(String(format: template, merchant.visitCount, patronageVisitDaysRequired),
                         systemImage: "clock")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }

    private func reload() {
        merchants = store.learnedMerchants().sorted { $0.latestDayKey > $1.latestDayKey }
    }

    private func forget(_ merchant: LearnedMerchant) {
        store.forget(merchantKey: merchant.merchantKey)
        reload()
    }

    private func block(_ merchant: LearnedMerchant) {
        store.block(merchantKey: merchant.merchantKey)
        reload()
    }
}
```
- [ ] Confirm the routing case added in Task 5 now compiles.
- [ ] Build the App target: find a simulator UDID with `xcrun simctl list devices available`, then
```bash
cd App && xcodebuild build -project CardCopilot.xcodeproj -scheme CardCopilot -configuration Debug -destination "id=<sim-udid>" CODE_SIGNING_ALLOWED=NO
```
Expected: build succeeds.
- [ ] Run the App test target the same way with `test` instead of `build`. Expected: 69 existing tests still pass (no App-level tests are added for this view per the plan — behaviour lives in the Store-level tests from Tasks 1–4).
- [ ] Manually sanity-check in the simulator: Settings → Ambient → "Learned merchants" opens the list, swipe reveals Forget/Never learn this place, empty state renders with no data recorded.
- [ ] Commit: `git add App/CardCopilot/Views/LearnedMerchantsView.swift App/CardCopilot/State/Destination.swift App/CardCopilot/Views/SettingsView.swift App/CardCopilot/Views/CheckoutFlowView.swift && git commit -m "feat(app): owner-facing learned merchants list with forget/block"`

## Task 7: Full regression pass

- [ ] `cd Engine && swift test` — expect 272 tests green (unchanged).
- [ ] `cd Store && swift test` — expect 287 + 9 new = 296 tests green.
- [ ] App build + test as in Task 6.
- [ ] Confirm `git status` shows only the intended files changed beyond what was already modified/untracked at session start (per the "another session may be writing in this tree" constraint) — stage explicitly, never `git add -A`.

---

## Self-review notes

- Spec coverage: `forget` (Task 1), block list + `frequentedKeys`/`recordVisit` exclusion (Task 2), `forgetAll` block-list decision pinned with test (Task 3), `learnedMerchants` read model (Task 4), list view with swipe-to-forget/block reachable from Settings (Tasks 5–6). `AmbientMerchantMuteStore` left untouched — confirmed its keyspace (arrival mute key) is unrelated to the patronage block list (pre-index merchant id).
- No placeholders: every step has runnable code.
- Type consistency: `LearnedMerchant` fields (`merchantKey`, `displayName`, `visitCount`, `earliestDayKey`, `latestDayKey`, `qualifies`) are used identically in the Task 4 test, the Task 4 implementation, and the Task 6 view.
