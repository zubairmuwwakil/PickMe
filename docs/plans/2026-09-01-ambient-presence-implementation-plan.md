# Ambient Presence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PickMe visible on every arrival it can honestly speak to, while it keeps interrupting only when switching cards earns money.

**Architecture:** `AmbientGate` gains a second output — a delivery tier derived from the suppression reasons it already computes. `AmbientLocationService` routes on that tier instead of on one boolean, and the Live Activity is started from the routing site rather than from inside the notification function. Two Live Activity lifecycle defects are fixed in the same change because they go from rare to routine once activities fire on every arrival.

**Tech Stack:** Swift 6 (SwiftPM engine + Xcode app target), Kotlin (Android engine twin), ActivityKit, UserNotifications, UserDefaults-backed ambient stores.

**Spec:** `docs/plans/2026-09-01-ambient-presence-and-payment-loop-design.md` (this plan implements **piece 1, Presence**, from that spec's Sequencing section)

## Global Constraints

- Cross-language gate, must pass before any task is considered done:
  `(cd Engine && swift test) && (cd android && ./gradlew :core:engine:test)`
- App target build/test:
  `cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot -configuration Debug -destination "id=<simulator-udid>" CODE_SIGNING_ALLOWED=NO`
- **Never pass `-sdk iphonesimulator`** to xcodebuild. It overrides `SDKROOT` for the embedded watch app and `actool` fails the whole build before any Swift compiles.
- Work directly on `main`. Do not create branches or pull requests.
- Do **not** add a `Co-Authored-By` trailer to commits.
- `App/CardCopilot/Services/CardCopilotActivityAttributes.swift` and `App/CardCopilotWidgets/CardCopilotActivityAttributes.swift` are byte-identical copies and **must stay identical** — ActivityKit requires the app and the widget extension to agree on `ContentState`. Every edit to one is applied verbatim to the other.
- `fires` must keep meaning exactly what it means today (`tier == .interrupt`), so `SuppressionLog` counters and the TestFlight A3 criterion are unchanged.
- Owner-facing copy goes through `String(localized:defaultValue:)`, matching the surrounding ambient code.
- The `presence` tier must never name a card. Naming a card at an unidentifiable merchant is a confident wrong answer.

---

### Task 1: Delivery tier in the Swift engine

**Files:**
- Modify: `Engine/Sources/CardCopilotEngine/Engine/AmbientGate.swift` (the `AmbientGateDecision` struct, ~line 86)
- Test: `Engine/Tests/CardCopilotEngineTests/AmbientGateTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public enum AmbientDeliveryTier: String, Codable, Equatable, Sendable, CaseIterable { case silent, presence, confirm, interrupt }` and `AmbientGateDecision.tier: AmbientDeliveryTier`. `AmbientGateDecision.fires: Bool` is retained, redefined as `tier == .interrupt`.

- [x] **Step 1: Write the failing tests**

Append to `Engine/Tests/CardCopilotEngineTests/AmbientGateTests.swift`, inside the existing `AmbientGateTests` class (it already defines `both` and `passingInput()`):

```swift
    // MARK: - Delivery tier

    func testClearArrivalInterrupts() {
        XCTAssertEqual(AmbientGate.evaluate(passingInput()).tier, .interrupt)
    }

    func testDefaultCardWinConfirmsRatherThanSilencing() {
        var input = passingInput()
        input.recommendedCardId = input.defaultCardId
        XCTAssertEqual(AmbientGate.evaluate(input).tier, .confirm)
    }

    func testAdvantageBelowThresholdConfirms() {
        var input = passingInput()
        input.advantage = AmbientAdvantage(percentagePoints: 0.99, cad: 2)
        XCTAssertEqual(AmbientGate.evaluate(input).tier, .confirm)
    }

    func testUnknownMerchantGetsPresenceWithoutAdvice() {
        var input = passingInput()
        input.merchantConfidence = .unknown
        XCTAssertEqual(AmbientGate.evaluate(input).tier, .presence)
    }

    func testMutedMerchantIsSilent() {
        var input = passingInput()
        input.isMuted = true
        XCTAssertEqual(AmbientGate.evaluate(input).tier, .silent)
    }

    /// Consent outranks a correctness stop, which outranks a volume judgement.
    func testMutePrecedesEveryOtherReason() {
        var input = passingInput()
        input.isMuted = true
        input.merchantConfidence = .unknown
        input.recommendedCardId = input.defaultCardId
        XCTAssertEqual(AmbientGate.evaluate(input).tier, .silent)
    }

    func testUnknownMerchantPrecedesVolumeReasons() {
        var input = passingInput()
        input.merchantConfidence = .unknown
        input.recommendedCardId = input.defaultCardId
        XCTAssertEqual(AmbientGate.evaluate(input).tier, .presence)
    }

    /// The TestFlight A3 criterion and `SuppressionLog` both read `fires`. It must keep
    /// meaning "PickMe interrupted", not "PickMe was visible".
    func testFiresStillMeansInterrupt() {
        for input in [passingInput(), mutedInput(), unknownInput(), defaultWinInput()] {
            let decision = AmbientGate.evaluate(input)
            XCTAssertEqual(decision.fires, decision.tier == .interrupt)
            XCTAssertEqual(decision.fires, decision.suppressionReasons.isEmpty)
        }
    }

    private func mutedInput() -> AmbientGateInput {
        var input = passingInput(); input.isMuted = true; return input
    }

    private func unknownInput() -> AmbientGateInput {
        var input = passingInput(); input.merchantConfidence = .unknown; return input
    }

    private func defaultWinInput() -> AmbientGateInput {
        var input = passingInput(); input.recommendedCardId = input.defaultCardId; return input
    }
```

- [x] **Step 2: Run the tests to verify they fail**

Run: `cd Engine && swift test --filter AmbientGateTests`
Expected: FAIL — `value of type 'AmbientGateDecision' has no member 'tier'`.

- [x] **Step 3: Add the tier**

In `Engine/Sources/CardCopilotEngine/Engine/AmbientGate.swift`, insert immediately **above** `public struct AmbientGateDecision`:

```swift
/// How an arrival should reach the owner.
///
/// The gate used to answer one question — interrupt or stay silent — and the Live Activity was
/// started from inside the notification path, so one boolean decided both whether PickMe spoke
/// and whether PickMe was *visible*. That coupling was a consequence of call-site placement, not
/// a policy: it left the owner seeing nothing on most arrivals.
///
/// The tiers are derived from the suppression reasons rather than added alongside them, because
/// the reasons already record the distinction that matters. Two of them are volume judgements
/// ("the answer is: keep going"), one is a correctness stop ("we do not know this merchant"), and
/// one is consent ("you told us to stop"). Those deserve different treatment and the same
/// notification budget cannot express it.
public enum AmbientDeliveryTier: String, Codable, Equatable, Sendable, CaseIterable {
    /// Nothing at all. The owner's explicit instruction, not a volume dial.
    case silent
    /// Visible, but carrying no card advice. Naming a card at a merchant we cannot identify is a
    /// confident wrong answer, which costs trust faster than silence does.
    case presence
    /// Visible and advisory, but never audible: the answer is "stay on the card you were going
    /// to use anyway", which is worth showing and not worth interrupting for.
    case confirm
    /// Sound, time-sensitive banner, and a Live Activity. Reserved for arrivals where switching
    /// cards actually earns money.
    case interrupt
}
```

Then replace the body of `AmbientGateDecision`:

```swift
public struct AmbientGateDecision: Codable, Equatable, Sendable {
    public let suppressionReasons: Set<AmbientSuppressionReason>

    public init(suppressionReasons: Set<AmbientSuppressionReason>) {
        self.suppressionReasons = suppressionReasons
    }

    /// Precedence: consent, then correctness, then volume. Expressed as ordered checks rather
    /// than as a `Comparable` ranking so that adding a reason forces a decision about where it
    /// sits, instead of defaulting into the quietest tier by accident.
    public var tier: AmbientDeliveryTier {
        if suppressionReasons.contains(.merchantMuted) { return .silent }
        if suppressionReasons.contains(.merchantConfidenceLow) { return .presence }
        return suppressionReasons.isEmpty ? .interrupt : .confirm
    }

    /// Unchanged in meaning: PickMe interrupted. `SuppressionLog` and the TestFlight A3
    /// criterion both read this, and neither is a statement about visibility.
    public var fires: Bool { tier == .interrupt }
}
```

- [x] **Step 4: Run the tests to verify they pass**

Run: `cd Engine && swift test --filter AmbientGateTests`
Expected: PASS, including the pre-existing suppression-reason tests, which are untouched.

- [x] **Step 5: Run the full engine suite**

Run: `cd Engine && swift test`
Expected: PASS. No other engine code reads `AmbientGateDecision`.

- [x] **Step 6: Commit**

```bash
git add Engine/Sources/CardCopilotEngine/Engine/AmbientGate.swift Engine/Tests/CardCopilotEngineTests/AmbientGateTests.swift
git commit -m "feat(ambient): derive a delivery tier from the gate's suppression reasons"
```

---

### Task 2: Delivery tier in the Kotlin twin

**Files:**
- Modify: `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/AmbientGate.kt` (the `AmbientGateDecision` data class, ~line 49)
- Create: `android/core/engine/src/test/kotlin/com/cardcopilot/engine/AmbientGateTest.kt`

**Interfaces:**
- Consumes: the tier semantics defined in Task 1. The two twins must agree exactly.
- Produces: `enum class AmbientDeliveryTier { SILENT, PRESENCE, CONFIRM, INTERRUPT }` and `AmbientGateDecision.tier`.

Note: there is no Kotlin test for this file today — the Swift side is the only place the gate is covered. This task creates the missing twin test as well as the twin behaviour, which is why it is one task rather than two.

- [x] **Step 1: Write the failing test**

Create `android/core/engine/src/test/kotlin/com/cardcopilot/engine/AmbientGateTest.kt`:

```kotlin
package com.cardcopilot.engine

import com.cardcopilot.engine.engine.AmbientAdvantage
import com.cardcopilot.engine.engine.AmbientDeliveryTier
import com.cardcopilot.engine.engine.AmbientGate
import com.cardcopilot.engine.engine.AmbientGateInput
import com.cardcopilot.engine.engine.AmbientMerchantConfidence
import com.cardcopilot.engine.models.SwitchThreshold
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Test

class AmbientGateTest {
    private val both = SwitchThreshold(
        minAdvantagePercentagePoints = 1.0,
        minAdvantageCad = 1.0,
        semantics = "both"
    )

    private fun passingInput() = AmbientGateInput(
        merchantConfidence = AmbientMerchantConfidence.VERIFIED,
        recommendedCardId = "amex-cobalt",
        defaultCardId = "wealthsimple-vip",
        advantage = AmbientAdvantage(percentagePoints = 1.5, cad = 2.0),
        switchThreshold = both,
        isMuted = false
    )

    @Test
    fun clearArrivalInterrupts() {
        assertEquals(AmbientDeliveryTier.INTERRUPT, AmbientGate.evaluate(passingInput()).tier)
    }

    @Test
    fun defaultCardWinConfirmsRatherThanSilencing() {
        val input = passingInput().copy(recommendedCardId = "wealthsimple-vip")
        assertEquals(AmbientDeliveryTier.CONFIRM, AmbientGate.evaluate(input).tier)
    }

    @Test
    fun advantageBelowThresholdConfirms() {
        val input = passingInput().copy(
            advantage = AmbientAdvantage(percentagePoints = 0.99, cad = 2.0)
        )
        assertEquals(AmbientDeliveryTier.CONFIRM, AmbientGate.evaluate(input).tier)
    }

    @Test
    fun unknownMerchantGetsPresenceWithoutAdvice() {
        val input = passingInput().copy(merchantConfidence = AmbientMerchantConfidence.UNKNOWN)
        assertEquals(AmbientDeliveryTier.PRESENCE, AmbientGate.evaluate(input).tier)
    }

    @Test
    fun mutedMerchantIsSilent() {
        assertEquals(
            AmbientDeliveryTier.SILENT,
            AmbientGate.evaluate(passingInput().copy(isMuted = true)).tier
        )
    }

    @Test
    fun mutePrecedesEveryOtherReason() {
        val input = passingInput().copy(
            isMuted = true,
            merchantConfidence = AmbientMerchantConfidence.UNKNOWN,
            recommendedCardId = "wealthsimple-vip"
        )
        assertEquals(AmbientDeliveryTier.SILENT, AmbientGate.evaluate(input).tier)
    }

    @Test
    fun unknownMerchantPrecedesVolumeReasons() {
        val input = passingInput().copy(
            merchantConfidence = AmbientMerchantConfidence.UNKNOWN,
            recommendedCardId = "wealthsimple-vip"
        )
        assertEquals(AmbientDeliveryTier.PRESENCE, AmbientGate.evaluate(input).tier)
    }

    @Test
    fun firesStillMeansInterrupt() {
        val inputs = listOf(
            passingInput(),
            passingInput().copy(isMuted = true),
            passingInput().copy(merchantConfidence = AmbientMerchantConfidence.UNKNOWN),
            passingInput().copy(recommendedCardId = "wealthsimple-vip")
        )
        for (input in inputs) {
            val decision = AmbientGate.evaluate(input)
            assertEquals(decision.tier == AmbientDeliveryTier.INTERRUPT, decision.fires)
            assertEquals(decision.suppressionReasons.isEmpty(), decision.fires)
        }
    }
}
```

- [x] **Step 2: Run the test to verify it fails**

Run: `cd android && ./gradlew :core:engine:test --tests "*AmbientGateTest*"`
Expected: FAIL — unresolved reference `AmbientDeliveryTier`.

- [x] **Step 3: Add the tier to the twin**

In `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/AmbientGate.kt`, insert immediately **above** `data class AmbientGateDecision`:

```kotlin
/**
 * How an arrival should reach the owner.
 *
 * Derived from the suppression reasons rather than added alongside them: two of the reasons are
 * volume judgements ("the answer is: keep going"), one is a correctness stop ("we do not know
 * this merchant"), and one is consent ("you told us to stop"). One boolean cannot express that.
 *
 * Mirrors `AmbientDeliveryTier` in the Swift engine. The two must agree exactly.
 */
enum class AmbientDeliveryTier {
    /** Nothing at all. The owner's explicit instruction, not a volume dial. */
    SILENT,

    /** Visible, carrying no card advice: naming a card at an unidentifiable merchant is a
     * confident wrong answer, which costs trust faster than silence does. */
    PRESENCE,

    /** Visible and advisory, never audible. */
    CONFIRM,

    /** Sound, time-sensitive banner, Live Activity. Switching cards earns money here. */
    INTERRUPT
}
```

Then replace `AmbientGateDecision`:

```kotlin
data class AmbientGateDecision(
    val suppressionReasons: Set<AmbientSuppressionReason>
) {
    /**
     * Precedence: consent, then correctness, then volume. Ordered checks rather than a ranking,
     * so that adding a reason forces a decision about where it sits instead of defaulting into
     * the quietest tier by accident.
     */
    val tier: AmbientDeliveryTier
        get() = when {
            AmbientSuppressionReason.MERCHANT_MUTED in suppressionReasons ->
                AmbientDeliveryTier.SILENT
            AmbientSuppressionReason.MERCHANT_CONFIDENCE_LOW in suppressionReasons ->
                AmbientDeliveryTier.PRESENCE
            suppressionReasons.isEmpty() -> AmbientDeliveryTier.INTERRUPT
            else -> AmbientDeliveryTier.CONFIRM
        }

    /** Unchanged in meaning: PickMe interrupted. Not a statement about visibility. */
    val fires: Boolean get() = tier == AmbientDeliveryTier.INTERRUPT
}
```

- [x] **Step 4: Run the test to verify it passes**

Run: `cd android && ./gradlew :core:engine:test --tests "*AmbientGateTest*"`
Expected: PASS.

- [x] **Step 5: Run the full cross-language gate**

Run: `(cd Engine && swift test) && (cd android && ./gradlew :core:engine:test)`
Expected: PASS on both sides.

- [x] **Step 6: Commit**

```bash
git add android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/AmbientGate.kt android/core/engine/src/test/kotlin/com/cardcopilot/engine/AmbientGateTest.kt
git commit -m "feat(ambient): mirror the delivery tier in the Kotlin engine twin"
```

---

### Task 3: Teach the Live Activity to render a tier

**Files:**
- Modify: `App/CardCopilot/Services/CardCopilotActivityAttributes.swift`
- Modify: `App/CardCopilotWidgets/CardCopilotActivityAttributes.swift` (identical edit)
- Modify: `App/CardCopilotWidgets/CardCopilotLiveActivityView.swift`
- Modify: `App/CardCopilot/Views/CardCopilotLiveActivityView.swift`

**Interfaces:**
- Consumes: `AmbientDeliveryTier` from Task 1.
- Produces: `CardCopilotActivityAttributes.ContentState.tier: AmbientDeliveryTier` (defaulting to `.interrupt` so existing call sites compile unchanged), and a presence rendering that shows no card.

The two `CardCopilotActivityAttributes.swift` files are byte-identical duplicates and ActivityKit requires them to stay that way. Make the edit once and copy the file.

- [x] **Step 1: Add the tier to the content state**

In `App/CardCopilot/Services/CardCopilotActivityAttributes.swift`, add the import, the stored property, and the initialiser parameter:

```swift
import ActivityKit
import CardCopilotEngine
import Foundation
```

Inside `ContentState`, add after `isFork`:

```swift
        /// Which delivery tier produced this activity. The view needs it because a `presence`
        /// activity deliberately carries no card: it exists to say PickMe is here and to invite
        /// the owner to identify a merchant we could not resolve.
        public var tier: AmbientDeliveryTier
```

Add the parameter to `init`, defaulted so that every existing call site keeps compiling:

```swift
                    isFork: Bool = false,
                    tier: AmbientDeliveryTier = .interrupt,
                    timestamp: Date = Date()) {
```

and the assignment, after `self.isFork = isFork`:

```swift
            self.tier = tier
```

- [x] **Step 2: Copy the file to the widget target verbatim**

```bash
cp App/CardCopilot/Services/CardCopilotActivityAttributes.swift App/CardCopilotWidgets/CardCopilotActivityAttributes.swift
diff App/CardCopilot/Services/CardCopilotActivityAttributes.swift App/CardCopilotWidgets/CardCopilotActivityAttributes.swift && echo IDENTICAL
```

Expected: `IDENTICAL`.

- [x] **Step 3: Render the presence tier without a card**

`App/CardCopilot/Views/CardCopilotLiveActivityView.swift` and
`App/CardCopilotWidgets/CardCopilotLiveActivityView.swift` are also identical copies. Edit one and
copy it over the other.

In `lockScreenBanner`, replace the "Pay with" block (line 41-49 of the current file):

```swift
                HStack(spacing: 6) {
                    Text("Pay with")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(context.state.recommendedCardName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                }
```

with:

```swift
                // A `presence` state reached the Lock Screen precisely because the merchant could
                // not be identified. It carries no card, and must not invent one.
                if context.state.tier == .presence {
                    Text(String(localized: "ambient.activity.presence.body",
                                defaultValue: "Tap to tell PickMe which shop this is."))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    HStack(spacing: 6) {
                        Text("Pay with")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(context.state.recommendedCardName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.blue)
                    }
                }
```

The `multiplierHeadline` and `advantageDescription` blocks below it already guard on
`.isEmpty`, and `presentArrivalActivity` passes empty strings for the presence tier, so they
render nothing without further edits.

Add the engine import at the top of both view files, since `.presence` is an engine type:

```swift
import SwiftUI
import WidgetKit
import ActivityKit
import CardCopilotEngine
```

Then copy the file across:

```bash
cp App/CardCopilot/Views/CardCopilotLiveActivityView.swift App/CardCopilotWidgets/CardCopilotLiveActivityView.swift
diff App/CardCopilot/Views/CardCopilotLiveActivityView.swift App/CardCopilotWidgets/CardCopilotLiveActivityView.swift && echo IDENTICAL
```

Expected: `IDENTICAL`. (The widget extension already links `CardCopilotEngine` — `CapTrackerWidget.swift`, `QuickRecommendWidget.swift`, and `WhichCardAppIntent.swift` all import it — so no target configuration is needed.)

- [x] **Step 4: Build the app target**

```bash
xcrun simctl list devices available | grep -m1 iPhone
```

Take the UDID from that line, then:

```bash
cd App && xcodebuild build -project CardCopilot.xcodeproj -scheme CardCopilot -configuration Debug -destination "id=<simulator-udid>" CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED. Remember: never add `-sdk iphonesimulator`.

- [x] **Step 5: Commit**

```bash
git add App/CardCopilot/Services/CardCopilotActivityAttributes.swift App/CardCopilotWidgets/CardCopilotActivityAttributes.swift App/CardCopilotWidgets/CardCopilotLiveActivityView.swift App/CardCopilot/Views/CardCopilotLiveActivityView.swift
git commit -m "feat(ambient): render a presence Live Activity that names no card"
```

---

### Task 4: Make ActivityKit the source of truth for the current activity

**Files:**
- Modify: `App/CardCopilot/Services/LiveActivityManager.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `LiveActivityManager.endActivity(dismissalPolicy:)` and `startRecommendationActivity(...)` behave correctly after a process death.

**Why this is not optional.** `currentActivityId` is in-memory on a `@MainActor` singleton. iOS terminates the app between geofence wakes, so after a relaunch the property is `nil` while the real activity is still alive — the system owns it, not our process. `endActivity()` opens with `guard let currentActivityId else { return }` and returns immediately, orphaning the card on the Lock Screen; the next arrival then stacks a second card on top. Today that happens rarely. Once activities fire on every arrival, it is most Saturdays, and the failure mode is three stale PickMe cards — exactly the impression this work exists to prevent.

- [x] **Step 1: Replace the in-memory guards with a system lookup**

In `App/CardCopilot/Services/LiveActivityManager.swift`, replace `endActivity` with:

```swift
    /// Ends every activity this app owns, whether or not this process started it.
    ///
    /// `currentActivityId` cannot be trusted here: the entry wake and the exit wake are separate
    /// process launches, and ActivityKit — not this object — owns the activity across them. The
    /// previous in-memory guard returned early after a relaunch and orphaned the card.
    public func endActivity(dismissalPolicy: ActivityUIDismissalPolicy = .immediate) {
        currentActivityId = nil
        Task.detached {
            for activity in Activity<CardCopilotActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: dismissalPolicy)
            }
        }
    }
```

- [x] **Step 2: Fix the stacking guard in `startRecommendationActivity`**

Replace the early block:

```swift
        // End any existing activity first
        if currentActivityId != nil {
            endActivity()
        }
```

with:

```swift
        // Ask the system, not this object: after a background relaunch `currentActivityId` is nil
        // while a real activity is still on the Lock Screen, and trusting it stacks a second card.
        if !Activity<CardCopilotActivityAttributes>.activities.isEmpty {
            endActivity()
        }
```

- [x] **Step 3: Fix the same assumption in `updateActivity`**

Replace `guard let currentActivityId else { return }` and the detached lookup with a system-first lookup:

```swift
        Task.detached {
            guard let activity = Activity<CardCopilotActivityAttributes>.activities.first else { return }
            await activity.update(
                .init(state: updatedState, staleDate: Date().addingTimeInterval(15 * 60))
            )
        }
```

Delete the now-unused `guard let currentActivityId else { return }` line at the top of `updateActivity`.

- [x] **Step 4: Build the app target**

```bash
cd App && xcodebuild build -project CardCopilot.xcodeproj -scheme CardCopilot -configuration Debug -destination "id=<simulator-udid>" CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED, with no "unused variable" warnings from the removed guards.

- [ ] **Step 5: Verify manually in the simulator**

`Activity` cannot be constructed in a unit-test process, so this defect is verified by hand:

1. Run the app on a simulator (drop `CODE_SIGNING_ALLOWED=NO` for a runnable build — the flag strips entitlements and Keychain calls crash on the first frame).
2. Trigger an arrival so a Live Activity appears on the Lock Screen.
3. Terminate the app from Xcode. Confirm the Live Activity is still on the Lock Screen.
4. Relaunch and trigger a second arrival.
5. Expected: exactly **one** PickMe card on the Lock Screen, showing the second merchant. Before this fix there were two.

- [x] **Step 6: Commit**

```bash
git add App/CardCopilot/Services/LiveActivityManager.swift
git commit -m "fix(ambient): treat ActivityKit as the source of truth for live activities"
```

---

### Task 5: Remember that the owner dismissed a card

**Files:**
- Modify: `App/CardCopilot/Services/AmbientVisitStore.swift` (the `AmbientVisit` struct, line 10)
- Modify: `App/CardCopilot/Services/LiveActivityManager.swift`
- Test: `App/CardCopilotTests/AmbientVisitStoreTests.swift` (create)

**Interfaces:**
- Consumes: `AmbientVisitStore.update(regionId:_:)` (existing).
- Produces: `AmbientVisit.liveActivityDismissed: Bool`, `LiveActivityManager.visitKey: String?` (set by the caller when starting an activity), and `LiveActivityManager.onDismissal: (@MainActor (String) -> Void)?`, invoked with the visit key when the owner swipes the card away.

**Why it belongs in this piece.** Geofence re-entry is common at plaza boundaries: a region can fire entry, exit, and entry again during one shop. Without this flag, a card the owner just swiped away reappears on the next flap, which teaches them the swipe does not work — and the next thing they reach for is the Settings toggle we cannot undo. The payment loop in piece 2 reads the same flag.

**Known limitation, accept and do not work around.** A swipe reports `ActivityState.dismissed` while our own cleanup reports `.ended`, so the two are distinguishable — but only while this process is alive. If iOS terminated the app before the swipe, the dismissal is unobservable, because a dismissed activity simply disappears from `Activity.activities` exactly as an ended one does. The fallback is the more generous branch (treat it as absent), which is the right way to be wrong.

- [x] **Step 1: Write the failing test**

Create `App/CardCopilotTests/AmbientVisitStoreTests.swift`:

```swift
import XCTest
@testable import CardCopilot

@MainActor
final class AmbientVisitStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = UserDefaults(suiteName: "AmbientVisitStoreTests.\(UUID().uuidString)")!
        return suite
    }

    func testDismissalFlagSurvivesAWriteAndReadCycle() {
        let store = AmbientVisitStore(defaults: makeDefaults())
        store.begin(AmbientVisit(enteredAt: .now, didEngage: false, purchaseId: nil,
                                 merchantName: "Loblaws"),
                    forRegionId: "area.1")

        XCTAssertEqual(store.visit(forRegionId: "area.1")?.liveActivityDismissed, false)

        store.update(regionId: "area.1") { $0.liveActivityDismissed = true }

        XCTAssertEqual(store.visit(forRegionId: "area.1")?.liveActivityDismissed, true)
    }

    /// Visits written before this field existed must still decode. Synthesised `Codable` throws
    /// on a missing key even when the property has a default, so the flag needs an explicit
    /// `decodeIfPresent` — without it every in-flight visit is silently dropped on upgrade.
    func testVisitsWrittenBeforeTheFieldExistedStillDecode() throws {
        let defaults = makeDefaults()
        let legacy = """
        {"area.1":{"enteredAt":0,"didEngage":false,"merchantName":"Loblaws"}}
        """
        defaults.set(Data(legacy.utf8), forKey: "ambientVisits.v1")

        let store = AmbientVisitStore(defaults: defaults)
        let visit = try XCTUnwrap(store.visit(forRegionId: "area.1"))
        XCTAssertEqual(visit.merchantName, "Loblaws")
        XCTAssertFalse(visit.liveActivityDismissed)
    }
}
```

- [x] **Step 2: Run the test to verify it fails**

Run: `cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot -configuration Debug -destination "id=<simulator-udid>" CODE_SIGNING_ALLOWED=NO -only-testing:CardCopilotTests/AmbientVisitStoreTests`
Expected: FAIL — `value of type 'AmbientVisit' has no member 'liveActivityDismissed'`.

- [x] **Step 3: Add the field with a tolerant decoder**

In `App/CardCopilot/Services/AmbientVisitStore.swift`, add to `AmbientVisit` after `merchantName`:

```swift
    /// Whether the owner swiped this visit's Live Activity away.
    ///
    /// A swipe is the only "not now" the owner has that costs them nothing. Honouring it means
    /// not re-showing the card when a plaza geofence flaps, and — in the payment loop — not
    /// pushing a confirmation they already dismissed.
    var liveActivityDismissed: Bool = false

    init(enteredAt: Date, didEngage: Bool, purchaseId: UUID?, merchantName: String,
         liveActivityDismissed: Bool = false) {
        self.enteredAt = enteredAt
        self.didEngage = didEngage
        self.purchaseId = purchaseId
        self.merchantName = merchantName
        self.liveActivityDismissed = liveActivityDismissed
    }

    /// Written by hand rather than synthesised: synthesised `Codable` throws on a missing key
    /// even where the property has a default, so a visit stored before this field existed would
    /// fail to decode and `all()`'s `try?` would silently discard every in-flight visit.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enteredAt = try container.decode(Date.self, forKey: .enteredAt)
        didEngage = try container.decode(Bool.self, forKey: .didEngage)
        purchaseId = try container.decodeIfPresent(UUID.self, forKey: .purchaseId)
        merchantName = try container.decode(String.self, forKey: .merchantName)
        liveActivityDismissed = try container.decodeIfPresent(
            Bool.self, forKey: .liveActivityDismissed) ?? false
    }
```

- [x] **Step 4: Run the test to verify it passes**

Run: `cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot -configuration Debug -destination "id=<simulator-udid>" CODE_SIGNING_ALLOWED=NO -only-testing:CardCopilotTests/AmbientVisitStoreTests`
Expected: PASS, both tests.

- [x] **Step 5: Report dismissals from the Live Activity manager**

`App/CardCopilot/Services/LiveActivityManager.swift` imports only ActivityKit, Foundation, and
SwiftUI today. It gains an `AmbientDeliveryTier` parameter in this task, so add the engine import
first:

```swift
import ActivityKit
import CardCopilotEngine
import Foundation
import SwiftUI
```

Then add two stored properties after `currentActivityId`:

```swift
    /// The region whose visit owns the activity on screen, so a dismissal can be attributed.
    private var visitKey: String?

    /// Called on the main actor with the visit key when the owner swipes the card away.
    /// `AmbientLocationService` wires this to `AmbientVisitStore`.
    public var onDismissal: (@MainActor (String) -> Void)?
```

Add a `visitKey` parameter to `startRecommendationActivity` — place it last so existing call sites keep compiling:

```swift
                                           isFork: Bool = false,
                                           tier: AmbientDeliveryTier = .interrupt,
                                           visitKey: String? = nil) {
```

Pass `tier: tier` into the `ContentState` initialiser, and after the successful `Activity.request`, replace `currentActivityId = activity.id` with:

```swift
            currentActivityId = activity.id
            self.visitKey = visitKey
            observeDismissal(of: activity, visitKey: visitKey)
```

Add the observer method:

```swift
    /// A swipe reports `.dismissed`; our own `endActivity` reports `.ended`. Only the first is
    /// the owner saying "not now", so only the first is recorded.
    ///
    /// This can only observe a dismissal while the process is alive. If iOS terminated the app
    /// first, the activity simply disappears from `Activity.activities` exactly as an ended one
    /// does, and the dismissal is unobservable — callers must treat "no flag" as "unknown",
    /// never as "not dismissed".
    private func observeDismissal(of activity: Activity<CardCopilotActivityAttributes>,
                                  visitKey: String?) {
        guard let visitKey else { return }
        Task { [weak self] in
            for await state in activity.activityStateUpdates where state == .dismissed {
                await MainActor.run { self?.onDismissal?(visitKey) }
                return
            }
        }
    }
```

- [x] **Step 6: Build and re-run the app test suite**

Run: `cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot -configuration Debug -destination "id=<simulator-udid>" CODE_SIGNING_ALLOWED=NO`
Expected: PASS. Existing call sites compile unchanged because both new parameters are defaulted.

- [x] **Step 7: Commit**

```bash
git add App/CardCopilot/Services/AmbientVisitStore.swift App/CardCopilot/Services/LiveActivityManager.swift App/CardCopilotTests/AmbientVisitStoreTests.swift
git commit -m "feat(ambient): remember a dismissed live activity for the life of a visit"
```

---

### Task 6: Route arrivals by tier

**Files:**
- Modify: `App/CardCopilot/Services/AmbientLocationService.swift:712-732` (the tail of `evaluateArrival`) and `:838-908` (`scheduleArrivalNotification`)

**Interfaces:**
- Consumes: `AmbientGateDecision.tier` (Task 1), `ContentState.tier` (Task 3), `LiveActivityManager.onDismissal` and the `visitKey`/`tier` parameters (Tasks 3 and 5).
- Produces: no new public API. This is the task that actually changes what the owner sees.

Two structural points:

1. **The Live Activity moves out of the notification function.** It is currently started at the end of `scheduleArrivalNotification`, which is the entire reason presence and interruption are welded together.
2. **Where `diagnosticsStore.record(decision)` is called matters.** On the interrupt path it is deliberately called *after* iOS accepts the notification, so a "fired" count means the notification was actually enqueued rather than merely approved. Preserve that. On every other tier, record immediately.

- [x] **Step 1: Wire the dismissal callback**

In `AmbientLocationService`, in the same place the other stores are configured (near `private let visitStore = AmbientVisitStore()`, line 292 — put the assignment in whichever `start`/`configure` method already runs once on setup):

```swift
        LiveActivityManager.shared.onDismissal = { [weak self] regionId in
            self?.visitStore.update(regionId: regionId) { $0.liveActivityDismissed = true }
        }
```

- [x] **Step 2: Replace the fire/suppress guard with tier routing**

In `evaluateArrival`, replace this block:

```swift
        guard decision.fires else {
            diagnosticsStore.record(decision)
            return
        }

        do {
            try await scheduleArrivalNotification(arrival: arrival, recommendation: recommendation,
                                                  catalogue: catalogue, regionId: regionId)
            // A "fired" count now means iOS accepted the notification request, not merely that the
            // pure gate approved one that may have failed before reaching Notification Center.
            diagnosticsStore.record(decision)
        } catch {
            runtimeStore.recordIssue("Arrival advice was approved but could not be delivered: \(error.localizedDescription)")
        }
```

with:

```swift
        // The gate no longer decides whether PickMe is visible — only how loud it is. Silence is
        // now reserved for the one reason that is the owner's own instruction.
        switch decision.tier {
        case .silent:
            diagnosticsStore.record(decision)

        case .presence:
            // Deliberately no recommendation: the merchant could not be identified, and naming a
            // card here would be a confident wrong answer.
            presentArrivalActivity(tier: .presence, arrival: arrival, recommendation: nil,
                                   catalogue: catalogue, regionId: regionId)
            diagnosticsStore.record(decision)

        case .confirm:
            presentArrivalActivity(tier: .confirm, arrival: arrival, recommendation: recommendation,
                                   catalogue: catalogue, regionId: regionId)
            diagnosticsStore.record(decision)

        case .interrupt:
            do {
                try await scheduleArrivalNotification(arrival: arrival, recommendation: recommendation,
                                                      catalogue: catalogue, regionId: regionId)
                presentArrivalActivity(tier: .interrupt, arrival: arrival,
                                       recommendation: recommendation, catalogue: catalogue,
                                       regionId: regionId)
                // A "fired" count means iOS accepted the notification request, not merely that the
                // pure gate approved one that may have failed before reaching Notification Center.
                diagnosticsStore.record(decision)
            } catch {
                runtimeStore.recordIssue("Arrival advice was approved but could not be delivered: \(error.localizedDescription)")
            }
        }
```

- [x] **Step 3: Remove the Live Activity call from the notification function**

At the end of `scheduleArrivalNotification`, delete the whole trailing block beginning:

```swift
        // Start / refresh Live Activity on Lock Screen and Dynamic Island
        LiveActivityManager.shared.startRecommendationActivity(
```

through its closing parenthesis. That function now does one thing: enqueue a notification.

- [x] **Step 4: Add the presentation function**

Add to `AmbientLocationService`, next to `scheduleArrivalNotification`:

```swift
    /// Starts the Live Activity for an arrival at the tier the gate chose.
    ///
    /// Separate from `scheduleArrivalNotification` on purpose. Those two calls used to be one, so
    /// a single boolean decided both whether PickMe spoke and whether PickMe was visible — which
    /// is why the owner saw nothing on most arrivals.
    private func presentArrivalActivity(tier: AmbientDeliveryTier,
                                        arrival: ResolvedArrival,
                                        recommendation: Recommendation?,
                                        catalogue: Catalogue,
                                        regionId: String) {
        let meta = CategoryVisuals.meta(for: arrival.prediction.category)
        let merchant = notificationMerchantName(arrival.merchant.name)

        guard tier != .presence else {
            LiveActivityManager.shared.startRecommendationActivity(
                merchantName: merchant, merchantLocation: nil,
                cardName: "", cardId: "", multiplierHeadline: "",
                advantageDescription: "", categoryDisplayName: meta.displayName,
                categoryIcon: meta.icon, tier: .presence, visitKey: regionId)
            return
        }

        guard let recommendation,
              let card = catalogue.cards.first(where: { $0.cardId == recommendation.winner.cardId })
        else { return }

        let advantageCad = recommendation.advantageOverDefaultCad ?? 0
        let advantage: String
        switch tier {
        case .interrupt where advantageCad > 0.005:
            advantage = String(format: "+$%.2f vs default", advantageCad)
        case .confirm:
            // The answer is "stay on the card you were already going to use". Saying so plainly
            // is the whole point of this tier: it is reassurance, not a suppressed alert.
            advantage = String(localized: "ambient.activity.confirm.advantage",
                               defaultValue: "Already your best card here")
        default:
            advantage = String(localized: "ambient.activity.best.advantage",
                               defaultValue: "Best card here")
        }

        LiveActivityManager.shared.startRecommendationActivity(
            merchantName: merchant, merchantLocation: nil,
            cardName: Self.shortCardName(card), cardId: card.cardId,
            multiplierHeadline: rewardReason(card, recommendation),
            advantageDescription: advantage,
            categoryDisplayName: meta.displayName, categoryIcon: meta.icon,
            tier: tier, visitKey: regionId)
    }
```

- [ ] **Step 5: Build and run the full app suite**

Run: `cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot -configuration Debug -destination "id=<simulator-udid>" CODE_SIGNING_ALLOWED=NO`
Expected: PASS.

> **2026-09-01 note:** `xcodebuild build` SUCCEEDED with this change. The test suite could
> not be run: a concurrent session has the auth/config layer (`MoneyTalksSync.swift`,
> `CopilotEnvironment.swift`) mid-refactor, and the test host crashes at launch with
> `Clerk has not been configured`. Unrelated to this task. Re-run once the tree is clean.

- [ ] **Step 6: Commit**

```bash
git add App/CardCopilot/Services/AmbientLocationService.swift
git commit -m "feat(ambient): route arrivals by delivery tier instead of one fire flag"
```

---

### Task 7: Say what the owner now gets

**Files:**
- Modify: `App/CardCopilot/Views/AmbientLocationExplainerView.swift:373-392` (`AmbientSuppressionReason.ownerFacingDescription`)
- Modify: `TESTFLIGHT.md:182` and `TESTFLIGHT.md:30`
- Modify: `App/CardCopilot/Localizable.xcstrings` (regenerated by the build)

**Interfaces:**
- Consumes: `AmbientDeliveryTier` (Task 1).
- Produces: owner-facing copy that matches the shipped behaviour.

**Why this is a task and not a footnote.** `ownerFacingDescription` explains to the owner *why an arrival stayed silent*. Four of its six cases no longer mean silence. Left alone, the app explains an absence the owner just watched appear on their Lock Screen.

- [x] **Step 1: Rewrite the reason descriptions**

In `App/CardCopilot/Views/AmbientLocationExplainerView.swift`, replace the bodies inside `ownerFacingDescription`, and update its doc comment:

```swift
extension AmbientSuppressionReason {
    /// Why an arrival did not interrupt, in the owner's terms — and what they got instead.
    ///
    /// Deliberately names the cause rather than the rule: the counters exist to be acted on, and
    /// "advantageBelowUnverifiedThreshold" tells an owner nothing they can act on. Since the gate
    /// gained delivery tiers, only `merchantMuted` means the owner saw nothing at all; the rest
    /// describe an arrival that was visible without being audible.
    var ownerFacingDescription: String {
        switch self {
        case .merchantConfidenceLow:
            return String(localized: "ambient.suppressed.unrecognised",
                          defaultValue: "the store could not be identified, so PickMe showed up without naming a card")
        case .recommendedDefaultCard:
            return String(localized: "ambient.suppressed.already-best",
                          defaultValue: "your usual card was already the best one, so PickMe confirmed it quietly")
        case .advantageBelowSwitchThreshold:
            return String(localized: "ambient.suppressed.below-threshold",
                          defaultValue: "the gain was below your switch threshold, so PickMe confirmed your card quietly")
        case .advantageBelowUnverifiedThreshold:
            return String(localized: "ambient.suppressed.below-unverified",
                          defaultValue: "the gain was below the higher bar for unconfirmed stores, so PickMe confirmed your card quietly")
        case .advantageBelowFrequentedThreshold:
            return String(localized: "ambient.suppressed.below-frequented",
                          defaultValue: "the gain was below your switch threshold at a store you shop at often, so PickMe confirmed your card quietly")
        case .merchantMuted:
            return String(localized: "ambient.suppressed.muted",
                          defaultValue: "you muted that store, so PickMe stayed out of the way entirely")
        }
    }
}
```

- [x] **Step 2: Scope rule A3 in TESTFLIGHT.md**

Replace the table row at `TESTFLIGHT.md:182`:

```markdown
| **Ambient Firing Rule (A3)** | Governs *interruption*, not visibility. PickMe is visible on every arrival it can speak to; it interrupts only when advantage > threshold & confidence high & not muted. A muted store gets nothing at all. | Verify geofence pings fire at saved spots and do not spam; verify a default-card win still shows a silent Lock Screen card |
```

And amend the sentence at `TESTFLIGHT.md:30` so the tester gate matches:

```markdown
> Do not invite external testers until the owner has completed **30 physical checkouts** with the app, verified that ambient notifications *interrupt* according to Rule A3 (advantage > threshold, merchant confidence high, not muted) and that quieter arrivals still appear as silent Live Activities, and confirmed that the local SwiftData store maintains zero data-loss bugs.
```

- [ ] **Step 3: Build so the string catalogue picks up the new keys**

Run: `cd App && xcodebuild build -project CardCopilot.xcodeproj -scheme CardCopilot -configuration Debug -destination "id=<simulator-udid>" CODE_SIGNING_ALLOWED=NO`
Expected: BUILD SUCCEEDED. `Localizable.xcstrings` gains `ambient.activity.presence.title`, `ambient.activity.presence.body`, `ambient.activity.confirm.advantage`, `ambient.activity.best.advantage`, and the rewritten `ambient.suppressed.*` values.

> **2026-09-01 note:** BUILD SUCCEEDED. Incremental build did not re-extract the new
> `ambient.activity.*` keys into `Localizable.xcstrings`, and that file already carries
> unrelated concurrent-session edits, so it was left out of the Task 7 commit. The
> `String(localized:defaultValue:)` calls resolve at runtime without a catalogue entry;
> a clean build on a settled tree will backfill the keys for translation.

- [ ] **Step 4: Run the whole gate**

```bash
(cd Engine && swift test) && (cd android && ./gradlew :core:engine:test)
```

Then the app suite:

```bash
cd App && xcodebuild test -project CardCopilot.xcodeproj -scheme CardCopilot -configuration Debug -destination "id=<simulator-udid>" CODE_SIGNING_ALLOWED=NO
```

Expected: all PASS.

> **2026-09-01 note:** Cross-language engine gate PASSED (`swift test` + `:core:engine:test`).
> App suite blocked by the same `Clerk has not been configured` test-host crash from
> concurrent auth/config WIP — see Task 6 Step 5. Re-run once the tree is clean.

- [ ] **Step 5: Commit**

```bash
git add App/CardCopilot/Views/AmbientLocationExplainerView.swift App/CardCopilot/Localizable.xcstrings TESTFLIGHT.md
git commit -m "docs(ambient): scope A3 to interruption and say what quiet arrivals now show"
```

---

## Manual acceptance

Automated tests cover the gate in both languages and the visit store. ActivityKit cannot be exercised from a test process, so the delivered behaviour is confirmed by hand on a simulator with a runnable build (drop `CODE_SIGNING_ALLOWED=NO`; that flag strips entitlements and Keychain calls crash on the first frame).

Walk the four cases from the spec:

1. **Advantage clears threshold** → sound, time-sensitive banner, Live Activity naming the card.
2. **Default card wins** → silent Live Activity reading "Already your best card here". No banner, no sound.
3. **Unidentifiable merchant** → silent Live Activity reading "PickMe is here / Tap to tell PickMe which shop this is." **No card named.**
4. **Muted merchant** → nothing at all.

Then: swipe the card away at case 2, and force a region re-entry. Expected: it does not come back for that visit.

## Out of scope for this plan

- The payment loop (spec piece 2): the ✓ confirmation, the reachable success branch, the surfaced advantage figure, and the units rule.
- Notification hygiene and the monthly summary (spec piece 3).
- Dismissal-driven merchant muting — a swipe is a weak signal and an explicit mute already exists.
