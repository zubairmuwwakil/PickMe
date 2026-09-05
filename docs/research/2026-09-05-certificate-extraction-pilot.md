# Certificate extraction pilot — schema proof and contract defects

**Date:** 2026-09-05  
**Status:** pilot complete; schema proposed, not yet implemented. No contract bytes changed.  
**Scope:** 3 of 55 benefit-bearing cards, read from their own certificates of insurance.  
**Purpose:** prove the predicate + adjudicator schema against real certificate text before 52 more
cards are authored against it.

## Headline

The schema is proved and needed changing: **adjudication attaches per benefit, not per card**, and
insurer must be modelled separately from claims administrator. The three pilot cards produced three
structurally different shapes, which is why one card would not have been enough.

The pilot also found **eight defects in shipped contract data across these three cards**, all at
`issuerPage` verification. The shopping-benefit catalogue needs a re-verification pass, not merely
an extension.

## Evidence rule

Every claim below is quoted from the card's own certificate of insurance, fetched from the URL
already recorded in `contracts/benefits-catalogue.json`. Page numbers refer to the extracted PDF
text. Where a certificate is silent, this note says silent — it does not infer.

## Finding 1 — three cards, three adjudicator shapes

| Card | Insurer | Claims administrator | Shape |
|---|---|---|---|
| `amex-platinum` | Belair Insurance Company Inc. | none named; claims go to the insurer at 1-800-243-0198 | administrator == insurer |
| `bmo-cashback-world-elite` | CUMIS General Insurance Company | Allianz Global Assistance (registered business name of AZGA Service Canada Inc.), Operations Centre 1 877 704-0341 | one insurer + one administrator, card-wide |
| `td-aeroplan-visa-infinite` | **varies by benefit** — see below | Global Excel Management Inc. for travel; Assurant-affiliated for mobile device | per-benefit insurer, per-benefit administrator |

BMO, verbatim:

> "The insurance products described in this certificate of insurance are underwritten by CUMIS
> General Insurance Company … The insurance is administered by Allianz Global Assistance which is a
> registered business name of AZGA Service Canada Inc."

TD, verbatim, two different benefits in one document:

> "Coverage under this Certificate is provided by: TD Life Insurance Company and TD Home and Auto
> Insurance Company ("Insurer") … Claims administration and adjudication services are provided by:
> Global Excel Management Inc. ("Administrator")"

> "Mobile Device Insurance is underwritten by American Bankers Insurance Company of Florida (the
> "Insurer") under Group Policy No. TDA112020 … The Insurer, its subsidiaries, and affiliates carry
> on business in Canada under the trade name of Assurant®."

**Consequence for the design.** `CertificateProvenance.underwriter` is per card, so it structurally
cannot express TD. Adjudicator identity must move to the benefit. The design document's Layer 5
assumption — condition on the adjudicator — survives, but the field cannot live where it currently
does.

## Finding 2 — `claimNoticeDays` is real, stated, and easy to confuse

Amex Buyer's Assurance, verbatim:

> "The Cardmember must report their claim within 45 days from the date of occurrence."

That is the field the design proposed, confirmed present at least once. **But the pilot also found
the trap:** TD's certificates repeatedly state

> "payment will be made within 60 days after receipt of the required claim forms"

which is the **insurer's** response commitment, not the claimant's notice deadline. These read
almost identically and mean opposite things. Any extraction pass must separate:

- `claimNoticeDays` — the claimant must notify within N days of the loss (a deadline that can void
  coverage);
- `proofDays` — the claimant must submit proof within N days;
- insurer response commitments — **not a coverage term, do not model.**

Neither TD nor BMO surfaced a shopping-benefit claimant notice deadline in this pass. That is
*silent in the sections reviewed*, not *absent*.

## Finding 3 — eight defects in shipped contract data

All three cards are marked `issuerPage`. Each defect is a delta against the card's own certificate.

| # | Card / benefit | Defect |
|---|---|---|
| 1 | `platinum-extended-warranty` | **Missing the charge condition.** Certificate: *"When a Cardmember charges the entire purchase price of an insured item to their Card…"* and *insured item* is defined as one *"for which the full purchase price is charged to the Card."* The catalogue records only the ≤5-year warranty condition. This is precisely the entire-vs-partial distinction the purchase decision architecture is built on. |
| 2 | `platinum-extended-warranty` | **Missing limits.** Certificate: *"limited to a maximum of $10,000 per insured item (not to exceed $25,000 per Cardmember per policy year…)"*. Catalogue records no limit at all. |
| 3 | `platinum-extended-warranty` | **`extraYears: 1` misstates the rule.** Certificate extends the warranty *"for a period of time equal to the duration of the original manufacturer's warranty … up to one additional year."* It is **doubling, capped at one year**. A six-month manufacturer warranty gets six months, not twelve. The catalogue overstates coverage for every warranty under one year. |
| 4 | `platinum-purchase-protection`, `platinum-extended-warranty` | **`exclusions: []`** while the certificate lists roughly 25, including jewellery, used/rebuilt/refurbished goods, perishables, animals, one-of-a-kind products, business property, and warranties exceeding five years. |
| 5 | `platinum-purchase-protection` | **Payout basis not modelled.** Certificate reimburses *"the portion of the insured item that was charged to the Card"* — a partial charge yields a partial payout. |
| 6 | `td-aeroplan-mobile-device` | **Wrong insurer.** Catalogue note says *"Underwritten by TD Home and Auto Insurance Company."* Certificate says American Bankers Insurance Company of Florida under Group Policy TDA112020. |
| 7 | `td-aeroplan-visa-infinite` | **`certificate.underwriter` omits ABIC/Assurant entirely**, so the card-level string is incomplete as well as unstructured. |
| 8 | all six pilot benefits | **`certificateQuote: null`** throughout, though quotable text was readily available in every case. |

Three cards were not selected for suspicion — they were selected to span adjudicator shapes. The
defect rate should be treated as a reason to re-verify, not as an estimate of the whole catalogue.

## Proposed schema

Shape only; field names are free to change. Nothing here is authored yet.

**Adjudicator, at the benefit level:**

```
adjudicator:
  insurerId          stable id from a normalized vocabulary  (belair, cumis, abic-assurant, td-life, …)
  insurerName        verbatim legal name from the certificate
  administratorId    stable id, or equal to insurerId when none is named
  administratorName  verbatim, or null
  claimsPhone / claimsUrl
  groupPolicy        e.g. "FC310000-A", "PSI018966745", "TDA112020"
  quote              the sentence naming these parties
```

`groupPolicy` earns its place: it is the join key back to the exact policy a claim was decided
under, and it changes when the issuer re-papers the program.

**Predicates, per benefit:**

```
predicates:
  - id            charge-full-price | warranty-max-years | item-class-excluded | …
    kind          condition | exclusion
    evaluable     true when it can be tested against a purchase and an item
    expression    structured form, only when evaluable
    quote         REQUIRED, verbatim certificate sentence
    sourcePage
```

`evaluable: false` is expected and fine — "negligence" is a real exclusion that no purchase record
can test. Recording it unevaluated is honest; omitting it is not.

**Claim timing, per benefit:** `claimNoticeDays`, `proofDays`, both nullable, both quote-backed.
Insurer response commitments are deliberately not modelled.

## Recommended sequencing change

The design document's Layer 1 assumed structured predicates were an extension of good data. They
are not — defects 1, 3 and 6 are wrong today and affect the shipped protection comparison. Split:

1. **Re-verify the six shopping-benefit fields already published** (window, limits, charge
   condition, warranty rule) across all 55 cards, quote-backed. This is a correction pass and can
   ship on its own.
2. **Then add** adjudicator, predicates and claim timing as new fields.

Doing 2 without 1 would build evaluable predicates on top of coverage numbers that are wrong.

## Handoff prompt for the remaining 52 cards

Reproduced here so it stays with the pilot that produced it.

---

You are extracting card-benefit facts from Canadian credit-card certificates of insurance for
PickMe. Work from `contracts/benefits-catalogue.json`: each card carries `certificate.sourceUrl`
and a `documents` array with certificate URLs. Read the card's **own certificate**. Do not use
marketing pages, comparison sites, or another card's certificate.

Read `docs/research/2026-09-05-certificate-extraction-pilot.md` first — it defines the schema and
shows three worked shapes.

**Note on tooling:** these PDFs do not parse through page-fetch tools. Download them and extract
text with `pypdf` (installed), then locate sections by keyword. Budget one card at a time.

**Already done — do not redo:** `amex-platinum`, `td-aeroplan-visa-infinite`,
`bmo-cashback-world-elite` (this pilot); `amex-cobalt`, `amex-bonvoy`, `mbna-rewards-we`,
`scotia-momentum-vi-plus`, `tangerine-moneyback-world`, `rogers-red-we`
(`2026-09-05-certificate-extraction-batch-02.md`). **Skip entirely:** `cryptocom-royal-indigo` and
`comenity-aaa-daily-advantage-visa-signature` — both are `stub` with no located certificate, so
there is nothing to read. That leaves **44 cards**. Work in catalogue order and skip any card in
the lists above; "resume after the last card" is not sufficient, because completed cards are not
contiguous.

**Quotes are short anchors, not transcripts.** One sentence per field plus a page locator.
`catalogue-pipeline/RAW_SOURCE_POLICY.md` keeps uncleared third-party expression out of this public
repo and committed files persist in tagged source archives, so name exclusion categories with
locators rather than reproducing full clause lists. Batch 02 got this right.

**Batch size: 6 cards per session, maximum.** These certificates run 50–80 pages each and the
extracted text is large. Attempting the full 52 in one pass will exhaust context and produce
degraded extraction on the later cards, which is worse than fewer cards done properly. Finish a
batch, write its file, stop. A later session picks up the next six.

For each card, for every benefit in the `shopping` family (`purchaseProtection`,
`extendedWarranty`, `mobileDeviceInsurance`), produce:

1. **Adjudicator** — insurer legal name, claims administrator if a *different* company is named,
   claims phone/URL, group policy number, and the verbatim sentence naming them. If no separate
   administrator is named, say so explicitly rather than repeating the insurer's name into that
   field. Attach this **per benefit** — one card can have several insurers.
2. **Verification of the published coverage fields** — window days, per-occurrence and annual
   limits, charge condition (entire price vs any portion), warranty rule. For each, quote the
   certificate and state whether the current catalogue value is correct, wrong, or missing.
3. **Predicates** — every condition and exclusion, each with a verbatim quote and a page number,
   each marked evaluable or not.
4. **Claim timing** — claimant notice deadline and proof deadline, quoted. **Do not confuse these
   with the insurer's own response commitment** (e.g. "payment will be made within 60 days after
   receipt of the required claim forms"), which is not a coverage term and must not be recorded.

**Rules.**

- Every field carries a verbatim quote. No quote, no field.
- Never infer a value from another card, from the issuer's marketing page, or from a sibling
  product. Certificates differ between cards from the same bank.
- Silent is not absent. If the certificate does not state a notice deadline, write "silent in
  sections reviewed."
- Do not edit `contracts/` in this pass. Output findings; contract authoring is a separate,
  gated change under the card-contract-authoring rules.
- Report defects against the current catalogue explicitly — those are the most valuable output.

**Deliverable:** one markdown file per batch under `docs/research/`, following the house style
of the existing files there: hard headline first, an evidence rule, then per-card sections, then a
consolidated defect table.

---

## What this pilot did not do

- No contract bytes were changed, no schema was added, no version was bumped.
- Only the `shopping` family was examined. Travel, rental and medical families are unreviewed.
- BMO and TD shopping-benefit exclusion lists were not fully transcribed; only adjudicator and
  claim-timing structure were confirmed for those two.
- The Amex certificate's remaining families were not reviewed.
