# Purchase protection — coverage, claims, and the outcome loop

**Status:** Proposed as the shipping target. Owner ruling 2026-09-04: build this version, not the
conservative one. The app is pre-release, so boundary, storage and policy changes are cheap now.

**Supersedes:** the device-only coverage-projection design previously at this path (see *What this
supersedes*, below — several ratified rules must be edited, not quietly ignored).

**Not yet done:** the ratified-document edits this design requires. Until those land, this document
and `2026-09-04-purchase-decision-architecture-design.md` disagree, and the older one is still the
one the code implements.

**Research result 2026-09-04 — RED.** The public-source feasibility study
([`card-benefit-claim-outcome-sources`](../../research/2026-09-04-card-benefit-claim-outcome-sources.md))
found **zero issuer-attributable shopping-benefit claim outcomes** in Canadian institutional
sources. Layer 5 cannot be cold-started from public data. Layers 0–4 are unaffected; Layers 5–6 now
sit behind a data gate rather than a position in the build order. The study also changed the
conditioning variable — see *Layer 5*.

## Thesis

PickMe's protection advice is currently unfalsifiable. It tells the owner a card *has* purchase
protection, then never learns whether that protection was worth anything. Every attempt to price it
runs into the same wall — the existing purchase-decision architecture refuses to convert coverage
into dollars because the numbers would be invented, and it is right to refuse.

The way past the wall is not a better model. It is **owning the whole loop**:

```text
recommendation → purchase → receipt → item identity → loss → claim → OUTCOME
        ^                                                              |
        +--------------- learned priors, per card, per benefit --------+
```

Once outcomes come back, protection has a measured dollar value instead of a modelled one. That is
the product: PickMe becomes the only thing that knows *which adjudicators actually pay*, not which
issuers promise to. No issuer publishes it. Every comparison site infers it from certificate prose,
which describes what is owed, not what is paid.

**This is a multi-year bet earned from first-party claims, not a launch capability.** The 2026-09-04
research established that no public dataset can seed it. Layers 1–4 must therefore be worth building
on their own merits — they are — and Layer 5 is what they compound into if the app lasts.

Coverage records are a step on the way, not the destination.

## What changed, and what it costs

The previous design was shaped by four constraints. Three are now lifted by owner ruling and one is
not a constraint at all.

| Constraint | Status | Consequence |
|---|---|---|
| PickMe owns card semantics, In Unity owns receipts and the purchase spine | **Lifted.** One system, two clients. | Purchases, receipts, coverage and claims live server-side. Card semantics stay in `contracts/` because that is where the Swift engine and the cross-language fixtures already are — moving them buys nothing. |
| Device-only personal data | **Lifted.** | Item-level purchase history, receipt bytes and claim records are held server-side. Priced honestly in *Privacy and legal* below; this is an assumed liability, not a deleted one. |
| Scope discipline (ship the minimum) | **Lifted.** | The outcome loop is the point. A coverage screen alone is not worth the architecture. |
| Local-first | **Not a constraint — a physical fact, correctly scoped.** | Checkout happens at a till, sometimes with no signal, and must stay fully local and offline. A claim happens on a couch three months later and never needed to be. The previous design let the checkout requirement leak onto the claim path for no reason. See *What stays local*. |

## What this supersedes

A design that contradicts ratified documents in silence is a trap for the next agent. These are the
edits this design requires. Each is a real decision, not a formality.

1. **`ECOSYSTEM.md` ownership table** — "`PickMe` must NOT own … dashboards / deep analytics" and
   "`MoneyTalks` … owns purchase spine" both need restating. The new line: In Unity hosts the
   purchase, receipt, coverage and claim spine; PickMe remains the canonical author of card
   semantics and the primary client. This is the *identity* section of that file, so by its own
   precedence rule it must be edited deliberately and synced to all four repos.
2. **`docs/policies/card-ownership.md` (MoneyTalks, C1/D3)** — the prohibition on card facts in
   MoneyTalks stays, and gets *stronger*: structured certificate predicates are card facts and must
   arrive through `contracts/`, never be authored in TypeScript. What changes is that the hub may
   now hold coverage *state* derived from those facts. The `check:cards` guardrail must be extended
   to catch a hand-authored coverage term, not just a hand-authored rate.
3. **Purchase decision architecture D1 and D5** — "benefits must not mutate `decisionValueCad`" and
   "a trade-off is not a negative dollar amount." Both were correct while the number was invented.
   They are replaced, under a new policy version, once the number is measured. The old policy stays
   as a fallback. See *Layer 5*.
4. **Purchase decision architecture D7** — the declared purchase type may now persist. The
   merchant-truth prohibition in D7 survives untouched and is restated as **I4** below.
5. **`docs/policies/product-boundaries.md` (A5)** — analytics on the hub. Still broadly right;
   a coverage list and a claim tracker in the app are not dashboards. A claim-outcome analytics
   surface is, and belongs on the hub.

## Architecture

```text
                    contracts/  (PickMe-authored, versioned, twinned)
        card-catalogue.json · benefits-catalogue.json · certificate-predicates.json
                                      |
        +-----------------------------+-----------------------------+
        |                             |                             |
   Swift engine                  Kotlin twin                  TypeScript twin
   (iOS checkout, local)        (Android)                    (hub, server-side)
        |                                                           |
   local scoring                                            coverage evaluation
   local coverage read                                      claim assembly
        |                                                           |
        +--------------------- In Unity server ---------------------+
                    Purchase · Receipt · Coverage · Claim · Outcome
                                      |
                              derived priors snapshot
                              (learned, never a card fact)
                                      |
                        shipped back to clients for scoring
```

The valuable property of the current architecture — one semantics, three languages, shared fixtures
gating CI — is preserved and extended. What is dropped is the arbitrary rule about which repo may
hold a row.

## Layer 1 — structured certificates

Today `Benefit.conditions` and `Benefit.exclusions` are free prose. Nothing can evaluate
*"eligible original manufacturer warranty must be five years or less."* That single fact is why the
previous design could never say more than "here are the terms."

Structure them: each condition and exclusion becomes a predicate over a purchase and an item —
`itemClass in {jewellery, art, ...} → excluded`, `originalWarrantyYears <= 5 → eligible`,
`chargedFraction == 1.0 → eligible`. A model does the first pass across the 27 cards' certificates;
a human confirms.

**This is the highest-risk layer in the design.** A hallucinated exclusion denies real coverage; a
missed one promises coverage that does not exist, which is the harmful direction. Two controls:

- **Every predicate carries the verbatim certificate sentence it came from.** `Benefit` already has
  a `certificateQuote` field — this is that hook, made mandatory rather than optional. A predicate
  with no quote is unverified by construction and cannot fire.
- **Predicates inherit the existing provenance ladder.** `stub` / `issuerPage` / `certificateVerified`
  already exists and already gates display. A `stub` predicate never produces a coverage answer and
  never enters an expected-value calculation.

## Layer 2 — receipts and item identity

Receipt ingestion into In Unity already exists — `EmailTransaction`, `ReceiptDocument`,
`PurchaseAttachment`, and the whole `src/lib/domain/receipts/` extractor family. What is added is a
model pass that produces **item identity** from the receipt body: product name, class, unit price,
and the manufacturer warranty term inferable from the product.

This is the layer that dissolves the problem every earlier version choked on. The item fact is no
longer something the owner types at a till — it falls out of a receipt they already forwarded.
Consequences:

- `"extended warranty runs to March 2028"` becomes computable, because
  `purchaseDate + manufacturerWarrantyYears + extraYears` finally has all three terms.
- The checkout question ("what are you buying?") stops being load-bearing. Keep it — it still
  resolves the *decision* at the till, which is a different job — but nothing downstream depends on
  it any more.
- Item identity is a **model inference and must be labelled as one**, with the receipt line it came
  from, and must be correctable by the owner. It is not receipt truth and it is not owner testimony.

## Layer 3 — coverage as evaluated state

With Layers 1 and 2, coverage stops being "here are the terms" and becomes an evaluated verdict per
purchase per benefit:

- `covered` — every predicate satisfied, window open;
- `excluded` — a predicate fails, with the verbatim clause that failed;
- `expired` — window closed, with the date it closed;
- `indeterminate` — a predicate needs a fact nobody has, naming which fact.

`indeterminate` is not a failure state and must not be collapsed into `covered`. It is the honest
answer for a purchase whose receipt never arrived, and it is what drives the app to ask.

Coverage is **stored** now, not recomputed on read — because there is a server that can reprocess
it. But it stores a `derivedFromContractVersion`, and a certificate change triggers re-evaluation of
every affected record. The staleness objection that killed the stored version in the previous design
is answered by reprocessing, not by avoidance. In Unity already has this pattern in
`email-fact-reprocess`; reuse it rather than inventing a second one.

## Layer 4 — claims, and the data they generate

Assemble the claim: receipt, statement line, certificate excerpt, card details, loss description,
pre-filled into the issuer's actual form. **Then stop and let the owner review and submit.** Not a
safety hedge — a correctness one. A wrong insurance claim submitted automatically is at best a
denial that poisons the outcome data and at worst something worse than a denial.

The reason most covered people never claim is that the process is tedious, not that they do not know
they are covered. Removing the tedium is where the owner's actual money is.

And every claim writes the record this whole design exists for:

| Captured | Why |
|---|---|
| **adjudicator** — underwriter and claims administrator | the real conditioning variable; see Layer 5 |
| card, benefit, item class, purchase amount | secondary conditioning; the card selects the adjudicator |
| filed date, loss date | timeliness, and whether notice windows are the real killer |
| outcome: approved / partial / denied / abandoned | the label |
| amount paid, days to settle | payout ratio and friction |
| denial reason, structured + verbatim | valuable when it arrives, but see the caution below |

**Friction is the near-term signal, not approval rate.** Every claim produces a settlement time and
an abandonment flag; only denials produce a denial reason, and only many denials in one cell produce
an approval rate. The research found reported settlement ranging from next-business-day to a cheque
roughly three months later, and at least one Amex extended-warranty claim abandoned mid-process
(*"In the end I gave up"*). A benefit the owner abandons is worth zero regardless of whether it would
have been approved — so time-to-settle and abandonment rate become useful at far lower sample sizes
than approval rate, and nobody else publishes them.

`abandoned` therefore matters more than `denied`, not merely as much.

**Caution on denial reasons.** The research assessed the public record as narrative and procedural
rather than clause-citing — *"clause-level precision is usually absent."* First-party final-position
letters may be better, since the owner receives the insurer's actual written decision, but do not
assume a clean clause-to-exclusion mapping will materialise. Design the field to hold verbatim text
first and structure second.

## Layer 5 — expected protection value

With outcomes, protection becomes money. The formulation that matters:

```text
E[protection] = P(claim | item class) × P(approved | adjudicator, benefit, item class) × E[payout | approved]
```

**Condition on the adjudicator, not the card.** This is the most useful thing the 2026-09-04 research
produced. Claims are decided by underwriters and administrators, not by banks — TD purchase security
is underwritten by TD Home and Auto with Global Excel adjudicating, BMO uses CUMIS with Allianz,
Amex Canada uses Belair, and Scotiabank states outright that it is not an insurer. Administrators are
**shared across issuers**, so claim behaviour clusters by adjudicator.

Two consequences. First, a per-card prior would be the wrong model even with unlimited data. Second,
and more usefully, pooling by adjudicator collapses the catalogue's ~145 products into roughly
8–12 deciding entities, cutting the sample size Layer 5 needs by close to an order of magnitude. It
is the single change that moves Layer 5 from implausible to merely distant.

This makes **underwriter and claims administrator per card a required catalogue field.**
`CertificateProvenance.underwriter` already exists and is unpopulated; a sibling `claimsAdministrator`
is needed. Both are printed in the certificates Layer 1 already parses, so this is nearly free if
captured during that pass — and expensive to backfill later. Capture it in Layer 1.

Note what this deliberately is **not**: it is not `P(loss)`. You cannot observe losses — you observe
claims. Trying to estimate loss frequency would reintroduce exactly the invented number the current
architecture forbids. But every term above *is* observable, because the purchase spine gives you the
denominator: you know every purchase, and you know which ones produced a claim. The quantity the
owner actually cares about is what they will be *paid*, and payment requires a claim, so the claim
rate is the correct term rather than an approximation of the wrong one.

It also personalises honestly: someone who never bothers to claim gets a lower protection value,
because for them it is worth less.

This is the point at which D1 and D5 are replaced — as a new policy version, alongside the old, with
the deterministic conservative policy kept as fallback. The migration protocol already written in
the purchase-decision doc applies unchanged and is good; follow it.

The merged number must stay decomposed in the UI: **"$12 rewards + $8 protection"**, never "$20."
The whole reason the current design is trustworthy is that the owner can see which part is which.

## Invariants

Replaceable implementation lives in the layers above. These do not move.

### I1 — A predicate without a certificate quote cannot fire

Structured conditions are machine-readable claims about a legal document. Every one carries the
sentence it came from, and an unquoted or `stub` predicate produces no coverage verdict and no
expected value.

### I2 — Coverage verdicts carry their contract version and are reprocessed, never left stale

A stored `covered` that outlived the certificate it was derived from is the one failure mode that
actively harms the owner. Re-evaluation on contract change is mandatory, not a background nicety.

### I3 — Model inferences are labelled, sourced, and correctable

Item identity from a receipt and predicates from a certificate are both inferences. Each shows what
it was derived from and can be overridden by the owner. An inference is never displayed as issuer
fact or owner testimony.

### I4 — Item and purchase facts never become merchant truth

Inherited intact from D7, and it survives every other change here. A declared or inferred item does
not train the merchant graph, does not enter community MCC evidence, and does not become a
merchant-wide fact. The item is not the merchant.

### I5 — Learned priors are never mixed into issuer facts

Approval rates and payout ratios are observations about issuer *behaviour*. They ship as a separate
versioned artifact with its own provenance, never written into `benefits-catalogue.json`. The
existing separation of policy version from issuer facts (D6) is the precedent and it is a good one.

### I6 — No dollar value is shown until its interval is tight enough to change a decision

An expected protection value computed from four claims is noise wearing a dollar sign. Below a
minimum sample, show the coverage verdict and suppress the number. Ship the confidence interval
alongside the estimate, always.

### I7 — Aggregate priors must not be a channel for one person's claim

A cell of (card × benefit × item class) with n=1 is a single owner's claim history republished to
every other user. Suppress below a minimum cell size; do not rely on aggregation alone to anonymise.

### I8 — Claims are assembled, never auto-submitted

The owner reviews and submits. A pre-filled form is the deliverable.

### I9 — Erasure is complete and is built first

One gesture removes purchases, receipt bytes, item inferences, coverage records, claims, outcomes,
and the owner's contribution to derived priors. Hard delete, not soft. See *Privacy and legal*.

### I10 — Checkout works with no account and no network

Non-negotiable and unaffected by everything above.

## The binding constraint: cold start — settled, and it is RED

This was the gating question. It has been answered and the answer is no. Full study:
[`2026-09-04-card-benefit-claim-outcome-sources.md`](../../research/2026-09-04-card-benefit-claim-outcome-sources.md).

**Zero issuer-attributable purchase-protection or extended-warranty outcomes were located in
Canadian institutional sources** across OBSI, GIO, OLHI, AMF, FCAC, CanLII and OSFI filings. Layer 5
has no public cold start.

Three findings matter more than the headline count:

1. **OBSI was the wrong door, and the right door is structurally closed.** A denied card-benefit
   claim is a dispute with the *insurer* named in the certificate, not the bank; OBSI's Terms of
   Reference exclude affiliates whose main business is insurance. The bodies that do see the merits —
   GIO and OLHI — anonymise the carrier. GIO has precisely the case this design would want, a card
   cell-phone claim denied on notice timing and reversed on documents, and identifies the carrier
   only as "the Insurer." **The process that produces the useful narrative is the process that strips
   the conditioning variable.** More searching does not fix that.
2. **Denial reasons fail independently of volume.** The public record is narrative and procedural
   rather than clause-citing, so even a large anecdote corpus would leave the richest intended field
   mostly null. Both kill criteria fired.
3. **The legal gate and the statistical gate agree, so do not fight the legal one.** Reddit holds the
   densest attributable anecdotes and its terms bar systematic collection without agreement. Pursuing
   permission is not worth it: a corpus of voluntary posts is selection-biased in exactly the
   direction that matters. Even lawfully obtained, it would mislead.

**Consequence for the build.** Layers 5 and 6 leave the numbered sequence and sit behind a **data
gate**: no expected-value model, and no dollar figure shown, until observed first-party outcomes
clear the minimum cell size under I6 and I7 — counted **per adjudicator**, which is what makes the
threshold reachable at all. Until then Layer 4 accumulates, and the app ships Layers 0–4 on their own
merits.

**The one path that could flip this to amber** is not a search — it is a request. Ask GIO and OLHI
directly whether they can supply de-identified records that *retain* insurer, benefit type, outcome
and reason. That targets the anonymisation problem head-on and costs an email. It is an
owner-initiated outward request, not agent work. Direct underwriter requests (Belair, Allianz,
Global Excel, CUMIS) are the same shape and much likelier to be declined.

## Privacy and legal — the assumed cost

Stated once, factually, then not repeated.

Server-side item-level purchase history, receipt bytes and claim records constitute sensitive
personal information under PIPEDA. Rewriting the policy does not rewrite these:

- breach notification obligations, on a dataset that is now worth breaching;
- discoverability in litigation, and exposure to subpoena — including from insurers, given that this
  dataset is *about* insurers;
- access and deletion rights the owner is obliged to satisfy on request;
- consent that must be specific about model processing of receipt contents.

Cheap now, expensive later — do all of these before ingesting a single receipt:

1. **The deletion path before the ingestion path.** This is the one thing that genuinely cannot be
   retrofitted once data is spread across tables, blob storage, model outputs and derived priors.
   "The app is early" is the argument for building this now, not for deferring it.
2. Encryption at rest with per-user keys; receipt blobs behind short-lived signed URLs.
3. Receipt content never in logs, never in error reports, never in analytics events.
4. A retention default that drops receipt bytes and item inferences once every coverage window they
   feed has closed plus the claim-notice period. Keep the coverage outcome, which is what the model
   needs; drop the receipt, which is what the breach wants.

One relationship consequence worth naming rather than discovering: a dataset of which issuers
actually pay is adversarial to the issuers whose cards the catalogue depends on. That may be the
most valuable thing here. It is still a choice being made.

## What stays local

Checkout. Entirely. Merchant recognition, MCC resolution, scoring, the reward answer, the protection
trade-off at the till — all on device, all offline, no account. The engine and contracts already
ship in the binary and nothing in this design changes that.

Coverage lookup should also degrade gracefully offline by caching the owner's own coverage records
on device. Claim assembly and outcome capture are online-only and that is fine.

## Build order

0. **Erasure path and retention job.** Before any ingestion. (I9)
1. **Structured certificate predicates** for the 27 cards, quote-backed, in `contracts/`, twinned,
   fixture-gated — **and capture underwriter plus claims administrator in the same pass.** Useful
   immediately: it upgrades today's protection lens from prose to evaluated verdicts with no new
   personal data at all, and the adjudicator fields are nearly free now and expensive to backfill.
2. **The ratified-document edits** listed above. Do these before shipping code that contradicts them.
3. **Receipt → item identity**, on top of In Unity's existing ingestion.
4. **Coverage records + reprocess-on-contract-change**, reusing the `email-fact-reprocess` pattern.
5. **Claim assembly and outcome capture**, capturing adjudicator, settlement time and abandonment
   from the first claim onward.

Then stop. The remaining two are **gated on data, not on sequence**, and may wait years:

- **Priors per adjudicator**, with intervals, once cell sizes clear I6 and I7.
- **New decision policy version** that spends protection dollars in the score, old policy retained
  as fallback.

Step 1 is worth doing even if the owner later abandons everything after step 3 — it makes the
existing shipped protection lens better on its own terms. Under the RED verdict that is no longer a
hedge but the likely near-term reality.

## What would still make this fail

1. **Cold start never resolves — now the live case, not a hypothetical.** The public seed is
   confirmed unavailable, so Layer 5 depends entirely on first-party volume the app does not yet
   have. The realistic outcome is a good coverage-and-claims tracker with an unfulfilled thesis.
   Everything downstream should be judged on whether Layers 1–4 justify themselves alone.
2. **Receipt coverage is thin.** Item identity requires the receipt. If most purchases never produce
   an ingestible receipt — in-store, cash-adjacent, no email — then `indeterminate` becomes the
   normal answer and the screen is mostly blank.
3. **Denial reasons turn out to be uninformative.** If issuers deny with boilerplate rather than a
   citable clause, the most valuable column in the schema is noise, and the model learns a rate
   without a reason — much less useful and much harder to explain.
4. **Predicate extraction is not reliable enough.** If human confirmation of the 27 certificates
   shows the model gets exclusions materially wrong, Layer 1 collapses back to prose display, and
   Layers 3 and 5 lose their footing with it.
5. **The liability outgrows the product before the data does.** Holding this dataset for a small
   user base is the worst point on the curve: full obligation, no statistical power.

## Unsettled

1. ~~Whether public sources can seed priors~~ — **answered 2026-09-04: no.** See the cold-start
   section. What remains open is whether a direct de-identified data request to GIO or OLHI can
   return records retaining insurer, benefit, outcome and reason.
2. Whether structured predicates belong in `benefits-catalogue.json` or a sibling
   `certificate-predicates.json`. Leaning sibling: different provenance cadence, different review
   process, and the benefits catalogue stays readable.
3. Where coverage evaluation runs when the client is offline — cached verdicts, or a Swift evaluator
   over cached predicates. The second is more work and strictly better.
4. Whether the checkout purchase-type question survives at all once receipts supply item identity.
   It serves a different job (resolving the decision now), but it may not be worth the tap.
5. Whether item inference should run on-device with a small model instead of server-side, which
   would take most of the privacy cost back off the table at some accuracy cost. Worth a real look
   before Layer 2 is built the obvious way.
6. How a partial payout is scored — an approved claim settled at 40% is not a clean success label.

## Testing contract

- A predicate without a certificate quote never produces a coverage verdict.
- A `stub` benefit produces neither a verdict nor an expected value.
- A failing exclusion returns `excluded` **with the verbatim clause**, never a bare boolean.
- A missing fact returns `indeterminate` naming the fact, never `covered`.
- A contract version bump re-evaluates every affected coverage record.
- Erasure removes purchases, receipts, inferences, coverage, claims, outcomes, and the owner's
  contribution to every derived prior.
- An expected protection value below the minimum sample is suppressed, not rounded.
- A prior cell below the minimum size is suppressed.
- Checkout scores correctly with no network and no account.
- Swift, Kotlin and TypeScript agree on predicate evaluation for the shared fixtures.

Gate, unchanged:

```bash
(cd Engine && swift test) && (cd android && ./gradlew :core:engine:test)
```
