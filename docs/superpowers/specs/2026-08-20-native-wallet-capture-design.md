# Native Apple Wallet Capture Design

**Status:** Approved 2026-08-20 after written-spec review. Five forks ratified in review (§0).
**Products:** PickMe (native bridge, on-device verdict, capture status), Inunity (capture system of record)
**Repositories:** `PickMe`, `MoneyTalks`
**Delivery:** One throwaway Apple-boundary spike (§6) to settle parameter coercion, then direct full implementation. No feature flag, no staged rollout, no production path that gets thrown away. Automated verification is part of implementation, followed by one real-device Wallet check.

## 0. Review rulings (2026-08-20)

This section records what the written-spec review changed. It is the diff against the pre-review draft; the body below already reflects it.

| # | Fork | Ruling |
|---|---|---|
| R1 | Where the transactions/corrections UI lives | **Capture status + deep-link only.** PickMe does not gain a recent-purchases read API or native correction controls. Corrections stay on the hub's `/purchases`, which already ships them. |
| R2 | App Intent host | **Main app target**, not a dedicated App Intent extension. |
| R3 | Apple-boundary risk | **Spike first.** A stub intent proves Shortcuts→App-Intent parameter coercion before the schema is committed. |
| R4 | Amount representation | **Both.** Raw Apple text for provenance plus a device-parsed decimal; the server prefers the decimal and flags disagreement. |
| R5 | Better-card verdict | **On-device, with the server verdict as refinement.** PickMe computes and shows it immediately; Inunity's cap-aware verdict wins on the stored record when they disagree. |

### Supersessions

This design deliberately changes two previously ratified rulings. Both are called out here so `LOG.md` can record the supersession rather than discover a silent drift.

- **`LOG.md` 2026-08-17 — "Shortcut stays a dumb transport."** Superseded for the native path only. A dumb transport cannot retain an offline purchase, and retention is the point of this work. The other half of that ruling — *complete-record capture, server absorbs serialization quirks* — is preserved and strengthened: raw Apple strings are still stored untouched and still normalized server-side.
- **`LOG.md` 2026-08-17 — poison-file rule ("delete queued files on any 4xx").** Superseded by §10: a `4xx` now quarantines rather than deletes. Deleting the file destroys the only evidence of a malformed capture. Quarantine keeps the outbox unblocked without discarding the record. The server's existing `final: true` flag remains the classification signal.

### Explicitly NOT changed

- Cross-source dedup keeps the ratified rule (`LOG.md` 2026-08-17: amount + 72h window + merchant-compatible → enrich; amount+time alone → flag, never silent merge) and the implemented ±60s same-source fuzzy check in `wallet-events/route.ts`. The pre-review draft's bespoke 15-second rule is deleted — a schema 2 event is the same observation over a new transport, not a new source. See §13.
- The purchase list keeps source badges (`LOG.md` 2026-08-17). The pre-review draft removed them; that was out of scope for this work and is reverted.

## 1. Summary

Replace the user-maintained Wallet Capture V2 shortcut with a dedicated PickMe App Intent named **Send Wallet Purchase to Inunity**, declared in the main PickMe app target.

The user still creates Apple's Personal Automation and maps the properties Apple exposes in the Transaction editor (§6). Everything after that mapping moves into maintained native code: event identity, durable local persistence, optional location, device-locale amount decoding, the immediate better-card verdict, authentication, upload, retries, notifications, and diagnostics.

PickMe remains independently useful as the offline card-recommendation product — and under R5 the highest-value moment of the whole flow, the better-card warning, now works with no network at all. Inunity remains the owner of Apple Wallet capture, the purchase spine, transaction history, normalization, reconciliation, corrections, and cross-product intelligence. PickMe hosts the bridge because it is the installed native iPhone product and because it already owns card-decision semantics.

## 2. Goals

- Reduce the Personal Automation to one parameterized app action.
- Persist every meaningful Wallet trigger before attempting optional enrichment or networking.
- Keep offline events indefinitely until Inunity accepts them or the user explicitly removes them.
- Ensure one failed event never blocks another — locally *and* in the server's normalization queue.
- Deliver the better-card verdict from on-device state, so it survives being offline.
- Normalize the newly accepted event in real time so it appears on the hub's purchase screen within seconds.
- Keep ordinary captured purchases frictionless; receipt or statement reconciliation is optional enhancement, not required work.
- Make capture health and failure stages understandable to the user.
- Preserve raw observations while allowing corrections, declines, duplicate resolution, reversals, and permanent deletion — on the hub, where those controls already live.
- Maintain Wallet Capture V2 server compatibility during migration.
- Preserve the boundary that Inunity owns capture and PickMe owns card-decision semantics.
- Land the capture library where CI can test it (§5).

## 3. Non-goals

- Creating, enabling, inspecting, or editing Apple's Personal Automation programmatically.
- Reading Apple Wallet history.
- Determining authorization, decline, or settlement status from Apple when Apple does not expose it.
- Bank aggregation or FinanceKit access.
- Performing merchant normalization, categorization, card resolution, cap-ledger accrual, deduplication, or analytics inside the App Intent. (Decoding a locale-formatted number is not normalization — see §7.)
- A recent-transactions list or correction controls inside PickMe (R1). Deep-link to the hub.
- Requiring users to reconcile every purchase against a statement.
- Collecting device identifiers, network names, battery state, IP-derived location, or unrelated telemetry.

## 4. Product ownership and trust boundaries

### PickMe

- Provides offline card recommendations whether or not the user connects Inunity.
- Ships the native App Intent bridge and the shared capture library.
- **Computes the current-event better-card verdict on-device** from the catalogue, `CategoryMapper`, `MerchantProvider`, and the account's owner state, including synced cap usage (R5).
- Holds unsent events in a protected App Group outbox.
- Holds one write-only, installation-scoped Inunity credential in a device-only Keychain item.
- Shows capture status, local diagnostics, and the recent capture-outcome list it already renders in `SyncCenterView`.
- Deep-links to the hub for transaction history and every correction (R1).
- Uses normal signed-in access only for owner-state and cap sync. The capture credential cannot read account data.

### Inunity

- Authenticates the installation credential.
- Durably stores raw Wallet observations, the device-decoded amount, and precise location when supplied.
- Normalizes and promotes observations into the purchase spine.
- Owns transaction status, cross-source matching, corrections, rewards/cap effects, and reconciliation.
- Computes the cap-aware refinement verdict and returns explicit upload dispositions.
- Owns the transactions experience at `/purchases`, including every correction control in §14.

### Apple

- Owns the Wallet Transaction trigger and Personal Automation.
- Supplies the mapped Wallet properties, as a typed entity graph rather than flat strings (§6).
- May trigger on a tap that is later declined and does not provide a documented approval/decline flag to this integration.

## 5. Native architecture

**The intent is declared in the main PickMe app target** (R2). iOS background-launches the app to run it. This was chosen over a dedicated App Intent extension for three reasons:

1. **Location.** `AmbientLocationService` already holds `.authorizedAlways` with `allowsBackgroundLocationUpdates = true` in the app target. An app extension cannot declare those background modes, so an extension is the worst possible host for §8's location step.
2. **Concurrency.** The cross-process claim protocol in §9 existed only to coordinate an extension with the app. One process reduces it to crash recovery.
3. **Capacity.** The on-device verdict loads `card-catalogue.json` and the engine. Extension memory limits make that fragile.

**The capture library is a new `CardCopilotCapture` target inside the existing `Store` package**, alongside `CardCopilotStore` and depending on `CardCopilotEngine`. This is not a stylistic choice: `.github/workflows/ci.yml` runs `swift test` against `Engine` and `Store` only and **never builds the `App/` target**. Logic that lands in `App/` cannot be covered by §20's verification list. Adding a target to `Store/Package.swift` picks up CI with no workflow change. `App/` keeps only thin platform glue — the intent declaration, permission prompts, and SwiftUI.

Components:

| Component | Responsibility | Lives in |
|---|---|---|
| `WalletCaptureIntent` | Declares the mapped optional parameters (§6) and hands them to the capture coordinator. | `App/` |
| `WalletCaptureCoordinator` | Generates metadata, decodes the amount, persists first, requests optional location, computes the on-device verdict, drains the queue. | `CardCopilotCapture` |
| `WalletOutboxStore` | Atomic files, claims, stale-claim recovery, quarantine, and queue inspection. | `CardCopilotCapture` |
| `WalletAmountDecoder` | Device-locale decimal decoding with raw text preserved (§7). | `CardCopilotCapture` |
| `WalletCaptureVerdict` | On-device better-card verdict from catalogue + owner state + synced caps (R5). | `CardCopilotCapture` |
| `WalletCaptureCredentialStore` | Device-only Keychain installation credential and account-binding metadata. | `CardCopilotCapture` |
| `WalletLocationEnricher` | Best-effort fresh location with a short budget; never gates capture. | `CardCopilotCapture` |
| `WalletCaptureUploader` | Schema 2 request construction, explicit response classification, independent per-event attempts. | `CardCopilotCapture` |
| `WalletCaptureDiagnosticsStore` | Safe event timelines and redacted support-report generation. | `CardCopilotCapture` |
| `WalletCaptureNotificationCoordinator` | Aggregated offline/auth/problem notifications and current-event feedback. | `App/` |
| `CaptureStatusView` | Setup, permissions, connection state, queue inspection, retry, diagnostics, disable, relinking. | `App/` |

**Naming:** the status surface is `CaptureStatusView`, **not** "Wallet Health". `WalletHealthView.swift` already exists and means something entirely different — portfolio keep/cancel analysis. Reusing that name would be a permanent source of confusion. `CaptureStatusView` extends the existing `SyncCenterView`, which already performs sign-in, installation-token creation, sync-issue display, and recent capture feedback; it is not a greenfield screen.

The existing App Group `group.ca.inunity.pickme` remains the shared filesystem boundary for widgets. With R2 there is no second process for capture, so no new Keychain access group is required.

## 6. Personal Automation contract, and the spike that settles it

The user creates one Transaction automation per selected Wallet card, chooses Run Immediately, and maps:

```text
Send Wallet Purchase to Inunity
Merchant        <- Merchant
Amount          <- Amount
Name            <- Name
Currency        <- Currency Code
Card            <- Card or Pass
Payment Method  <- Payment Method > Name      (candidate, see below)
```

**Five confirmed properties plus one candidate.** Field inventory observed on-device 2026-08-20: the Wallet trigger's input can be cast in Shortcuts to a typed `Payment Method` entity carrying its own `Name` sub-property, distinct from the transaction's `Name` and from `Card or Pass`. The transaction is an object graph, not five flat strings, so the spike must enumerate the graph rather than assume the five leaves this design started from.

**What is already proven:** the Wallet trigger itself. `MoneyTalks/docs/plans/2026-08-16-wallet-capture-spec.md` records that the automation was manually tested and the trigger exposes transaction fields cleanly.

**What is not proven:** Shortcuts→App-Intent *parameter coercion*. Passing a Shortcuts variable into a typed App Intent parameter is a different mechanism from reading it inside a shortcut, and §7's entire schema depends on what actually arrives.

**Spike (R3), before any schema is committed:** a throwaway intent with one optional `String` parameter per mapped property that writes one JSON file to disk and does nothing else. Run it from a real Wallet tap on a real device. Record verbatim what each parameter receives. This costs an afternoon and is a probe, not a staged rollout — nothing it produces ships.

The spike must answer:

- What does each parameter actually contain, byte for byte?
- Does `Amount` arrive as a localized string, a plain number, or a currency-typed value? If a numeric or currency parameter type coerces cleanly, prefer it and keep the raw string alongside (§7).
- What arrives when a field is genuinely absent — `nil`, empty string, or a localized placeholder?
- Does the intent get enough runtime for the §8 sequence, and does a location fix arrive at all in a background launch?
- **Does `Payment Method > Name` carry a string distinct from both `Card or Pass` and the transaction's `Name`?** If yes it is a second independent card-resolution signal and becomes a sixth parameter. If it equals the transaction's `Name`, the entity binding silently fell back and the value is worthless — the two render as identical `Name` chips in the Shortcuts editor, so this is undetectable without inspecting a real payload.
- What else hangs off the transaction entity that this design has not enumerated?

Start from optional text parameters and tighten only where the spike proves a stronger type is safe. Do not require the whole private Wallet transaction object.

## 7. Schema 2 capture contract

```json
{
  "schemaVersion": 2,
  "captureVersion": 1,
  "source": "apple_wallet_automation",
  "transport": "pickme_app_intent",
  "eventId": "UUID",
  "capturedAt": "ISO-8601 with offset",
  "timezone": "America/Toronto",
  "transaction": {
    "merchantRaw": "Apple-supplied text or null",
    "transactionNameRaw": "Apple-supplied text or null",
    "amountRaw": "localized Apple-supplied text or null",
    "amountDecimal": "6.42",
    "amountDecodeStatus": "decoded | undecodable | absent",
    "currencyRaw": "Apple-supplied code or null",
    "cardRaw": "Apple-supplied text or null",
    "paymentMethodRaw": "Apple-supplied text or null"
  },
  "location": {
    "latitude": 43.0,
    "longitude": -79.0,
    "horizontalAccuracyMeters": 20.0,
    "capturedAt": "ISO-8601 with offset"
  },
  "client": {
    "appVersion": "1.0",
    "buildNumber": "1",
    "osVersion": "iOS 26.0",
    "locale": "en_CA"
  }
}
```

Rules:

- Preserve all Wallet values exactly. Semantic normalization — merchant identity, card resolution, category, rewards, caps — happens only on the server.
- **Amount is the one exception, and deliberately so (R4).** Decoding "1 234,56 $" into a decimal is mechanical locale decoding, not semantic normalization, and only the device knows the locale that produced the string. `Decimal(string:locale:)` on-device is exact; the server's `capturePayload.ts` heuristic is a guess that silently reads de-DE `"1.234"` as `1.23`. So the client sends **both**: `amountRaw` for provenance and `amountDecimal` for correctness.
- The server prefers `amountDecimal` when present, falls back to parsing `amountRaw`, and **records a flag when its own parse of `amountRaw` disagrees with `amountDecimal`**. Disagreement is a signal worth keeping, not an error to suppress.
- `amountDecodeStatus` distinguishes "Apple gave nothing" from "Apple gave something we could not decode". Only the second is a defect.
- All Wallet fields are individually optional at runtime.
- `paymentMethodRaw` is a raw observation and **never replaces `cardRaw`**. It exists because card resolution is a hard gate on the product's most valuable output: `wallet-events/route.ts` computes a verdict only when `cardAlias` resolves, and `cardAlias` is an exact-string lookup on `cardRaw`. An unresolved card produces no warning at all rather than a wrong one, so a second independent card signal is insurance against a silent failure. Capture it even before the server reads it — an uncaptured field is unrecoverable for every past transaction, while an ignored one costs a nullable column.
- A meaningful incomplete event uploads for later correction.
- If every Wallet field is empty, retain it locally as an automation-configuration error, do not promote it as a purchase, and notify the user.
- Missing location never delays or loses a capture.
- `source` describes where the observation originated; `transport` describes how it reached Inunity.
- Do not include a user ID, device identifier, network name, or secret. The installation credential determines the destination account.
- Inunity retains the raw payload alongside interpreted values.

**Schema 1 is already forward-compatible with extra keys — verified 2026-08-20.** `capturePayload.ts:43` uses a plain `z.object({...})`, which strips unknown keys rather than rejecting them, and `route.ts` persists `rawPayload: rawBody` verbatim. A sixth dictionary key added to the existing V2 automation today therefore cannot produce a `4xx` — which matters, because under the ratified poison-file rule a `4xx` deletes the queued file — and its value is durably retained for a later parser to read. New fields can be captured before the server understands them. This holds only if the V2 shortcut nests the received dictionary wholesale; if it re-reads named keys and rebuilds the payload, extra keys are dropped before the POST.

Note for the server: schema 1's parser requires `merchantRaw` and reads `transaction.amount`. Schema 2 makes merchant optional and renames the amount fields. Both shapes must decode, and the schema 2 relaxation interacts with a live normalization defect — see §12.

Actionable incompleteness means merchant and name are both absent, the amount is absent or `undecodable`, card is absent, several mapped values are unexpectedly empty, or the mapping appears entirely broken. Missing location, or a missing name when merchant exists, is diagnostic information without an interruption.

## 8. Persist-before-enrichment flow

1. Receive the mapped Wallet fields.
2. Generate `eventId`, `capturedAt`, timezone, source/transport versions, and client diagnostics.
3. Decode the amount with the device locale; keep the raw string regardless of outcome.
4. Build the minimal event without location.
5. Atomically persist it to `pending`.
6. If persistence fails, show a prominent **Purchase could not be saved** notification/result and retain a safe local diagnostic if possible.
7. Compute the on-device verdict (§12a) from local state. This requires no network and must not be gated on one.
8. Request a location for at most two seconds. Accept only a valid fix whose timestamp is no more than 60 seconds old.
9. If location succeeds, atomically replace the queued payload with coordinates, accuracy, and the location timestamp. Record accuracy but do not reject an otherwise valid fresh fix solely for being imprecise; Inunity decides how much evidentiary weight it deserves.
10. If location fails or is unavailable, record the safe reason and continue with the minimal event.
11. Attempt the current event first, then independently attempt older pending events.

Omit the `location` object entirely when no acceptable fix exists. Never attach a later location to an old purchase because a later coordinate may no longer represent the purchase location.

**Location expectations.** The 2-second budget combined with the 60-second freshness rule is strict by design, and the spike must measure how often it actually yields a fix in a background launch. The app target's existing `.authorizedAlways` grant and warm ambient fixes make success plausible; if the spike shows the yield is near zero, the honest response is to widen the freshness window with the fix age recorded — never to silently accept a stale coordinate as if it were fresh.

## 9. Durable outbox and concurrency

Directory structure:

```text
WalletCapture/
  pending/
  inflight/
  unassigned/
  quarantined/
  diagnostics/
```

Requirements:

- Write a temporary file and atomically rename it into `pending`.
- Claim an event by atomically moving it from `pending` to `inflight`.
- **Under R2 there is one capture process, so claiming exists for crash safety and re-entrancy, not cross-process arbitration.** Keep the atomic moves — they are cheap and they are what makes an interrupted background launch recoverable — but do not build a distributed-claim protocol for a problem that no longer exists.
- Recover stale `inflight` files to `pending` after interrupted execution.
- Store account-mismatch events in `unassigned`; they are never upload candidates until the user explicitly assigns them.
- Serialize each drain, but catch failures per event and continue with other files.
- Server idempotency is the final defense against duplicate upload after a crash or ambiguous response.
- Keep events indefinitely; there is no age-based expiry.
- Exclude transient outbox files from device backups and use iOS data protection.
- Background tasks are opportunistic only and never required for correctness.

Retry opportunities:

- Every new Wallet trigger.
- PickMe launch or foreground.
- Manual **Retry now**.
- Connectivity restoration when iOS gives PickMe execution time.
- Opportunistic background execution.

Attempt each event at most once per drain. Respect a valid server `Retry-After` value for `429`; do not run an in-process retry loop.

Local-only delivery metadata includes delivery state, creation time, attempt count, last attempt, safe error category/message, and next retry opportunity.

## 10. Delivery dispositions

Inunity returns a structured disposition. The client does not infer deletion from arbitrary text or the mere presence of an HTTP response.

| Disposition | Local action |
|---|---|
| `accepted` | Delete the local event after durable server ownership is confirmed. |
| `duplicate` | Delete locally and let Inunity link the observation to the existing purchase. |
| `authenticationRequired` | Retain and mark the queue authentication-blocked. |
| `retry` | Return to `pending`; covers network failure, timeout, `429`, and `5xx`. |
| `invalid` | Move to `quarantined`, preserve diagnostics, and request user attention. |
| Unexpected/undecodable response | Retain and record a safe diagnostic. |

`invalid` quarantining supersedes the ratified poison-file rule; see §0. The outbox stays unblocked either way — the difference is that the evidence survives.

Once Inunity durably stores an event, later normalization failure is server-owned. The iPhone may delete its local file on `accepted`; Inunity retries normalization without asking the device to resend.

## 11. Independent state machines

Do not overload one status field with transport and financial meaning.

```text
Delivery state:
pending -> inflight -> accepted
                   -> authenticationBlocked
                   -> quarantined

Financial state:
captured -> normalized -> reconciled
         -> declined
normalized -> adjusted
           -> declined
           -> reversed
reconciled -> adjusted
           -> reversed
```

- Delivery state is local transport health.
- Financial state belongs to Inunity's observation/purchase model.
- `normalized` means displayable and usable, not issuer-settled.
- A decline never became an authorization; a reversal undoes an authorization. Keep them distinct.

## 12. Inunity ingestion and real-time normalization

- Continue accepting schema 1 Wallet Capture V2 payloads.
- Accept schema 2 App Intent payloads through the same installation-scoped security boundary.
- Keep event ID uniqueness for exact retry idempotency.
- Durably insert the raw event before enrichment.
- Prefer `amountDecimal`; fall back to parsing `amountRaw`; flag disagreement (§7).
- **Replace the request-time global batch with `processWalletEvent(eventId)`.** Today `wallet-events/route.ts:179` calls `processWalletEvents()` synchronously inside every capture request, and that function selects `processingStatus: "OBSERVED"` with `take: 100` **across all users**. One user's Wallet tap therefore performs up to 100 events of work spanning other tenants, inside their latency budget.
- **Fix the head-of-line jam at the same time, and treat it as the primary reason for this change rather than a side benefit.** `walletNormalization.ts:16` does `if (!event.merchantRaw) continue;` **without changing the status**. Schema 2 explicitly permits merchant-null uploads (§7), so those rows accumulate as permanent `OBSERVED`. Once 100 of them exist anywhere in the system, the `take: 100` window fills with rows that are skipped forever and **no new event normalizes again, for any user**. Every event the batch touches must reach a terminal or explicitly blocked status; none may be skipped in place. This needs its own regression test — 100 merchant-null events, then assert a new event still normalizes.
- Keep the hourly batch as repair machinery for pending server work, with the same no-skip-in-place rule.
- Immediately create or enrich the canonical `Purchase` when enough information exists.
- Promote meaningful incomplete events with explicit missing fields rather than leaving them invisible forever.
- Compute the cap-aware refinement verdict after targeted normalization; degrade to `unknown` without delaying durable acceptance.
- Return the real-time normalization state and the refinement verdict in the response.
- Expose authenticated correction commands for declined/not-completed, duplicate, field correction, refund/reversal, Undo where safe, and permanent deletion, revalidating purchase ownership server-side. These serve `/purchases`; under R1 PickMe does not call them.

Ordinary accepted purchases appear on the hub's purchase screen within seconds. Source badges on purchase rows stay as ratified; source provenance in transaction detail also stays.

### 12a. Where the verdict is computed (R5)

The better-card verdict is computed **on-device, immediately, from local state**, and shown without waiting for the network. Inunity still computes its own verdict and stores it on the event; when the two disagree, **the server's wins on the stored record** because it sees the true cap ledger.

The reasoning:

- **It works offline.** The server-only design could never warn on an offline capture, since §16 also forbids replaying old feedback as current-purchase feedback. The outbox exists precisely for the offline case, and that is exactly where the warning silently vanished.
- **It is more accurate at capture time, not less.** The hub's synchronous verdict runs with `category: "unknown"` and only when `currency === "CAD"`, falling back to base earn. PickMe has `CategoryMapper` and `MerchantProvider` locally and can resolve a category the server does not yet have.
- **It is the ratified ownership boundary.** `CLAUDE.md` makes this engine the canonical owner of all card-decision semantics.

The honest cost: on-device cap usage is only as fresh as the last `SpineCap` sync, so a card near a cap ceiling can produce a verdict the server later revises. That is why the server verdict is retained as the refinement and why the stored record defers to it. Do not surface a second, contradicting notification when the refinement disagrees — update the event record and let the hub's transaction detail show the final answer.

PickMe refreshes owner state and cap usage on sign-in, foreground, and manual refresh.

## 13. Deduplication

### Exact retry

The same `eventId` always resolves to the existing observation and never creates a second purchase or cap accrual.

### Migration overlap and cross-source matching

**Schema 2 events use the existing dedup machinery unchanged.** A schema 2 event is the same Apple Wallet observation arriving over a new transport, not a new evidence source, so it needs no bespoke rule:

- the implemented same-source fuzzy check (`wallet-events/route.ts:62`: same user, card, merchant, amount within ±60s → `POSSIBLE_DUPLICATE`) already covers old-Shortcut/new-intent overlap during migration;
- the ratified cross-source merge (amount + 72h window + merchant-compatible → enrich; amount + time alone → `possibleDuplicateOfId` flag, never a silent merge) already covers receipt and statement evidence.

Both raw observations are preserved, both link to one canonical purchase, rewards and caps accrue once, and one purchase displays. The pre-review draft's separate 15-second rule is deleted — it would have been a fourth dedup window with different semantics from the three that already exist.

### Same-source rapid attempts

Do not silently merge same-source events; two fast purchases can be legitimate. The existing `POSSIBLE_DUPLICATE` flag plus user-confirmed resolution on the purchase page (ratified 2026-08-17) is the mechanism. Stronger receipt/statement evidence may resolve them automatically.

## 14. Purchase UX and corrections

**These controls live on the hub's `/purchases`, which already implements them (R1).** PickMe deep-links here and adds nothing of its own.

New Wallet captures appear immediately as ordinary purchases. The user is not asked to reconcile them. Receipt or statement evidence silently strengthens or adjusts them when available.

Transaction details expose:

- **Payment didn't complete**: mark `DECLINED`, hide from the default purchase list, and reverse provisional rewards/cap effects.
- **This is a duplicate**: link/merge observations and prevent double counting.
- **Edit details**: store corrected merchant, amount, currency, or card separately from Apple's raw values and recalculate affected results.
- **Refunded/reversed**: retain history and apply the appropriate reversal.
- **Delete permanently**: explicitly erase the purchase and underlying capture under account privacy/deletion rules.

Support Undo where technically safe. Normal removal retains the raw observation for diagnostics; permanent deletion is a separate explicit action.

## 15. Authentication and account binding

- Store a write-only installation token in a non-synchronizing, device-only Keychain item.
- The token remains active when the user signs out of PickMe.
- Signing out stops signed-in reads and owner-state sync but does not stop capture. Note that on-device verdicts degrade as cap data goes stale while signed out.
- Wallet Capture has its own explicit enabled/disabled state.
- The installation credential is bound to the Inunity account that enabled it.
- Signing into a different account pauses capture and requires an explicit relink decision.
- Events received during an account mismatch remain locally unassigned and are never silently sent to either account.
- Relinking requires the user to choose which account, if any, receives unassigned events.
- Account deletion revokes capture and deletes unsent events because no valid destination remains.

Disabling with pending events offers:

- **Send then disable**;
- **Delete unsent events and disable**;
- **Cancel**.

Never silently discard pending purchases.

## 16. Notifications

Request notification permission in context during Wallet Capture setup. If notifications are denied, preserve durable capture status and return a concise App Intent result where possible.

| Outcome | Notification behaviour |
|---|---|
| Ordinary online success | Silent. |
| Current-event better-card warning | Immediate, computed on-device — fires whether or not the network is available (R5). |
| Server refinement disagrees with the on-device verdict | Silent; update the event record only. Never contradict a warning the user already saw. |
| First offline capture | "Purchase saved offline. It will sync automatically." |
| Additional offline captures | Update the same notification with the queued count. |
| Backlog uploaded | One aggregate "N purchases synced" summary. |
| Authentication blocked | One actionable reconnect notification. |
| Actionable incomplete/quarantined event | Actionable notification offering review and a diagnostic report. |
| Local persistence failure | Immediate prominent warning. |
| Location unavailable | Diagnostics only. |
| Old retried event feedback | Save in activity history; do not present it as current-purchase feedback. |

## 17. Capture status and setup

Setup, as an extension of the existing `SyncCenterView` flow:

1. Explain that Inunity owns capture and PickMe provides the native bridge.
2. Sign in to the intended Inunity account.
3. Create and store the installation credential. (`SyncCenterView` already does this.)
4. Request notification permission.
5. Request location permission only if not already granted — the ambient checkout feature may already hold it — and state that location is optional.
6. Open Shortcuts and guide the user through the Transaction automation and its property mappings (§6).
7. Run a synthetic connection test that does not create a purchase.
8. Show **Connection tested — waiting for your first Wallet tap**.

Because PickMe cannot inspect the Personal Automation, `CaptureStatusView` shows evidence rather than claiming it is enabled:

- connection verified;
- bound Inunity account;
- last Wallet trigger received;
- last accepted upload;
- pending/quarantined counts and oldest pending time;
- location and notification permission state;
- last safe error and failing stage;
- **Retry now**, **Review queued events**, **Prepare diagnostic report**, **Open transactions in Inunity**, and **Disable Wallet Capture**.

Migration guidance replaces Dictionary + Run Wallet Capture V2 with the single App Intent. Revoke the old Shortcut token only after the first successful native capture; the existing ±60s fuzzy check protects the overlap.

## 18. Diagnostics, privacy, and support reports

Each event has a user-readable timeline, for example:

```text
Wallet fields received
Amount decoded (en_CA)
Saved locally
Verdict computed on-device
Location unavailable - continued without it
Upload attempted
No internet - retained safely
Retry started
Accepted by Inunity
Removed from outbox
```

Diagnostics may include short event ID, timestamps, stages, missing-field names, amount decode status, queue state, attempt count, safe error category, HTTP status, app/build/iOS/capture versions, and a non-coordinate location outcome/accuracy category.

Never log credentials, authorization headers, Keychain contents, full raw payloads, precise coordinates in default exports, device identifiers, or network names.

Support-report flow:

1. An actionable notification opens a redacted report preview.
2. Merchant, amount, card, and precise location are excluded by default.
3. The user may explicitly include transaction details.
4. Nothing is transmitted until the user taps **Send diagnostic report**.
5. Reference the existing server event ID instead of duplicating raw data already held by Inunity.
6. Submit through an authenticated Inunity diagnostics endpoint that stores the redacted snapshot and its explicit inclusion choices.
7. Retain submitted reports for 30 days, then automatically delete them.
8. Enforce expiry with server-side deletion rather than relying only on UI hiding.
9. Allow earlier user deletion.

Pending/quarantined diagnostics remain until resolution or explicit deletion. Completed local delivery diagnostics remain for 30 days, capped at the newest 500 completed event timelines.

## 19. Edge-case decisions

| Edge case | Required behaviour |
|---|---|
| No service | Persist, decode, verdict on-device, optionally locate, queue indefinitely, aggregate notification, retry later. |
| Location unavailable | Continue without location and log the reason. |
| Notification permission denied | Capture normally; show durable in-app status. |
| Missing useful field | Upload meaningful partial event, flag exact missing field, offer diagnostics. |
| `paymentMethodRaw` equals `transactionNameRaw` | The Shortcuts entity binding fell back; treat the field as absent and flag the mapping. Never store it as a card signal. |
| `cardRaw` resolves to no `CardAlias` | No verdict is produced. Surface it as a capture-status issue rather than letting the warning vanish silently; try `paymentMethodRaw` as a secondary resolution key when present. |
| Amount present but undecodable | Upload with `amountDecodeStatus: "undecodable"` and the raw text; server attempts its own parse. |
| Device and server disagree on the amount | Store both, flag the disagreement, prefer `amountDecimal`. |
| Every Wallet field empty | Keep as local configuration error; do not create a purchase. |
| Declined tap | Apple may not identify it; show normally until user or stronger evidence marks it declined. |
| Old poisoned file | Quarantine or retain it without blocking any other event. |
| Merchant-null events accumulate server-side | Must not stall the normalization queue for anyone; see §12. |
| `401`/revoked token | Retain and pause uploads pending relink; do not delete events. |
| Server stored event but normalization failed | Client deletes on acceptance; server retries normalization. |
| Two simultaneous intent invocations | Atomic claims ensure one uploader; server event ID ensures idempotency. |
| Old Shortcut and new intent both fire | Existing ±60s fuzzy check flags it; both raw events preserved, one purchase. |
| On-device cap data is stale | Verdict may be revised by the server refinement; stored record defers to the server, no contradicting notification. |
| Sign-out | Capture continues for the bound account; cap freshness degrades. |
| Different account signs in | Pause and require an explicit account decision. |
| Disable with backlog | Send, delete, or cancel; never silently lose. |
| Account deletion | Revoke token and remove unsent data. |
| App reinstall | Validate any surviving device-only credential before reuse; never assume account binding from Keychain presence alone. |
| Local storage failure | Prominent user-visible failure; never claim the purchase is safe. |

## 20. Verification and direct delivery

Sequence: **spike (§6) → full implementation → real-device checklist.** There is no feature flag, no staged rollout, and no throwaway production path. The spike is a probe whose only output is an answer about Apple's boundary; nothing it builds ships.

Automated verification is part of implementation. It is deliverable **only because the capture library lives in the `Store` package** (§5) — `App/`-resident logic is not built by CI at all. Coverage:

- atomic persistence before location, verdict, and network;
- claim and stale `inflight` recovery across an interrupted launch;
- independent retry processing;
- offline retention and reconnect drain;
- response classification and quarantine;
- credential/account isolation;
- missing-field behaviour;
- device-locale amount decoding across en_CA, fr_CA, and at least one period-as-thousands locale, plus the undecodable path;
- on-device verdict correctness, including the offline path and the stale-cap disagreement path;
- notification aggregation and diagnostic redaction;
- schema 1/schema 2 server compatibility, including schema 1's required `merchantRaw` and the renamed amount fields;
- exact and cross-source idempotency through the existing dedup rules;
- targeted real-time normalization, **including the 100-merchant-null head-of-line regression test** (§12);
- amount disagreement flagging;
- `paymentMethodRaw` capture, the equals-`transactionNameRaw` fallback case, and secondary card resolution;
- unknown payload keys surviving into `rawPayload` without a `4xx`;
- provisional accrual and correction reversal;
- declined, duplicate, adjusted, and permanent-delete actions.

After implementation, one real-device checklist verifies the Apple-controlled boundary: the full property mapping, successful purchase, declined attempt, PickMe terminated, no service, and location unavailable. This is final verification, not a staged rollout.

Deployment keeps the server backward-compatible so deployment order cannot strand the existing Wallet Capture V2 queue.

## 21. Success criteria

- No event received by the App Intent is lost to location, verdict computation, or networking.
- A local persistence failure is visible and never reported as safely queued.
- One failed or malformed event never blocks another — in the device outbox or the server's normalization queue.
- Offline events remain until accepted or explicitly removed.
- **A better-card warning fires on an offline capture**, with no network at any point.
- An amount is never silently misread by a factor of a thousand; a device/server disagreement is recorded rather than suppressed.
- Accepted captures normally appear on the hub's purchase screen within seconds.
- Schema 1 and schema 2 duplicates affect the purchase spine and cap ledger once, through the existing dedup rules rather than a new one.
- Ordinary purchases require no statement reconciliation or user confirmation.
- Users can correct declines, duplicates, bad fields, reversals, and deletions on the hub without destroying raw evidence accidentally.
- Users can identify the failing capture stage and knowingly send a redacted diagnostic report.
- No secret appears in payload diagnostics, logs, notifications, or support reports.
- Account switching cannot silently route transactions to the wrong account.
- PickMe's offline recommendation capability remains independent of Inunity.
- Every component in §5 marked `CardCopilotCapture` is exercised by `swift test`.
