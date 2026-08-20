# Native Apple Wallet Capture Design

**Status:** Proposed from decisions approved in conversation; awaiting written-spec review  
**Products:** PickMe (native bridge and optional transaction view), Inunity (capture system of record)  
**Repositories:** `PickMe`, `MoneyTalks`  
**Delivery:** Direct full implementation. No feature flag or staged rollout. Automated verification remains part of implementation, followed by one real-device Wallet check.

## 1. Summary

Replace the user-maintained Wallet Capture V2 shortcut with a dedicated PickMe App Intent named **Send Wallet Purchase to Inunity**.

The user still creates Apple's Personal Automation and maps the five properties Apple exposes in the Transaction editor. Everything after that mapping moves into maintained native code: event identity, durable local persistence, optional location, authentication, upload, retries, notifications, and diagnostics.

PickMe remains independently useful as the offline card-recommendation product. Inunity remains the owner of Apple Wallet capture, the purchase spine, transaction history, normalization, reconciliation, and cross-product intelligence. PickMe hosts the bridge because it is the installed native iPhone product and may display recent Inunity transactions as an optional connected benefit.

## 2. Goals

- Reduce the Personal Automation to one parameterized app action.
- Persist every meaningful Wallet trigger before attempting optional enrichment or networking.
- Keep offline events indefinitely until Inunity accepts them or the user explicitly removes them.
- Ensure one failed event never blocks another.
- Normalize the newly accepted event in real time so it appears on the purchase screen within seconds.
- Keep ordinary captured purchases frictionless; receipt or statement reconciliation is optional enhancement, not required work.
- Make capture health and failure stages understandable to the user.
- Preserve raw observations while allowing user corrections, declines, duplicate resolution, reversals, and permanent deletion.
- Maintain Wallet Capture V2 server compatibility during migration.
- Preserve the boundary that Inunity owns capture and PickMe owns card-decision semantics.

## 3. Non-goals

- Creating, enabling, inspecting, or editing Apple's Personal Automation programmatically.
- Reading Apple Wallet history.
- Determining authorization, decline, or settlement status from Apple when Apple does not expose it.
- Bank aggregation or FinanceKit access.
- Performing merchant normalization, categorization, card resolution, rewards calculation, cap rules, deduplication, or analytics inside the App Intent.
- Requiring users to reconcile every purchase against a statement.
- Collecting device identifiers, network names, battery state, IP-derived location, or unrelated telemetry.

## 4. Product ownership and trust boundaries

### PickMe

- Provides offline card recommendations whether or not the user connects Inunity.
- Ships the native App Intent bridge and shared capture library.
- Holds unsent events in a protected App Group outbox.
- Holds one write-only, installation-scoped Inunity credential in a shared device-only Keychain item.
- Shows Capture Health, local diagnostics, recent connected transactions, and correction controls.
- Uses normal signed-in access for reading Inunity data. The capture credential cannot read account data.

### Inunity

- Authenticates the installation credential.
- Durably stores raw Wallet observations and precise location when supplied.
- Normalizes and promotes observations into the purchase spine.
- Owns transaction status, cross-source matching, corrections, rewards/cap effects, and reconciliation.
- Returns explicit upload dispositions and current-event feedback.

### Apple

- Owns the Wallet Transaction trigger and Personal Automation.
- Supplies the five mapped Wallet properties.
- May trigger on a tap that is later declined and does not provide a documented approval/decline flag to this integration.

## 5. Native architecture

Use a dedicated App Intent extension for background isolation. Place the implementation behind a shared native capture library so the extension and main PickMe app use identical storage, upload, diagnostics, and retry rules.

Components:

| Component | Responsibility |
|---|---|
| `WalletCaptureIntent` | Declares the five optional parameters and hands them to the capture coordinator. |
| `WalletCaptureCoordinator` | Generates metadata, persists first, requests optional location, drains the queue, and returns current-event status. |
| `WalletOutboxStore` | Atomic files, claims, stale-claim recovery, quarantine, and queue inspection. |
| `WalletCaptureCredentialStore` | Shared Keychain installation credential and account-binding metadata. |
| `WalletLocationEnricher` | Best-effort fresh location with a short budget; never gates capture. |
| `WalletCaptureUploader` | Schema 2 request construction, explicit response classification, and independent per-event attempts. |
| `WalletCaptureDiagnosticsStore` | Safe event timelines and redacted support-report generation. |
| `WalletCaptureNotificationCoordinator` | Aggregated offline/auth/problem notifications and current-event card feedback. |
| Capture Health UI | Setup, permissions, connection state, queue inspection, retry, diagnostics, disable, and account relinking. |

The existing App Group `group.ca.inunity.pickme` is the shared filesystem boundary. Add a shared Keychain access group for the main app and App Intent extension.

## 6. Personal Automation contract

The user creates one Transaction automation per selected Wallet card, chooses Run Immediately, and maps:

```text
Send Wallet Purchase to Inunity
Merchant      <- Merchant
Amount        <- Amount
Name          <- Name
Currency      <- Currency Code
Card          <- Card or Pass
```

Start with optional text parameters because Wallet/Shortcuts frequently supplies localized representations. A real-device check must confirm the exact conversion behavior. Do not require the whole private Wallet transaction object.

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
    "currencyRaw": "Apple-supplied code or null",
    "cardRaw": "Apple-supplied text or null"
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

- Preserve all Wallet values exactly; normalize only on the server.
- All five Wallet fields are individually optional at runtime.
- A meaningful incomplete event uploads for later correction.
- If all five fields are empty, retain it locally as an automation-configuration error, do not promote it as a purchase, and notify the user.
- Missing location never delays or loses a capture.
- `source` describes where the observation originated; `transport` describes how it reached Inunity.
- Do not include a user ID, device identifier, network name, or secret. The installation credential determines the destination account.
- Inunity retains the raw payload alongside interpreted values.

Actionable incompleteness means merchant and name are both absent, amount is absent/unreadable, card is absent, several mapped values are unexpectedly empty, or the mapping appears entirely broken. Missing location, or a missing name when merchant exists, is diagnostic information without an interruption.

## 8. Persist-before-enrichment flow

1. Receive the mapped Wallet fields.
2. Generate `eventId`, `capturedAt`, timezone, source/transport versions, and client diagnostics.
3. Build the minimal event without location.
4. Atomically persist it to `pending`.
5. If persistence fails, show a prominent **Purchase could not be saved** notification/result and retain a safe local diagnostic if possible.
6. Request a location for at most two seconds. Accept only a valid fix whose timestamp is no more than 60 seconds old.
7. If location succeeds, atomically replace the queued payload with coordinates, accuracy, and the location timestamp. Record accuracy but do not reject an otherwise valid fresh fix solely for being imprecise; Inunity decides how much evidentiary weight it deserves.
8. If location fails or is unavailable, record the safe reason and continue with the minimal event.
9. Attempt the current event first for timely feedback, then independently attempt older pending events.

Omit the `location` object entirely when no acceptable fix exists. Never attach a later location to an old purchase because a later coordinate may no longer represent the purchase location.

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
- Atomic claiming, rather than an in-process Swift actor alone, coordinates the main app and extension across processes.
- Recover stale `inflight` files to `pending` after interrupted execution.
- Store account-mismatch events in `unassigned`; they are never upload candidates until the user explicitly assigns them.
- Serialize each process's drain work, but catch failures per event and continue with other files.
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
- Replace request-time global batch processing with `processWalletEvent(eventId)` so the event that just arrived is processed directly.
- Keep the hourly batch as repair machinery for pending server work.
- Immediately create or enrich the canonical `Purchase` when enough information exists.
- Promote meaningful incomplete events with explicit missing fields rather than leaving them invisible forever.
- Compute current-event feedback after targeted normalization when normalized merchant/category/card evidence is available; degrade to `unknown` without delaying durable acceptance.
- Return the real-time normalization state and current-event feedback in the response.
- Expose a signed-in, paginated recent-purchases read API for PickMe. Its stable row shape includes purchase ID, display merchant, amount/currency, card, purchase time, financial status, issue flags, and correction capabilities.
- Expose authenticated correction commands for declined/not-completed, duplicate, field correction, refund/reversal, Undo where safe, and permanent deletion. Every command revalidates purchase ownership server-side.

Ordinary accepted purchases appear in the purchase screen within seconds. The purchase list does not show a persistent `Unverified` warning or source badge. Source provenance appears in transaction details and when it explains a conflict.

PickMe refreshes recent purchases on sign-in, foreground, manual refresh, and after a capture performed while the main app is active. When the app was closed during capture, the new purchase appears on the next foreground refresh; the App Intent does not need read-account authority.

## 13. Deduplication

### Exact retry

The same `eventId` always resolves to the existing observation and never creates a second purchase or cap accrual.

### Migration overlap

When schema 1 and schema 2 observations for the same account have matching card, amount, merchant, and capture times within approximately 15 seconds:

- preserve both raw observations;
- link both to one canonical purchase;
- accrue rewards/caps once;
- display one purchase.

### Same-source rapid attempts

Do not silently merge same-source events because two fast purchases can be legitimate. Flag or group them as multiple Wallet attempts and make correction easy. Stronger receipt/statement evidence may resolve them automatically.

## 14. Purchase UX and corrections

New Wallet captures appear immediately as ordinary purchases. The user is not asked to reconcile them. Receipt or statement evidence silently strengthens or adjusts them when available.

Transaction details expose:

- **Payment didn't complete**: mark `DECLINED`, hide from the default purchase list, and reverse provisional rewards/cap effects.
- **This is a duplicate**: link/merge observations and prevent double counting.
- **Edit details**: store corrected merchant, amount, currency, or card separately from Apple's raw values and recalculate affected results.
- **Refunded/reversed**: retain history and apply the appropriate reversal.
- **Delete permanently**: explicitly erase the purchase and underlying capture under account privacy/deletion rules.

Support Undo where technically safe. Normal removal retains the raw observation for diagnostics; permanent deletion is a separate explicit action.

## 15. Authentication and account binding

- Store a write-only installation token in a non-synchronizing, device-only shared Keychain item.
- The token remains active when the user signs out of PickMe.
- Signing out stops signed-in reads/manual account sync but does not stop capture.
- Viewing server transactions requires signing in.
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

Request notification permission in context during Wallet Capture setup. If notifications are denied, preserve durable Capture Health state and return a concise App Intent result where possible.

| Outcome | Notification behaviour |
|---|---|
| Ordinary online success | Silent. |
| Current-event better-card warning | Immediate. |
| First offline capture | “Purchase saved offline. It will sync automatically.” |
| Additional offline captures | Update the same notification with the queued count. |
| Backlog uploaded | One aggregate “N purchases synced” summary. |
| Authentication blocked | One actionable reconnect notification. |
| Actionable incomplete/quarantined event | Actionable notification offering review and a diagnostic report. |
| Local persistence failure | Immediate prominent warning. |
| Location unavailable | Diagnostics only. |
| Old retried event feedback | Save in activity history; do not present it as current-purchase feedback. |

## 17. Capture Health and setup

Setup:

1. Explain that Inunity owns capture and PickMe provides the native bridge.
2. Sign in to the intended Inunity account.
3. Create and store the installation credential.
4. Request notification permission.
5. Request location permission separately and state that location is optional.
6. Open Shortcuts and guide the user through the Transaction automation and five mappings.
7. Run a synthetic connection test that does not create a purchase.
8. Show **Connection tested - waiting for your first Wallet tap**.

Because PickMe cannot inspect the Personal Automation, Capture Health shows evidence rather than claiming it is enabled:

- connection verified;
- bound Inunity account;
- last Wallet trigger received;
- last accepted upload;
- pending/quarantined counts and oldest pending time;
- location and notification permission state;
- last safe error and failing stage;
- **Retry now**, **Review queued events**, **Prepare diagnostic report**, and **Disable Wallet Capture**.

Migration guidance replaces Dictionary + Run Wallet Capture V2 with the single App Intent. Revoke the old Shortcut token only after the first successful native capture. Cross-source deduplication protects temporary overlap.

## 18. Diagnostics, privacy, and support reports

Each event has a user-readable timeline, for example:

```text
Wallet fields received
Saved locally
Location unavailable - continued without it
Upload attempted
No internet - retained safely
Retry started
Accepted by Inunity
Removed from outbox
```

Diagnostics may include short event ID, timestamps, stages, missing-field names, queue state, attempt count, safe error category, HTTP status, app/build/iOS/capture versions, and a non-coordinate location outcome/accuracy category.

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
| No service | Persist, optionally locate, queue indefinitely, aggregate notification, retry later. |
| Location unavailable | Continue without location and log the reason. |
| Notification permission denied | Capture normally; show durable in-app health state. |
| Missing useful field | Upload meaningful partial event, flag exact missing field, offer diagnostics. |
| All five fields empty | Keep as local configuration error; do not create a purchase. |
| Declined tap | Apple may not identify it; show normally until user/stronger evidence marks it declined. |
| Old poisoned file | Quarantine or retain it without blocking any other event. |
| `401`/revoked token | Retain and pause uploads pending relink; do not delete events. |
| Server stored event but normalization failed | Client deletes on acceptance; server retries normalization. |
| Two simultaneous intent processes | Atomic claims ensure one local uploader; server event ID ensures idempotency. |
| Old Shortcut and new intent both fire | Preserve both raw events and collapse into one purchase. |
| Sign-out | Capture continues for the bound account. |
| Different account signs in | Pause and require an explicit account decision. |
| Disable with backlog | Send, delete, or cancel; never silently lose. |
| Account deletion | Revoke token and remove unsent data. |
| App reinstall | Validate any surviving device-only credential before reuse; never assume account binding from Keychain presence alone. |
| Local storage failure | Prominent user-visible failure; never claim the purchase is safe. |

## 20. Verification and direct delivery

There is no staged rollout, feature flag, or throwaway production path. Implement the complete client and server design directly.

Automated verification is part of implementation and covers:

- atomic persistence before location/network;
- concurrent claims and stale `inflight` recovery;
- independent retry processing;
- offline retention and reconnect drain;
- response classification and quarantine;
- credential/account isolation;
- missing-field behaviour;
- notification aggregation and diagnostic redaction;
- schema 1/schema 2 server compatibility;
- exact and cross-source idempotency;
- targeted real-time normalization;
- provisional accrual and correction reversal;
- declined, duplicate, adjusted, and permanent-delete actions.

After implementation, one real-device checklist verifies the Apple-controlled boundary: five-field mapping, successful purchase, declined attempt, PickMe terminated, no service, and location unavailable. This is final verification, not a staged rollout.

Deployment keeps the server backward-compatible so deployment order cannot strand the existing Wallet Capture V2 queue.

## 21. Success criteria

- No event received by the App Intent is lost to location or networking.
- A local persistence failure is visible and never reported as safely queued.
- One failed or malformed event never blocks another.
- Offline events remain until accepted or explicitly removed.
- Accepted captures normally appear in the purchase screen within seconds.
- Schema 1 and schema 2 duplicates affect the purchase spine and cap ledger once.
- Ordinary purchases require no statement reconciliation or user confirmation.
- Users can correct declines, duplicates, bad fields, reversals, and deletions without destroying raw evidence accidentally.
- Users can identify the failing capture stage and knowingly send a redacted diagnostic report.
- No secret appears in payload diagnostics, logs, notifications, or support reports.
- Account switching cannot silently route transactions to the wrong account.
- PickMe's offline recommendation capability remains independent of Inunity.
