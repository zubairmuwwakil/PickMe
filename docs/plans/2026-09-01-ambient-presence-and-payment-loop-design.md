# Ambient presence and the payment loop

**Status:** design agreed 2026-09-01. Not yet implemented.
**Supersedes:** the delivery half of rule A3 (`TESTFLIGHT.md:182`). The *firing* half
— when PickMe interrupts — is unchanged. What changes is that A3 stops being the
decision about whether PickMe is *visible* at all.

## Problem

PickMe is invisible on most arrivals. `AmbientGate` answers one boolean question —
notify or stay silent — and the Live Activity is started *inside*
`scheduleArrivalNotification`, so `guard decision.fires` gates presence and
interruption together. On a Saturday with four stops, the owner typically sees
PickMe once.

That is not a policy anyone chose. It is a consequence of where one call sits.

Separately, PickMe gives advice and never learns whether it was taken. Wallet
Capture receives real transactions and `WalletCaptureVerdictEvaluator` already
computes the counterfactual, but the success case is structurally unreachable and
the computed advantage is discarded before it reaches the owner.

## Goal

The owner sees PickMe at every arrival it can speak to, and PickMe interrupts only
when switching cards earns money. The advice loop closes visibly: advice →
payment → confirmation, in one place.

## The core move

`AmbientGate` stops answering *"fire or stay silent"* and starts answering
*"how should this arrival be delivered"*. The notification path and the Live
Activity path read different outputs of the same decision.

The information required already exists. `AmbientGateDecision` computes a `Set` of
distinct suppression reasons — deliberately, so the field-test counters stay
diagnostic — and then collapses them into one boolean that only the notification
path reads. This adds a second output; it does not loosen a threshold.

### Delivery tiers

| Reason present | Kind of reason | Tier | Owner sees |
|---|---|---|---|
| *(none)* | Switching earns money | `interrupt` | Notification (time-sensitive, sound) **+** Live Activity |
| `recommendedDefaultCard` | Volume — answer is "keep going" | `confirm` | Live Activity only, silent |
| `advantageBelowSwitchThreshold`<br>`advantageBelowUnverifiedThreshold`<br>`advantageBelowFrequentedThreshold` | Volume — answer is "not worth the swap" | `confirm` | Live Activity only, silent |
| `merchantConfidenceLow` | **Correctness** — we do not know the merchant | `presence` | Live Activity, no card advice, invites identification |
| `merchantMuted` | **Consent** — owner said stop | `silent` | Nothing |

Precedence when several reasons are present: `silent` > `presence` > `confirm` >
`interrupt`. Consent outranks everything; a correctness stop outranks a volume
judgement.

Two rows are load-bearing and must not be collapsed into the volume rows:

- **`merchantConfidenceLow` must never carry card advice.** Naming a card at a
  place we cannot identify is a confident wrong answer, which costs trust faster
  than silence. What the arrival honestly supports is presence plus an open
  question — and that tap is also the highest-value one in the app, because
  confirming a merchant promotes it up the confidence ladder and unlocks every
  future alert there.
- **`merchantMuted` means nothing at all.** Mute is the owner's explicit
  instruction. It is not a volume dial.

`fires` is retained as `tier == .interrupt` so existing callers and the
`SuppressionLog` counters keep their present meaning. The counters continue to
count suppressed *interruptions*, which is what the TestFlight gate reads.

### Why presence goes to the Live Activity and not to notifications

`ActivityAuthorizationInfo().areActivitiesEnabled` reads a different Settings
toggle than notification authorization. The two are not drawn from one budget.

Notification permission is a one-way ratchet: `requestAuthorization` presents the
system dialog once, and after a Settings-level denial it returns denied without
prompting. Recovery requires the owner to volunteer a trip through Settings.
Softer failures matter more in practice — Notification Summary batches alerts into
a digest hours later, which for "use this card now" is non-delivery that still
reports success; and learned blindness degrades the valuable alerts and the
reassuring ones together, because owners classify the *app*, not the message type.

A Live Activity asks nothing: no sound, no banner, no interruption. It can be
constant without becoming noise. It is also *forgiving* — an irritated owner
swipes, which costs one gesture, rather than reaching for a toggle we cannot undo.

**Ceiling, accepted:** iOS caps geofences at 20 regions, aimed at ~20 plazas
(`AmbientLocationService.swift:546`). Arrivals with no region slot never reach the
gate. This is presence at the owner's twenty regular places, which is what a
routine is.

## Live Activity lifecycle

Two defects must be fixed with this change, not after it. Both are rare today and
routine once activities fire on every arrival.

**Orphaned and stacked cards.** `LiveActivityManager` holds `currentActivityId` in
memory. iOS terminates the app between geofence wakes, so after a relaunch the
property is `nil` while the real activity is still alive — the system owns it, not
our process. `endActivity()` opens with `guard let currentActivityId else { return }`
and returns immediately, orphaning the card; the next arrival then stacks a second
card on top. Fix: treat `Activity<CardCopilotActivityAttributes>.activities` as the
source of truth. `updateActivity` and `endActivity` already perform that lookup —
they simply gate on the stale in-memory value first.

**Dismissal must be remembered across a process death.** A swipe reports
`ActivityState.dismissed`; our own cleanup on geofence exit reports `.ended`, so
the two are distinguishable via `activityStateUpdates`. The flag must be persisted
alongside the visit record (`visitStore` already persists the visit) — in-memory
state will not survive to the payment.

## The payment loop

Wallet Capture is the payment signal: a Shortcuts automation delivers merchant,
amount, and card as a `WalletCaptureEvent`.

### Where each outcome goes

| Outcome | Channel |
|---|---|
| Used the recommended card | Live Activity ✓ confirmation. No notification, ever. |
| Used another card, advantage clears threshold | **Notification** |
| Used another card, difference is trivial | Nothing |

The confirmation resolves against Live Activity state as follows:

| State at payment | Behaviour |
|---|---|
| Activity on screen | `updateActivity` in place → ✓ |
| No activity, none dismissed this visit (online, ungeofenced) | Start a fresh short activity → ✓ |
| Owner dismissed it during this visit | **Nothing pushed.** Lands in-app only. |

**Principle: importance decides the channel; availability never does.** The
tempting rule — quiet channel if present, loud channel if not — makes urgency a
function of screen state. A ✓ confirmation is the least urgent message in the
system: it asks nothing and changes nothing. It is never promoted to a
notification because a quiet surface was unavailable. Answering a swipe with a
louder channel teaches the owner the swipe does not work, and the next thing they
reach for is the toggle we cannot undo.

The regret notification is independent of all Live Activity state.

**Confirmation lifetime:** a couple of minutes, then self-dismiss. Long enough to
catch the eye while pocketing the phone; short enough that a normal Saturday never
leaves more than one PickMe card on the Lock Screen. (The recommendation card keeps
its present 15-minute stale window and exit-driven cleanup.)

### The regret notification fires in both situations

- **Advice ignored** — PickMe named a card at the door and another was tapped.
  Closes a loop the owner was part of and teaches that arrival alerts are worth
  reading.
- **PickMe never spoke** — online, outside the twenty geofences, or an
  unidentified pin. Decided in favour despite the scold risk: this is the case
  that teaches the owner to open PickMe *before* paying rather than only reacting
  to alerts, which is the habit that makes it routine.

### Units: state what the card actually pays in

Constrained by the locked valuation policy — point valuations are disclosed
assumptions, and statements can confirm points earned but never dollars realized.

- Cash-back card → **"$1.84 back"** (a fact)
- Points card → **"740 MR points"** (confirmable against a statement)
- Cross-card comparison → dollars **carrying the existing disclosure**:
  *"about $3.40 more — assumes MR at 1.80¢"*. `RecommendationExplainer` already
  writes sentences in this shape; reuse it rather than inventing a second voice.

Never render a dollar figure for points earned. That is a forecast about future
redemption presented as a receipt, on the screen most likely to be read literally.

**A confirmation is pending, not confirmed.** `valueRecovered` separates confirmed
(statement-checked) from pending. A message fired seconds after a tap is pending by
definition and must not graduate itself into the confirmed figure.

### Known coverage gap

Wallet Capture sees Apple Pay only, and only where the owner completed the
Shortcuts automation. Physical taps, online purchases outside Apple Pay, and
un-onboarded owners produce nothing. The payment loop is therefore an enhancement
to presence, never the mechanism that delivers it.

## Existing notification inventory

Eleven distinct notification types ship today. They share one permission.

| # | Type | Source | Verdict |
|---|---|---|---|
| 1 | Arrival alert | `AmbientLocationService` | **Keep.** The one that earns money. |
| 2 | Amount prompt on exit | `scheduleAmountPrompt` | Keep — review interaction with the new confirmation, which may already supply the amount. |
| 3 | Delivery test | `sendTestNotification` | Keep (owner-triggered). |
| 4 | Credit expiry, 7-day and 1-day | `CreditReminderScheduler` | Keep. Real money, real deadline. |
| 5 | Purchase received — saved securely | Wallet Capture | **Replace** with the payment-loop messages. |
| 6 | Purchase received — saved offline | Wallet Capture | **Replace** likewise. |
| 7 | Purchase saved on this iPhone | Wallet Capture | Keep — needs an owner action. |
| 8 | Wallet Capture needs attention | Wallet Capture | Keep — configuration is broken. |
| 9 | Purchase could not be saved | Wallet Capture | Keep — data loss risk. |
| 10 | Wallet Capture is up to date | `publishDrain` | **Cut.** Pure plumbing. |
| 11 | Reconnect / review a capture | `publishDrain` | Keep — needs an owner action. |

Row 10 is the clearest case: *"3 saved purchases synced"* reports PickMe's internal
state, asks nothing, and spends the same budget as the alert that earns money.
Rows 5 and 6 currently title as "Purchase received" — a sync-status message where a
value message belongs — and drop `WalletCaptureVerdict.advantageCad` on the floor
before it reaches the owner.

**Rule going forward: a notification must be about the owner's money or require
the owner's action. App-internal state belongs in the app.**

## Monthly summary

One notification a month: *"You recovered $47 with PickMe in August."*

Explicitly in scope per `docs/policies/product-boundaries.md` (A5), which sizes
PickMe at "one value-recovered figure, and a small monthly summary" with deep
analytics on the web hub. A weekly dashboard-style breakdown is **not** in scope.
Reports the confirmed figure, with pending shown separately if non-zero.

## Cross-language and documentation obligations

- `AmbientGate` has a Kotlin twin at
  `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/AmbientGate.kt`
  (`fires` at :52, dispatch at :127). The tier must land in both. The ambient gate
  is **not** represented in `engine-fixtures.json` — it is covered per-language, and
  only on the Swift side (`AmbientGateTests.swift`; the Kotlin twin has no test at
  all today). Rather than open a new fixture section for one enum, this work follows
  the existing convention and adds the missing Kotlin test alongside the Swift one,
  with the same cases in the same order so the twins are readable against each other.
- Gate: `(cd Engine && swift test) && (cd android && ./gradlew :core:engine:test)`
- `AmbientSuppressionReason.ownerFacingDescription`
  (`AmbientLocationExplainerView.swift:373`) tells the owner why an arrival stayed
  silent. Four of six reasons no longer mean silence; the copy must say what the
  owner *got* instead.
- `TESTFLIGHT.md:182` records A3 as a ratified pass criterion. Amend to state that
  A3 governs interruption, not visibility.
- Localizable.xcstrings: new keys for every tier's copy.

## Testing

- Engine, both languages: one case per suppression reason → expected tier;
  precedence when reasons combine; `fires == (tier == .interrupt)` preserved.
- `SuppressionLog` continues to count suppressed interruptions unchanged.
- Live activity: relaunch with a system-live activity and no in-memory id → no
  orphan, no stack. Dismissal survives a simulated process death.
- Payment loop: winner-used → confirmation, no notification; dismissed-this-visit
  → nothing pushed; regret both when advised and when never advised.
- Units: points card never renders a dollar figure for points earned.

## Sequencing

Three independently shippable pieces. Piece 2 depends on piece 1's lifecycle fixes;
piece 3 depends on neither.

1. **Presence** — the delivery tier in both twins, fixtures, the Live Activity
   lifecycle fixes, explainer copy, `TESTFLIGHT.md`. Ships the whole "PickMe is
   there at every arrival" outcome on its own.
2. **Payment loop** — confirmation update, the reachable success branch, the
   advantage figure surfaced, units rule.
3. **Notification hygiene** — the inventory cull and the monthly summary.

## Out of scope

- Dismissal-driven learning (repeated swipes muting a merchant). A swipe is a weak
  signal and an explicit mute already exists. Revisit only if the owner observes
  themselves swiping the same store repeatedly.
- Raising the 20-region geofence budget.
- Any weekly analytics surface (A5).
- Watch and widget presence — the Live Activity may surface on the Watch Smart
  Stack for free, but nothing here depends on it.
