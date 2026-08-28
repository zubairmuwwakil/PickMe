# Merchant-locked credit and closed-loop acceptance

**Date:** 2026-08-27
**Status:** design approved in chat, not implemented
**Baseline:** `card-contracts@2.4` — 85 cards (41 CA published, 40 US draft, 4 CA draft)
**Target:** catalogue 2.5 (additive; no existing card's score changes)

## Why this exists

The 2026-08-27 Option 1 ruling landed the US issuer-flagship set and deferred
co-brand currencies. `catalogue-pipeline/programid-additions.proposed.json`
carried the deferral in two parts: 19 named currencies under
`proposedAdditions` (seven of which landed the same day as catalogue 2.4), and
34 cards under `deferredNotOneCurrency`, held back on the stated ground that
they are not a single currency and collapsing them would value one brand's
points as another's.

That ground is sound. The grouping under it is not.

### The 34 are a regex artifact, not a finding

`catalogue-pipeline/scripts/propose_programs.py:89` and `:91` hold two
catch-all rows:

    (r"kohl|sam's club|sears|walgreens|\bgap\b|athleta|...", "Store-specific rewards")
    (r"harley|h-d |verizon|carecredit|aarp|\bnhl\b|morgan stanley|...", "Brand-specific rewards")

Every one of the 34 records a `basis` that is literally the alternation which
matched its **name**. No reward text was read. The "currency" is a placeholder
string.

The other 19 entries in the same file are honest by contrast: `deltaSkyMiles`
matched `delta|skymiles`, and Delta SkyMiles is one currency. The two catch-alls
were written as a residue bucket and then read back as a conclusion.

### The repo's own licensed source disagrees

`catalogue-pipeline/raw/us/cc-offers/cc-offers-export-2026-08-27.json` (MIT,
`disposition: redistributable-with-notice` in `SOURCES.json`) carries a
`category` field. Of the 34, **19 still have retained provenance** there; the
other 15 came only from the `opencard` snapshot, which `SOURCES.json` marks
`blocked` and which was deleted from the tree in the licence audit.

For those 19:

| cc-offers category | cards | implication |
|---|---|---|
| `CASH_BACK` | AARP Essential, NHL Discover it, Amazon Visa, Prime Visa | `cashback` / `discoverCashback` — already in the enum |
| `DIGITAL_WALLET_CASH_BACK` | PayPal Cashback MC, Venmo CC, Venmo Visa Signature | `cashback` shape |
| `HEALTH_WELLNESS_FINANCING`, `RETAIL_FINANCING` | CareCredit, PayPal Credit | the `noRewards` shape shipped 2026-08-27 |
| `RETAIL_/WAREHOUSE_/CRUISE_REWARDS` | Gap Encore, Athleta Encore, Nordstrom, Target Circle, BJ's One, Sam's Club MC, Amazon Store, Amazon Secured, Carnival, CareCredit Rewards | genuinely merchant-locked |

**9 of 19 (47%) are not "a currency this catalogue cannot name"** by the
source's own reading. Ruling the whole bucket out of scope would have excluded
ordinary cash-back cards from a checkout-pick product.

### The cost model was inverted

Two facts make the expensive-looking option cheap:

1. **`ctMoney` is already the generic merchant-locked-dollar model.** From
   `contracts/programs.json`: *"face value is 1 CT Money = $1.00 at Canadian
   Tire, an issuer fact. ASSUMPTION: a 0.95 usability factor, applied by
   default, because CT Money spends only in one retailer's stores and a dollar
   locked to one merchant is not a dollar."* It is built, valued, tested and
   mirrored across Swift/Kotlin/TypeScript. Only its name is Canadian-Tire
   specific.

2. **A new programId costs zero engine code.** `Scorer.valueCad` dispatches on
   the valuation's *model*, not the program's name (`Scorer.swift:216`). The
   2026-08-20 refactor moved dispatch from identity to shape, so the enum grows
   without any of the three engines learning a case. "34 enum values" is JSON in
   three synced files, not 34x3 code paths.

## Ratified decisions (owner, in chat, 2026-08-27)

1. Reclassify the bucket from evidence before ruling on the residue.
2. Genuinely merchant-locked cards get **one programId per brand on a shared
   `merchantCredit` model**, each with its own usability factor.
3. The closed-loop / private-label `network` gap is ruled on **in this pass**,
   not deferred.
4. A third-party `category` **may route a draft**; it may never verify one.

## Section 1 — Reclassification (pipeline only, no contract change)

Rewrite the classifier tail of `propose_programs.py`:

- **Delete** the two catch-all rows. A rule that cannot name a currency must not
  emit a currency-shaped proposal.
- **Add an evidence classifier** keyed on the cc-offers `category`:
  - `*_CASH_BACK` -> `cashback`, or `discoverCashback` when the issuer is Discover
  - `*_FINANCING` -> `noRewards` candidate
  - `RETAIL_/WAREHOUSE_/CRUISE_REWARDS` -> merchantCredit candidate (Section 2)
- **No retained provenance** (the 15 opencard-only cards) -> a record in
  `promote-refusals-us.json` with a new reason `provenanceWithdrawn`. These are
  not rejected on merit; their evidence left the repo under the licence audit
  and they require re-sourcing from issuer material.

### The rule-3 line, stated

A third-party `category` is **not** D3 evidence. Everything Section 1 produces
lands `status: "draft"` with `earnRules: []` and is never `issuerConfirmed`.
Three independent guards make a mis-routed draft harmless:

- the status guard excludes drafts from every recommendation, so it cannot reach
  a user;
- `CoBrandProgramTests.testEveryCardOnAnUnvaluedProgramIsADraft` holds the other
  end;
- promotion requires reading the issuer's own site, which would catch it.

The classifier **routes**; it never **verifies**. That distinction is the whole
licence for Section 1 to be cheap.

## Section 2 — `merchantCredit`, one programId per brand

### Add alongside, do not fold

**Amended 2026-08-27 after reading the encode side and the Kotlin serializer.**
The original design folded `ctMoney` into `merchantCredit` as a legacy spelling,
on the claim that the engine would get smaller. The three implementations do not
support that claim:

- **Swift** hand-writes its coder, so decoding two spellings into one case is
  trivial — but `ProgramValuation.swift:59` also *encodes*, and a merged case
  must pick one spelling on the way out. `testCtMoneyRoundTrips` and
  `testModernShapeRoundTripsLosslessly` pin this. Staying lossless would require
  the merged payload to carry which spelling it arrived as: a provenance field
  existing purely to preserve bytes.
- **Kotlin** is a `@Serializable sealed class` with `classDiscriminator = "model"`
  and one `@SerialName` per subclass. kotlinx.serialization maps exactly one name
  to one class; two spellings need a hand-written
  `JsonContentPolymorphicSerializer`, in the language with the fewest tests (46).
- **TypeScript** is a union plus a hand-written normalizer, and would be fine
  either way.

So folding trades one enum case for a provenance field plus a custom Kotlin
serializer, and puts the published 2.4 bytes at risk. **`merchantCredit` is
therefore a NEW model declared alongside `ctMoney`, which is left entirely
alone.** The cost is one duplicated line of arithmetic in each of the three
`Scorer`s:

    units * cadPerUnit * (usabilityFactorApplied ? optionalUsabilityFactor : 1)

Deduplicating behaviour is nearly always right; deduplicating a **wire format**
is not the same operation. `ctMoney` and `merchantCredit` are the same
arithmetic under different published names, and a name already shipped inside a
digest-pinned release is a fact about the world, not an implementation detail to
normalize away. The repo already knows this — `CroValuation.redemptionModel`
carries its name for exactly this reason.

No existing test is reworked, and `contracts/programs.json`'s `ctMoney` entry
keeps its bytes.

### Shape

    "gapInc": {
      "model": "merchantCredit",
      "cadPerUnit": <published face value>,
      "optionalUsabilityFactor": <per-brand>,
      "usabilityFactorApplied": true,
      "merchantScope": ["<merchant ids>"],
      "basis": "<issuer fact for face value; stated assumption for the factor>"
    }

The **per-brand usability factor is load-bearing**. A Sam's Club dollar (weekly
groceries) and a Harley-Davidson dollar (a motorcycle every few years) are not
the same dollar. A single shared `storeCredit` value with one factor would
recreate exactly the collapse Option 1 refused.

### Sequencing constraint

`CatalogueIntegrityTests.testEveryProgramDefaultKeyIsARealCatalogueProgramId`
refuses a `programs.json` entry that no card declares. Therefore **enum value +
valuation + cards must land in one commit per brand batch** — the same ratchet
that forced the `noRewards` ordering on 2026-08-27.

## Section 3 — Closed-loop acceptance

### The gap

`network` is `amex|visa|mastercard|discover`, and `Scorer` excludes outright on
`networkNotAccepted` (`Scorer.swift:84`). Kohl's Charge, Sam's Club Credit,
Amazon Store Card, PayPal Credit and CareCredit are private-label: they run on
no network. Landing them requires guessing `network`, which rule 3 forbids. The
gap blocks them under every option including deferral.

The irony worth recording: a closed-loop card is the **sharpest possible**
answer to "which card should I tap right now" — at exactly one merchant it is
often unbeatable — and it is the one card the schema cannot describe.

### The machinery already exists

- `PurchaseContext.merchantBrand: String?` is already a field.
- `RuleMatcher.matches` already has `merchantInclude`/`merchantExclude`
  predicates over it (`RuleMatcher.swift:110-114`).
- `merchant-pack.json` already carries per-merchant `acceptedNetworks`.

Closed-loop acceptance is the same predicate lifted one level: from "which rule
applies to this purchase" up to "is this card usable here at all". No new
Purchase field, no new matching concept — a second acceptance mechanism
alongside network.

### Schema

`network` gains `privateLabel`. `CardProduct` gains an optional:

    "acceptance": { "scope": "closedLoop", "merchants": ["target"] }

Absent implies `openLoop`, which is today's behaviour. **All 85 existing cards
are byte-identical.**

A schema `if/then` makes the pair inseparable: `network: "privateLabel"` if and
only if `acceptance.scope: "closedLoop"`. This removes the redundancy trap —
neither can be declared without the other.

### Scorer

Replacing the guard at `Scorer.swift:84`:

    switch card.acceptance?.scope ?? .openLoop {
    case .openLoop:
        guard purchase.acceptedNetworks.contains(card.network) else {
            return excludedScore(.networkNotAccepted, "\(card.network.rawValue) not accepted")
        }
    case .closedLoop:
        guard let brand = purchase.merchantBrand,
              card.acceptance!.merchants.contains(brand) else {
            return excludedScore(.merchantNotAccepted, "accepted only at ...")
        }
    }

New `Warning.merchantNotAccepted`, distinct from `networkNotAccepted`. "This
card only works at Target" and "Visa isn't accepted here" are different facts
and the UI must not conflate them.

### Two consequences, on the record

1. **`merchantBrand` is optional.** If capture does not resolve a brand, every
   closed-loop card is excluded. That is the correct failure direction — silence
   beats a wrong recommendation — but it means these cards are only ever as good
   as brand resolution. A stated assumption, not a hidden one.
2. **Fail-closed by construction.** If `acceptance` were ever omitted on a
   `privateLabel` card, the openLoop path runs and `acceptedNetworks` never
   contains `privateLabel`, so the card vanishes rather than being recommended
   everywhere. The schema invariant makes this unreachable; the runtime shape
   makes it harmless if it ever were.

## Explicitly out of scope

Deferred to `card-research-queue.json` and `card-data-gaps.json`:

- **Merchant points with no published conversion** — Gap Inc. 5X points,
  Nordstrom Notes, cruise Fun Points / WorldPoints. `merchantCredit` needs a
  published face value; where the issuer publishes none, there is no rate to
  state and rule 3 applies.
- **Target Circle's 5% discount.** It does not earn a currency; it reduces the
  price at the till. No model in `programs.json` covers that, and valuing it at
  face like merchant credit would misstate it. A discount model is a separate
  design.
- **The 15 opencard-only cards**, pending re-sourcing from issuer material.

## Versioning, ordering, verification

Everything is additive: no existing card's score changes, and all 85 existing
records keep their bytes. This is **catalogue 2.5**, not 3.0.

Rule 5 ordering: Swift + fixtures first, then Kotlin, then the TypeScript twin
in MoneyTalks. Rule 6 release dance at the end (bump -> `release-catalogue.sh`
-> commit -> push -> `publish-catalogue.sh` -> MoneyTalks `sync-contracts.sh`).

Minimum three commits, because Section 2's integrity ratchet will not let its
pieces separate:

1. Section 1 — pipeline classifier only, no contract change
2. Section 2 — `merchantCredit` model + per-brand enum values + valuations + cards, one commit per brand batch
3. Section 3 — `privateLabel`, `acceptance`, Scorer, `merchantNotAccepted`

Green baseline to hold: **Swift 276, Kotlin 46, TypeScript 1095**.
`scripts/check-id-permanence.sh` must pass; `idmap.json` stays append-only.
