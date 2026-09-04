# Purchase protection follow-through — coverage records across PickMe and In Unity

**Status:** Design only. Not ratified, not implemented. No code exists for anything below.

**Depends on:** [`purchase decision architecture`](2026-09-04-purchase-decision-architecture-design.md)
(`conservative-multi-attribute-v1`), [`product-boundaries.md`](../../policies/product-boundaries.md)
(A5, E1), [`ECOSYSTEM.md`](../../../ECOSYSTEM.md), and MoneyTalks
`docs/policies/card-ownership.md` (C1, D3).

**Blocking dependency:** Tier 1 below requires an amendment to invariant **D7** of the purchase
decision architecture. That amendment is the owner's call and is not made here.

## Executive decision

PickMe now advises partly on shopping protection and then forgets the purchase. The gap is real:
protection has no value unless it can be claimed, and a claim needs the card used, the purchase
date, the item, the coverage window, and the receipt.

The decision this document proposes is narrower than it first appears:

> **A coverage record is a derivation, not an entity.** It is a pure function of a purchase
> anchor PickMe already stores on device and a benefits catalogue PickMe already owns. It must not
> become a fourth persisted thing, and it must not become a row in In Unity.

```text
StoredPurchase (device, exists today)        contracts/benefits-catalogue.json (exists today)
  cardUsedId · amountCad · completedAt              windowDays · extraYears · conditions
  merchantLabel · categoryAtPurchase                verificationStatus
        |                                                   |
        +------------------------+--------------------------+
                                 v
                    CoverageProjection  (pure, Engine, new)
                                 |
                    [CoverageWindow]  — terms + dates + unevaluated conditions
                                 |
              +------------------+------------------+
              v                                     v
   PickMe coverage list (device)        In Unity receipt lookup (already stored there)
```

Nothing about that shape requires a new store, a new sync direction, a server-side coverage table,
or a copy of card facts into MoneyTalks.

## What already exists — read this before proposing storage

Three verified facts changed the scope of this design:

1. **The purchase anchor is already on device.** `CardCopilotSchemaV5.StoredPurchase` holds
   `cardUsedId`, `cardSourceRaw`, `amountCad`, `amountSourceRaw`, `completedAt`, `merchantLabel`,
   `merchantIdentifier`, `categoryAtPurchase`, and `walletEventId`. That is every field a coverage
   window needs except the item.
2. **Coverage duration is already in the contract.** `BenefitCoverage.windowDays` is populated for
   real cards — `amex-platinum` purchase protection is 120 days, `amex-cobalt` is 90 — alongside
   `extraYears` and `maxOriginalWarrantyYears` for extended warranty. Purchase-protection end dates
   need **no schema change**.
3. **Receipts already live in In Unity, server-side, under auth.** `Purchase`,
   `PurchaseAttachment` (`storageKey`, `sha256`), `ReceiptDocument` (`storagePath`), and
   `EmailTransaction` are all built. This feature reads them; it does not create them.

The genuinely missing pieces are small and specific. They are named in *Coverage terms* below.

## Ownership

Three different things are in play and they have three different owners. Blurring them is the
failure mode this section exists to prevent.

| Thing | Owner | Where it lives | Why |
|---|---|---|---|
| **Coverage terms** — what a card provides, for how long, under what conditions | **PickMe** | `contracts/benefits-catalogue.json` | Card-decision semantics, including benefits, are PickMe's by `ECOSYSTEM.md`. Card facts must not be re-authored in MoneyTalks (C1/D3). |
| **Purchase anchor** — card used, amount, date, merchant, declared item | **Split by origin.** Checkout- and wallet-captured purchases: PickMe, device-only. Email-derived purchases: In Unity. | `StoredPurchase` / `Purchase` | Each side already owns the capture path it built. Neither should mirror the other's captures to make coverage work. |
| **The coverage record** — this purchase × that benefit → covered until | **Neither. It is derived.** | Computed in `CardCopilotEngine`, held in memory | See below. |

### Why the coverage record is derived rather than stored

- **Staleness is dangerous in one direction.** Issuer certificates change. A stored "covered until
  March 2028" that outlives the certificate it came from tells the owner they are protected when
  they are not. A recomputed projection is wrong only in the same way the current catalogue is
  wrong, which is a problem the benefits provenance ladder already governs.
- **Storing it duplicates the most sensitive data.** A coverage table is, by construction, a list
  of what someone bought, for how much, on which card. Deriving it means that list exists only for
  as long as a screen is open.
- **Storing it in In Unity would import card facts.** A server-side `Coverage` row carrying
  `windowDays` or a benefit id is a hand-copied card fact in the repo whose `check:cards` guardrail
  exists precisely because that drift has already happened twice.

### Where coverage may be *shown*

PickMe shows it. In Unity may later show a coverage line on its own purchase detail page **by
calling the same contract**, not by re-deriving terms in TypeScript — the same rule the cards twin
already follows.

**A5 caution.** `product-boundaries.md` puts deep analytics and dashboards on the hub. A short
per-card or per-purchase coverage list in PickMe is the same weight as the existing "small monthly
summary" and is defensible. A coverage *dashboard* — filters, charts, aggregate exposure by
category, expiry heatmaps — is a hub surface and must not be built in Swift or Kotlin.

## Coverage terms — what the contract can and cannot express

Checked against `contracts/benefits-catalogue.json` v1.3 and `BenefitsModels.swift`.

### Expressible today, no change needed

- **`purchaseProtection`.** `windowDays` is populated. `closesAt = purchaseDate + windowDays`.
  Exact, derivable, offline.

### Expressible, but the missing input is an *item* fact — not a schema gap

- **`extendedWarranty`.** `extraYears` and `maxOriginalWarrantyYears` are populated. But the end
  date is `purchaseDate + originalManufacturerWarrantyYears + extraYears`, and the manufacturer's
  warranty length is a property of the **item**, not the card. PickMe must not add it to the card
  catalogue, and must not guess it from merchant, price, or category (this is D3 applied to time
  instead of category). Either the owner supplies it or the projection reports
  *"adds 1 year to the manufacturer warranty"* with no date. **Reporting the relationship without a
  date is an acceptable Tier 0 answer** and is more honest than a guessed one.

### Genuine catalogue gaps

Both are card facts, so they belong in the catalogue, authored under the card-contract authoring
rules with the existing provenance ladder:

- **`claimNoticeDays`** (and possibly `proofDays`). Certificates commonly require notice of a loss
  within N days of the loss, which is a *different clock* from the coverage window. Without it,
  "covered until March 2028" can be simultaneously true and useless — the loss happened in January
  and the notice window closed in February. Shipping expiry reminders without this field is the
  most likely way to make this feature actively misleading.
- **`claimContact`** — underwriter name and claims URL or phone. `CertificateProvenance.underwriter`
  exists but there is no claims entry point. "Here's who to call" is most of the perceived value of
  follow-through and is cheap to add.

### Deliberately not modelled

- **`conditions` and `exclusions` are free prose and stay prose.** A projection cannot evaluate
  "eligible original manufacturer warranty must be five years or less." It must therefore return
  conditions **verbatim and unevaluated** next to the dates, never a `isCovered: Bool`.
- **`mobileDeviceInsurance`** is not purchase-anchored — it typically runs while the device *bill*
  is charged to the card, on a declining-value schedule. It does not fit the
  `purchase + window` shape and must not be forced into it.

## Invariants

These protect correctness and privacy. A future agent replacing the implementation should keep
these; everything in *Implementation choices* below is free to go.

### P1 — A coverage record is derived, never stored as fact

Recompute from the current catalogue on every read. Caching for a screen's lifetime is fine;
persisting a computed `closesAt` is not.

### P2 — PickMe states terms and dates; it never states that a claim is covered

The output is *"this card's purchase protection runs 120 days from the purchase date, and the
certificate requires the following"* — with the conditions shown. No coverage boolean, no
"you're covered", no implied claim outcome. This is the existing checkout copy rule
(*"do not promise that a claim is covered merely because a benefit is listed"*) extended past the
till.

### P3 — Only non-`stub` benefits produce a coverage window

Inherits D2. A `stub` record may remain visible in reference/disclosure UX and must never generate
a date. Crypto.com Royal Indigo has no located certificate today; it must produce no windows.

### P4 — Coverage follows the card **used**, not the card **recommended**

`StoredPurchase.cardUsedId` with its `cardSourceRaw` provenance, never
`StoredPrediction.winnerCardId`. When `cardUsedId` is nil, the coverage answer is *unknown* — a
first-class result, not a fallback to the recommendation. Getting this backwards would tell owners
they have coverage from a card they declined to use.

### P5 — Item facts are owner-declared, never inferred

Extends D3 and D7. Neither MCC, merchant, price, nor a receipt line item establishes that a purchase
was a laptop with a two-year manufacturer warranty. No item fact may be derived from merchant
category, and no manufacturer-warranty length may be defaulted by category.

### P6 — Receipt bytes never cross the tier they arrived in

A receipt photographed on device stays on device. A receipt that arrived by email stays in In
Unity's existing storage under its existing auth. Coverage follow-through must not copy receipt
bytes across the boundary in either direction to assemble a record; it may only *link* to one.

### P7 — Every Tier 1 capability works signed out and offline

The purchase anchor, the catalogue, and the projection are all on device. If a capability requires
an account to answer "what is covered and until when," it is out of Tier 1 by definition.

### P8 — New owner-declared facts join the erasure gesture explicitly

`LocalDataEraser.eraseLocalHistory()` deletes each row explicitly rather than relying on cascades,
by its own stated convention. Derived coverage disappears with the purchases for free; any new
persisted item declaration or local receipt file must be added to the eraser in the same explicit
style, and to `WalletCaptureDeletionStore`'s sibling pattern where it applies.

### P9 — Expiry reminders are local notifications

No coverage date, item label, or purchase amount leaves the device in order to schedule a reminder.
A server-scheduled push would move the most sensitive data off device for the least valuable
capability in the design.

### P10 — Item declarations never enter community or aggregate data

An item declaration must not reach community MCC evidence, `CategoryResolutionMetricsStore`,
`MerchantMCCRewardFeedback`, or any telemetry. D7's merchant-truth prohibition survives fully:
a declaration is about the item, never about the merchant.

## The D7 conflict — read before building Tier 1

The ratified purchase decision architecture states:

> **D7** — … V1 stores the selection only in `RecommendationView` state. It survives amount
> refinements and nearby Purchase Route refreshes for the active answer screen, but is **not
> written to purchase history**, UserDefaults, account sync, community evidence, or analytics.

Coverage follow-through needs the declared item type to survive the checkout. D7 anticipated this:

> If a future product need justifies durable purchase-type storage, add it deliberately with a
> clear privacy/product purpose and migration plan; do not silently expand the lifetime of this V1
> state.

This design is that product need, but the amendment is a separate, explicit decision and belongs in
the purchase-decision spec, not here. The proposed shape:

**D7a (proposed).** A declared purchase type may be persisted to the local purchase anchor **only**
as the result of an owner-initiated per-purchase action taken with visible intent — never
automatically as a side effect of answering the checkout question. The prohibitions on promoting it
to merchant truth, community evidence, account sync, and analytics survive unchanged.

The practical consequence is a product one: **answering "what are you buying?" at the till must not
silently start a retention record.** Remembering is a second, visible act.

## The local-first constraint

| Capability | Signed out, offline | Signed in to In Unity |
|---|---|---|
| Purchase anchor | `StoredPurchase` from checkout or wallet capture | same, plus email-derived `Purchase` rows |
| Coverage terms | bundled `contracts/benefits-catalogue.json` | same |
| Coverage window + conditions | full | full |
| Claim contact | full | full |
| Expiry reminder | local notification | same |
| Receipt | whatever the owner attached on device, if anything | plus receipts already ingested from email |
| Claim pack assembly | manual | assisted by receipt lookup |

**Nothing in Tier 1 degrades when signed out.** That is achievable because the only server-side
asset in the whole design is the receipt, and a receipt found later does not change whether coverage
exists — it changes only how hard the claim is. The signed-in benefit is therefore genuinely
additive rather than a hollowed-out signed-out experience.

## Privacy

Stated plainly, because the honest answer is unflattering in one place and reassuring in another.

**Storage location.**
- Card terms: `contracts/`, public, impersonal.
- Purchase anchor and any item declaration: **device only**, SwiftData, never synced.
- Locally attached receipts: **device only**, in the app container. Not iCloud, not the shared
  photo library, not sync.
- Email-derived purchases and receipts: In Unity's existing Postgres and blob storage under Clerk
  auth, unchanged.

**The MoneyTalks public-repo rule is about repo contents, not the database.** `REPO_MAP.md` routes
anything containing personal data to gitignored `docs/private/`. The production database already
holds receipts, merchants, amounts, and order numbers under authentication. So the honest
statement is: **this design creates no new class of server-side personal data.** It reads what is
already there. Do not claim a privacy improvement that is not being made, and do not claim a
privacy cost on the hub side that is not being incurred.

**The real privacy delta is on device, and it is small but not nothing.** Today PickMe stores what
you bought *at the category level* — "grocery, $84." An item declaration moves that to
"electronics," and Tier 2's manufacturer-warranty capture invites a free-text item label. That is
the most item-specific data PickMe has ever held. For calibration: it is still less revealing than
`DiscoveryCache`, which records every ~1 km cell the owner has passed through and which the
existing eraser documentation already singles out as the weakest claim to surviving a wipe.

**Retention.** Purchase anchors are retained indefinitely today; no pruning exists. Item
declarations should not inherit that. Proposal: an item declaration is dropped automatically once
the last coverage window it feeds has closed plus `claimNoticeDays`, because an item label has no
purpose after nothing can be claimed. Per-purchase "forget this" must also exist, separate from the
all-or-nothing local wipe.

**Disclosure.** Two obligations. First, the point-of-declaration affordance from D7a — the owner
must be able to see that they are choosing to retain something. Second, the coverage screen must
disclose that dates are computed from PickMe's reading of the certificate and that the certificate
governs, with the existing document links from `CardDocument` reachable from the same screen.

## Scope tiers

### Tier 0 — "what this card would have covered" (recommended start)

Read-only. For existing `StoredPurchase` rows, show the shopping benefits of the card actually used
and their windows.

- Purchase protection: exact dates.
- Extended warranty: the relationship without a date — *"adds 1 year to the manufacturer warranty,
  if that warranty is 5 years or less."*
- Conditions verbatim; claim contact once the catalogue carries it.

**No schema change. No new personal data. No D7 conflict. No account.** It is a projection over
data that already exists, and it is the only tier that can be built without settling anything.

### Tier 1 — the genuinely useful minimum

Tier 0, plus:

1. `claimNoticeDays` and `claimContact` in the benefits catalogue (research + authoring pass).
2. The D7a amendment and an explicit "remember this for coverage" action at checkout.
3. A local notification before a purchase-protection window closes.

This delivers the owner's own sentence, minus the receipt: *"you bought this on the Amex, purchase
protection runs to January 2027, here's who to call."*

### Tier 2 — ambitious

- Manufacturer-warranty capture → true extended-warranty end dates.
- Device-local receipt attachment.
- Receipt auto-match against In Unity purchases when signed in (matching on merchant, amount, date
  — the same shape as the existing `purchaseMerge` and duplicate-detection machinery, and therefore
  In Unity's job, not PickMe's).
- Claim pack export: receipt + statement line + certificate excerpt + card last four.

### Explicitly not on this path

Automated claim filing. Inferring item identity from receipt line items. Any surface that predicts
a claim outcome. A coverage dashboard in Swift (A5).

### Recommendation

**Build Tier 0. Gate Tier 1 on evidence from Tier 0.** Tier 0 is cheap, settles nothing
irreversibly, and produces the one measurement that determines whether Tier 1 is worth its privacy
cost: how many purchases actually have a card with a non-stub shopping benefit *and* an amount above
`bigTicketThresholdCad`.

That number can be computed from the existing store **before writing any of this** — which is the
highest-ROI action in this document and takes an afternoon.

## What would make this not worth building

Not rhetorical. Five real reasons, roughly in order of how likely they are to be true.

1. **Frequency.** Claimable losses are rare — a household may have one every several years. A
   feature that is correct and never used is still dead weight, and reminder infrastructure ages
   badly. This is the strongest argument against Tier 1 and the reason Tier 0 is gated.
2. **The declaration is asked at the worst moment.** The item type is load-bearing for every date
   past purchase protection, and it is requested at the till, when the owner wants to pay. If
   attach rate is low, Tier 1 ships a follow-through surface with nothing in it — worse than not
   shipping, because it advertises a capability it cannot deliver.
3. **Exclusions are prose and PickMe cannot read them.** A certificate excludes more than it
   covers. An owner who reads "covered to March 2028," files, and is denied on an exclusion PickMe
   never surfaced has been harmed on the exact surface where PickMe's claim is *"we read the
   certificate."* P2 mitigates this; it does not eliminate it.
4. **The receipt may be the whole problem.** If what owners actually need is *"find the receipt for
   the thing that broke,"* that is a search feature over In Unity's existing `ReceiptDocument` and
   `PurchaseAttachment` rows — and building a coverage model in PickMe would be solving the less
   valuable half. This is worth asking a real user before building either.
5. **Issuers already run claim portals.** Amex and Scotia both do. PickMe's addition is narrow:
   knowing *which of your several cards* covered a purchase you made months ago and have forgotten.
   That gap is real, but it is one sentence wide, and one sentence is Tier 0.

**Kill criterion.** If the pre-build measurement shows that only a small fraction of recorded
purchases pair a non-stub shopping benefit with an above-threshold amount, the claimable population
is too small to justify Tier 1 and the design should stop at Tier 0 — or stop entirely.

## Implementation choices a future agent should feel free to replace

None of this is load-bearing.

- **Projection as a pure Engine function**, `CoverageProjection.windows(for:in:itemFacts:)`,
  twinned in Kotlin and covered by shared fixtures like every other Engine semantic.
- **A `CoverageWindow` shape** carrying `benefitId`, `kind`, `opensAt`, optional `closesAt`, a flag
  for whether `closesAt` is derived or unknown, the verbatim `conditions`, and a
  **`requiredInputs`** list naming what is missing (e.g. `manufacturerWarrantyYears`). That last
  field is what lets the UI *ask* instead of guess — the same move `purchaseContextNeeded` already
  makes at checkout, and the reason unknown stays a first-class result here too.
- **A `Destination.coverage` case** and a list reachable from the You hub, alongside the existing
  `protectionLens` and `benefitsReference` destinations.
- **Local notifications** for expiry, scheduled at declaration time.
- **Retention by automatic drop** after the last window closes, rather than a retention setting.

## What is unsettled

1. **Whether persisted item declarations are acceptable at all.** This is the D7a decision and it
   is the owner's, not an agent's. Everything in Tier 1 waits on it.
2. **Whether `claimNoticeDays` is uniformly stated** across the 27 cards' certificates, or too
   varied to type without inventing structure. Needs a research pass in the style of the existing
   MCC coverage research before any schema change is proposed.
3. **Whether extended-warranty end dates are worth the extra question.** Purchase protection is
   free to compute; extended warranty costs the owner an answer about manufacturer warranty length
   that they may not know.
4. **Which repo owns receipt→purchase matching** if Tier 2 happens. The matching machinery lives in
   In Unity and should probably stay there, but the coverage consumer is PickMe, and the interface
   between them is undesigned.
5. **Whether coverage belongs in PickMe's UI or In Unity's purchase detail page.** PickMe owns
   benefits semantics; In Unity owns the purchase spine and, under A5, the dashboards. Tier 0's
   small list is defensible in PickMe. Anything larger probably is not.
6. **Whether a coverage window should be shown for a purchase whose `cardUsedId` is nil** — the
   honest answer is "unknown," but a screen full of "unknown" may be worse than a shorter screen.

## Prior art in this repo worth reading before implementing

- `Engine/Sources/CardCopilotEngine/Engine/BenefitsAdvisor.swift` — existing protection comparison
  semantics and the stub/verified gate.
- `Engine/Sources/CardCopilotEngine/Models/BenefitsModels.swift` — `BenefitCoverage` field set and
  the "typed fields only for what the table sorts" rule.
- `Store/Sources/CardCopilotStore/SchemaV5Models.swift` — `StoredPurchase`, the anchor.
- `Store/Sources/CardCopilotStore/LocalDataEraser.swift` — the explicit-deletion convention and the
  reasoning about which local data has the weakest claim to surviving a wipe.
- MoneyTalks `prisma/schema.prisma` — `Purchase`, `PurchaseAttachment`, `ReceiptDocument`,
  `EmailTransaction`.
- MoneyTalks `docs/policies/card-ownership.md` — why no card fact may be re-authored on the hub.

## Testing contract, if this is built

- A purchase on a card with a 120-day purchase protection produces a window closing exactly 120 days
  after the purchase date.
- A purchase on a card whose benefits are `stub` produces no windows.
- A purchase with `cardUsedId` nil produces an explicit unknown, never the recommended card's
  coverage.
- Extended warranty with no owner-supplied manufacturer warranty produces a window with no
  `closesAt` and a `requiredInputs` entry, not a guessed date.
- Conditions appear verbatim in the projection output.
- Erasing local history removes every purchase-derived coverage answer and every item declaration.
- Swift and Kotlin agree on the projection for the shared fixtures.

Gate, unchanged:

```bash
(cd Engine && swift test) && (cd android && ./gradlew :core:engine:test)
```
