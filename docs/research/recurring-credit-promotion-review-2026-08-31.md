# Recurring-credit promotion review — 2026-08-31

> The missing-pack conclusion in this review is superseded by
> [`recurring-credit-us-remaining-promotion-review-2026-08-31.md`](recurring-credit-us-remaining-promotion-review-2026-08-31.md).
> The row-level decisions for the original base and edge-case packs remain in force.

## Decision

**Bulk promotion is blocked.** The research that is present contains a useful, mostly defensible fixed-credit set, but the current importer is not safe enough to consolidate the packs without over-promoting several shapes that PickMe cannot yet represent exactly.

The requested US remaining pack, `docs/research/issuer-recurring-credit-research-us-remaining-2026-08-31.json`, is **not present on `main`** as of this review. This review therefore must not be used to claim complete US recurring-credit coverage.

For the 47 credit rows in the base research pack that are available for review:

- **7** are safe to retain/promote as currently modeled.
- **22** are factually supportable but need field-level normalization before promotion.
- **18** must remain excluded from production promotion for now.
- Therefore **29 / 47 (61.7%)** are representable with the existing `CardCredit` model after corrections; **18 / 47 (38.3%)** are not production-ready.

Separately, the current canonical catalogue still contains the two Crypto.com Royal Indigo inferred rebate rows that the issuer research explicitly refused to verify. Those two rows should remain quarantined from issuer-confirmed promotion.

No contracts, application code, release files, or importer code were modified by this review.

## Inputs and consolidation status

| Input | Status | Review consequence |
|---|---|---|
| `issuer-recurring-credit-research-2026-08-31.json` | Present | Base pack: 67 card reviews and 47 proposed credit rows. Its global snapshot note references catalogue 2.16, so it is older than the current 2.18 canonical catalogue. |
| `issuer-recurring-credit-research-ca-remaining-2026-08-31.json` | Present | Contains 2 card reviews and 0 credit rows, but both cardIds now also exist in the current base pack. Treat as a newer card-level re-review, not additive coverage. |
| `issuer-recurring-credit-research-us-remaining-2026-08-31.json` | **Missing** | Full requested consolidation cannot be certified; importer must fail closed if this pack is expected. |
| `recurring-credit-edge-case-resolution-2026-08-31.json` | Present | Six exact credit-level resolutions. This pack overrides the base pack for those `(cardId, creditId)` pairs. It promotes 0 of 6. |
| `contracts/card-catalogue.json` | Present, v2.18 | 144 canonical cards. 43 canonical credit rows are currently present. |
| `contracts/schema/card-catalogue.schema.json` | Present | Existing fixed-money `CardCredit` schema is sufficient for the 29 representable rows, but not the blocked shapes below. |
| `import_recurring_credit_research.py` | Present | Currently reads only the base pack and relies on hard-coded exceptions/aliases. It is not a multi-pack consolidation importer. |

### Required precedence

For any future consolidated import, use this order:

1. `recurring-credit-edge-case-resolution-2026-08-31.json` for its six exact credit IDs.
2. Market-specific remaining packs for card-level review metadata and any rows they uniquely contain.
3. Base issuer recurring-credit pack.
4. Canonical catalogue only as the stable-ID/current-product target, never as evidence that an unverified research claim is true.

Conflicts must be explicit errors; later-file-wins silently is not acceptable.

## Counts and coverage statistics

### Research currently available

- Base card reviews: **67**
- Base proposed credit rows: **47**
- CA remaining rows: **2 cards / 0 credits**, both duplicate cardIds already present in the base pack
- Edge-case resolutions: **6 credit claims across 5 cards**, all overlays of base rows
- Net unique reviewed cardIds from the present packs: **67**
- Net unique proposed creditIds from the present packs: **47**

### Canonical catalogue

- Canonical cards: **144**
- Cards currently carrying `creditCoverage`: **67 / 144 (46.5%)**
- Canonical cards without `creditCoverage`: **77 / 144 (53.5%)**
- Current canonical credit rows: **43**

The 43 current canonical rows consist of the base importer’s promoted fixed/high-confidence rows plus the two pre-existing inferred Crypto.com rebates. The importer has therefore already applied much of the base pack, which means several findings below are rollback/quarantine findings rather than merely future import blockers.

### Coverage status among the 67 reviewed cards

| Coverage | Cards | Share |
|---|---:|---:|
| `complete` | 0 | 0% |
| `partial` | 18 | 26.9% |
| `unknown` | 49 | 73.1% |

No present research pack makes a defensible `complete` coverage claim. That conservatism should be preserved.

The CA remaining pack’s statement that it covered “exactly two remaining” Canadian cards is stale relative to the current base pack and current catalogue and must not be used as a coverage denominator.

## Duplicate IDs, conflicts, and stable identifiers

### Duplicate cardIds across packs

The CA remaining pack duplicates these base-pack cardIds:

- `td-cash-back-visa-infinite`
- `rbc-cashback-preferred-we`

Both remaining-pack reviews contain no monetary credit row, so the safe consolidation is to keep the newer card-review metadata/refusals without increasing card counts.

The edge-case pack intentionally repeats these base cardIds and must be treated as an override:

- `amex-platinum`
- `amex-aeroplan-reserve`
- `walmart-rewards-mastercard`
- `walmart-rewards-world-mastercard`
- `american-express-the-platinum-card`

### Duplicate creditIds

No duplicate creditId was found inside the 47-row base proposal set. The six repeated edge-case creditIds are intentional resolution overlays, not additional credits.

### Existing canonical creditIds that should not be renamed

Two base-research rows unnecessarily changed already-established canonical identifiers:

| Research ID | Required canonical ID | Correction |
|---|---|---|
| `amex-gold-dining-monthly` | `amex-gold-dining-credit` | Change the research `creditId`; do not depend on importer aliasing as the permanent normalization path. |
| `amex-plat-us-airline-fee-credit` | `amex-plat-airline-fee-credit` | Change the research `creditId`; preserve the existing canonical ID. |

The importer currently repairs both through `STABLE_ID_ALIASES`; keep those aliases as migration protection, but future research should already use the canonical IDs and the importer should reject unexpected renames.

`capital-one-venture-rewards-credit-card` looks misleading by ID, but the current canonical product name is **Venture X Rewards Credit Card**. Do not rename this cardId as part of recurring-credit work.

## Fee corrections

The two fee corrections in the base research agree with the current canonical catalogue:

- `american-express-the-platinum-card.fee.annual.amount = 895 USD`
- `chase-sapphire-reserve.fee.annual.amount = 795 USD`

These are now no-op assertions against canonical 2.18, not new promotion changes. The importer should not maintain these as unrelated hard-coded side effects; fee corrections should be data-driven and conflict-checked from research.

## Approved as currently modeled

These seven credit rows are representable by the existing schema without a material semantic correction. Account-anniversary rows still depend on owner state where noted, but `CardState.accountOpenedAt` and `CreditAdvisor.scheduleUnresolved` already provide a safe fail-closed path.

| Card | Credit | Decision |
|---|---|---|
| `amex-platinum` | `platinum-dining-credit` | Approve. Fixed C$200 calendar-year credit, minimum transaction and enrollment are representable; no invented MCC/merchant predicate is required. |
| `bmo-eclipse-visa-infinite` | `bmo-eclipse-lifestyle-credit` | Approve. Fixed C$50 anniversary credit after a qualifying C$50+ purchase. Requires `accountOpenedAt` before the advisor can resolve a live window. |
| `national-bank-world-elite` | `nbc-we-travel-credit` | Approve as a non-checkout reimbursement credit. Keep the exact eligible-expense list in usage terms and the claim/proof deadline; do not broaden it to generic travel matching. |
| `american-express-gold-card` | `amex-gold-resy-halfyear` | Approve. Fixed US$50 Jan–Jun / US$50 Jul–Dec windows; generic Resy wording is safely left out of `merchantInclude`. |
| `american-express-the-platinum-card` | `amex-plat-us-resy-quarterly` | Approve. Fixed US$100 calendar-quarter value; no fabricated restaurant list/MCC is required. |
| `chase-sapphire-reserve` | `csr-travel-credit` | Approve. Fixed US$300 account-anniversary travel credit. Requires `accountOpenedAt`; existing engine behavior fails closed when unresolved. |
| `chase-sapphire-reserve` | `csr-dining-halfyear` | Approve as a non-checkout credit. Enrollment/linking and eligible-program restrictions belong in enrollment/usage terms until PickMe has an authoritative restaurant-partner mapping. |

## Records needing correction before promotion

The underlying benefit is supportable for these 22 rows, but the normalized representation should be corrected first.

A recurring pattern is important: **do not slug arbitrary issuer display text into `purchasePredicate.merchantInclude`.** Merchant predicates must resolve to IDs in `contracts/merchant-pack.json`. If a benefit is safely identified by a supported portal channel, use the channel. If neither a canonical merchant ID nor a sufficiently precise channel exists, omit `purchasePredicate` and keep the record as a portfolio/reminder credit rather than creating a false checkout matcher.

| Card / credit | Exact correction |
|---|---|
| `amex-platinum / platinum-travel-credit` | Delete `purchasePredicate.merchantInclude: ["american-express-travel"]`; that token is not in the canonical merchant pack. Retain `channels: ["amexTravel"]`, `categories: ["travel"]`, minimum C$200, and anniversary schedule. Require owner `accountOpenedAt` to resolve the window. |
| `td-first-class-travel-visa-infinite / td-fct-expedia-credit` | Do not use a generated `expedia-for-td` merchant token. Retain `channels: ["expediaForTD"]`, lodging/travel categories and the C$500 minimum. |
| `amex-gold-rewards / gold-travel-credit` | Remove generated American Express Travel merchant text from `merchantInclude`; retain `amexTravel` channel, travel category and C$100 minimum. Require `accountOpenedAt`. |
| `american-express-gold-card / amex-gold-dining-monthly` | Change research `creditId` to `amex-gold-dining-credit`. Resolve every named dining partner through the canonical merchant pack; if any partner lacks a canonical ID, do not invent a slug. Omit checkout predicate until the full active list is mappable. |
| `american-express-gold-card / amex-gold-uber-cash-monthly` | The importer-generated `uber`/`uber-eats` merchant slugs are not authoritative merchant mappings (`uber` is not currently a canonical merchant-pack ID). Remove the merchant predicate until canonical IDs exist; keep partner-account enrollment and usage terms. |
| `american-express-gold-card / amex-gold-dunkin-monthly` | Resolve Dunkin through `merchant-pack.json` before emitting `merchantInclude`; otherwise omit the checkout predicate. |
| `american-express-the-platinum-card / amex-plat-us-airline-fee-credit` | Use existing canonical `creditId = amex-plat-airline-fee-credit`. Keep the selected-airline restriction in enrollment/usage terms; do not invent airline merchant/MCC lists. |
| `american-express-the-platinum-card / amex-plat-us-hotel-halfyear` | Delete program names such as Fine Hotels + Resorts / The Hotel Collection from `merchantInclude`; they are booking-program labels, not canonical merchant IDs. Retain `amexTravel` + `lodging`; keep the THC two-night condition in usage terms. |
| `american-express-the-platinum-card / amex-plat-us-uber-cash-monthly` | Remove noncanonical Uber merchant slugs until merchant mapping exists; retain partner-account enrollment and U.S.-use restrictions. |
| `american-express-the-platinum-card / amex-plat-us-uber-one-annual` | Resolve Uber canonically or omit `merchantInclude`; retain partner-account/payment-setup restrictions and account-level annual cap disclosure. |
| `american-express-the-platinum-card / amex-plat-us-clear-annual` | Resolve CLEAR+ through the canonical merchant pack before adding a merchant predicate; otherwise keep it portfolio-only. |
| `american-express-the-platinum-card / amex-plat-us-digital-entertainment-monthly` | Replace generated display-name slugs with canonical merchant IDs only. Concrete mismatch: issuer text `Disney+` is slugged to `disney-plus`, while PickMe’s canonical merchant ID is `disney`. Any provider not in the merchant pack must not be invented. |
| `american-express-the-platinum-card / amex-plat-us-lululemon-quarterly` | Resolve lululemon through canonical merchant data or omit checkout predicate. Preserve outlet/direct-channel exclusions in usage terms. |
| `american-express-the-platinum-card / amex-plat-us-oura-annual` | Resolve Oura through canonical merchant data or omit checkout predicate; preserve `ouraring.com` direct-purchase rule in usage terms. |
| `american-express-the-platinum-card / amex-plat-us-equinox-annual` | Resolve Equinox / Equinox+ through canonical merchant data or omit checkout predicate; do not create two free-form merchant slugs. |
| `chase-sapphire-preferred-card / csp-hotel-credit` | Delete generated `chase-travel` merchant token; retain `channels: ["chaseTravel"]` and `lodging`. Require owner `accountOpenedAt`. |
| `chase-sapphire-preferred-card / csp-doordash-nonrestaurant-monthly` | Do not rely on grocery/retail categories to infer what was inside a DoorDash order from a DoorDash card transaction. Keep value, effectiveTo, enrollment and usage terms, but omit `purchasePredicate` until PickMe can distinguish restaurant vs non-restaurant DoorDash orders. |
| `chase-sapphire-reserve / csr-select-hotels-2026-credit` | Keep `effectiveFrom=2026-01-01` and `effectiveTo=2026-12-31`. Do not slug hotel-brand names into merchant IDs. Unless every eligible brand can be mapped authoritatively, omit `purchasePredicate`; retain the precise brand/two-night/Pay Now restrictions in usage terms. |
| `chase-sapphire-reserve / csr-stubhub-halfyear` | Set `schedule.resetTimeZone` from `America/New_York` to null/absent unless an issuer term explicitly establishes the cutoff timezone. Resolve StubHub/viagogo via canonical merchant IDs or omit checkout predicate. Keep `effectiveTo=2027-12-31`. |
| `chase-sapphire-reserve / csr-lyft-monthly` | Resolve Lyft through canonical merchant data or omit checkout predicate. Set `eligibility.accountLevelLimit=true` because the research evidence describes the first eligible account user who links the card receiving the account benefit; do not imply a separate US$10 allowance for each authorized user. Keep `effectiveTo=2027-09-30`. |
| `chase-sapphire-reserve / csr-peloton-monthly` | Current keyword inference collapses a multi-step setup into `partnerAccount`. Normalize `enrollment.channel=issuerPortal`, keep the Chase URL, and put the required Peloton sign-in/payment setup in `enrollment.instructions`. Resolve Peloton canonically or omit checkout predicate. Keep `effectiveTo=2027-12-31`. |
| `chase-sapphire-reserve / csr-doordash-restaurant-monthly` | Keep value/effectiveTo/enrollment, but omit `purchasePredicate` until PickMe can distinguish restaurant from non-restaurant DoorDash orders using an authoritative transaction/basket signal. |

## Records that must remain excluded from production promotion

These 18 base-pack rows should not be promoted as production `CardCredit` rows now.

| Card / credit | Disposition | Reason |
|---|---|---|
| `amex-platinum / platinum-nexus-credit` | Exclude | Edge-case resolution confirms a legacy fixed cohort schedule plus anniversary-based newer cohorts. Generic `accountAnniversary/48 months` loses the cohort selector and is not defensible. |
| `amex-aeroplan-reserve / amex-aeroplan-reserve-nexus-credit` | Exclude | Same cohort/new-account split as the Canadian Platinum NEXUS benefit. |
| `walmart-rewards-mastercard / walmart-rewards-annual-walmart-plus-credit` | **Move to benefits** | Value is 3/12 of the current regular annual Walmart+ plan plus attributable taxes, not fixed `Money`. Edge-case pack explicitly rejects a fixed CAD amount. |
| `walmart-rewards-world-mastercard / walmart-rewards-world-annual-walmart-plus-credit` | **Move to benefits** | Value is 6/12 of the current regular annual Walmart+ plan plus attributable taxes, not fixed `Money`. |
| `american-express-the-platinum-card / amex-plat-us-global-entry-credit` | Exclude | Shared first-charge-wins allowance with TSA PreCheck, per eligible Basic/Additional card; current schema cannot model shared alternatives. Edge resolution also anchors frequency to the qualifying transaction, not generic last redemption. |
| `american-express-the-platinum-card / amex-plat-us-tsa-precheck-credit` | Exclude | Same shared allowance. Edge resolution corrects the earlier 54-month interpretation to 48 months under the controlling current terms. Do not keep two independent credits. |
| `td-aeroplan-visa-infinite / td-aeroplan-vi-nexus-credit` | Exclude | TD starts the 48-month period when the first qualifying fee posts. `CreditAdvisor` currently anchors rolling schedules to `lastRedemptionAt`. The research also describes cardholder-count-dependent availability that `accountLevelLimit: bool` cannot express. |
| `cibc-aventura-visa-infinite / cibc-aventura-vi-nexus-credit` | Exclude | Amount/effectiveFrom are supportable (C$200 from 2025-07-01), but the public research established “every four years” without a defensible anchor. Do not invent last-redemption semantics. |
| `td-aeroplan-visa-infinite-privilege / td-aeroplan-vip-nexus-credit` | Exclude | Same first-qualifying-fee-post rolling-anchor mismatch as TD’s other NEXUS implementation; additional-card/account-limit semantics also need an exact limit model. |
| `cibc-aeroplan-visa-infinite-privilege / cibc-aeroplan-vip-nexus-credit` | Exclude | C$200 amount/effectiveFrom are supportable; rolling anchor remains under-specified for the current `lastRedemptionAt` engine semantics. |
| `chase-sapphire-preferred-card / csp-trusted-traveler-credit` | Exclude | “Once every four years” is not enough to assert that PickMe’s `lastRedemptionAt + 48 months` is the issuer’s eligibility anchor. Resolve transaction-vs-credit-posting semantics first. |
| `chase-sapphire-reserve / csr-trusted-traveler-credit` | Exclude | Same rolling-anchor ambiguity. |
| `capital-one-venture-rewards-credit-card / venture-x-trusted-traveler-credit` | Exclude | Same rolling-anchor ambiguity; parent card is also currently draft. |
| `american-express-the-platinum-card / amex-plat-us-uber-cash-december-bonus` | Exclude | Current schema can express annual or monthly cadence but not an additional amount available only in December. A calendar-year row would make the US$20 appear usable outside December. |
| `american-express-the-platinum-card / amex-plat-us-walmart-plus-monthly` | Move to benefits unless schema changes | The row stores US$12.95, but issuer wording also credits applicable taxes. `CardCredit.value` is defined as the issuer maximum per window; a tax-varying maximum is not exact fixed `Money`. |
| `chase-sapphire-reserve / csr-the-edit-credit` | Exclude | Research states US$500 annual total with a US$250 per-booking cap. `perTransactionCreditCap` is present only in research metadata and is dropped by the importer/schema, which can overstate a single booking by 2×. |
| `chase-sapphire-reserve / csr-doordash-nonrestaurant-monthly` | Exclude | US$20 is delivered as **two separate US$10 promos**. Current schema/importer collapses them into one US$20 balance and loses denomination/use-count semantics. |
| `capital-one-venture-rewards-credit-card / venture-x-capital-one-travel-credit` | Draft-only; do not promote to production | The record itself is representable after removing a generated Capital One Travel merchant token and using `capitalOneTravel` channel + `accountOpenedAt`, but the canonical Venture X product is still `status=draft`. Keep it out of production promotion until the parent card is deliberately published. |

### Existing canonical rows that should remain quarantined

These rows are not issuer-verified by the recurring-credit research and should not be upgraded or counted as production-ready issuer-confirmed credits:

- `cryptocom-royal-indigo / cro-indigo-spotify-rebate`
- `cryptocom-royal-indigo / cro-indigo-netflix-rebate`

Both remain `sourceType=inferred` and lack credit-level issuer evidence sufficient to verify the exact current amount/cadence/ongoing availability.

### Already-canonical rows that this review would block or quarantine

Because the base importer has already run, at least these **10 published research-derived rows** are currently canonical but should not be treated as production-ready under the stricter semantics above:

- `td-aeroplan-vi-nexus-credit`
- `cibc-aventura-vi-nexus-credit`
- `td-aeroplan-vip-nexus-credit`
- `cibc-aeroplan-vip-nexus-credit`
- `amex-plat-us-uber-cash-december-bonus`
- `amex-plat-us-walmart-plus-monthly`
- `csp-trusted-traveler-credit`
- `csr-the-edit-credit`
- `csr-trusted-traveler-credit`
- `csr-doordash-nonrestaurant-monthly`

Together with the two inferred Crypto.com rows, that is **12 published canonical credit rows requiring quarantine/correction before release**. The two Venture X rows are on a draft card and therefore should remain draft-only.

## Audit against the requested failure modes

### Unsupported high-confidence claims

The main problem is not the sourced amounts; it is row-level confidence being applied to details that were not equally established.

- CIBC “every four years” rows should not convert that phrase into a high-confidence `lastRedemptionAt` rolling anchor.
- `csr-stubhub-halfyear.schedule.resetTimeZone = America/New_York` is not supported by the evidence text in the research row and should be removed unless explicit issuer terms establish it.
- Merchant IDs and enrollment enum values created by importer heuristics are normalization inventions, not issuer facts.
- The edge-case pack is authoritative for the six disputed rows and correctly separates “fact verified” from “safe to promote”: all six are high-confidence facts, but zero are promotable under the current model.

### Issuer URLs

All 47 base proposed credit rows include issuer-source URLs in their research records. The edge-case resolutions also include issuer evidence. No missing credit-level issuer URL was found among the present proposed rows.

Exceptions/limits:

- The two Crypto.com canonical inferred rows are not supported as issuer-confirmed credit rows by this research pass.
- The missing US remaining pack cannot be audited for source completeness.
- Partner enrollment URLs such as OpenTable/Lyft are not substitutes for the issuer `sources` field; issuer evidence must remain attached separately.

### MCCs

No proposed recurring-credit row in the present base pack relies on an invented MCC. Research MCC arrays are empty unless explicitly sourced, and the global research finding correctly refuses MCC inference. Preserve that behavior.

### Reset time zones

Do not assign a reset timezone unless the issuer source states a cutoff that requires it. `csr-stubhub-halfyear` is the present correction candidate; otherwise null/absent reset timezone is preferable to an invented zone.

### Category identifiers

No invalid normalized category identifier was found in the currently promoted credit output under the importer’s current map. The raw research intentionally uses semantic labels such as `membership`, `rideshare`, `wellness`, `trustedTravelerApplicationFee`, and airline-fee subtypes that the importer maps to PickMe categories.

The problem is that the importer passes **unknown** research categories through unchanged. Change this to a closed validation against `contracts/purchase-categories.json` (plus explicitly allowed rule-side categories where applicable). Unknown values must fail the import, not silently become new category IDs.

### Merchant tokens

The current importer’s `slug()` + `concrete_merchants()` path is unsafe.

Concrete examples:

- `American Express Travel` becomes `american-express-travel`, which is not in `merchant-pack.json`; the correct machine dimension is `amexTravel` channel.
- `Disney+` becomes `disney-plus`, while PickMe’s canonical merchant ID is `disney`.
- `Uber` currently has no canonical merchant-pack ID, so emitting `uber` creates a predicate that PickMe cannot resolve reliably.
- Portal/program labels such as Chase Travel, Capital One Travel, Fine Hotels + Resorts and The Edit are not ordinary merchant IDs and should be modeled as channels/program restrictions rather than slugged merchant tokens.

Only emit `merchantInclude` from an explicit canonical merchant resolver.

### Enrollment channels

The importer currently guesses an enum by keyword. That should stop. Use explicit normalized mapping from the research field and fail/omit when the source does not establish the channel.

Known correction: `csr-peloton-monthly` requires issuer activation plus Peloton setup; keyword ordering currently collapses this into `partnerAccount`. Use issuer activation as the primary channel and put the partner step in instructions unless/until enrollment becomes a multi-step model.

### Temporary credits and effectiveTo

The time-limited rows in the present pack that were identified as temporary have explicit end dates, including:

- CSP DoorDash: `2027-12-31`
- CSR select hotels: `2026-12-31`
- CSR StubHub/viagogo: `2027-12-31`
- CSR Lyft: `2027-09-30`
- CSR Peloton: `2027-12-31`
- CSR DoorDash promos: `2027-12-31`

No currently identified temporary credit should be promoted without `effectiveTo`. Add an importer assertion so future omissions fail before writing the contract.

Saks on U.S. Platinum correctly remains historical only, with the research noting an end on `2026-06-30`; it should not be reintroduced as a current credit.

### Currency and market

No CAD/USD market mismatch was found in the 47 present proposed credit rows:

- Canadian card credits are denominated CAD.
- U.S. card credits are denominated USD.
- Venture X is a U.S./USD draft product despite its legacy-looking cardId.

The importer should still validate `credit.value.currency == card.billingCurrency` unless an explicit issuer-denominated exception is supported by schema and evidence.

## Account-anniversary requirements

The current engine already supports the correct fail-closed state model: `CardState.accountOpenedAt` exists, and `CreditAdvisor` returns `scheduleUnresolved` if an account-anniversary credit lacks that owner fact.

These representable rows require `accountOpenedAt` before PickMe can show a resolved live window:

- `amex-platinum / platinum-travel-credit`
- `bmo-eclipse-visa-infinite / bmo-eclipse-lifestyle-credit`
- `amex-gold-rewards / gold-travel-credit`
- `chase-sapphire-preferred-card / csp-hotel-credit`
- `chase-sapphire-reserve / csr-travel-credit`
- `capital-one-venture-rewards-credit-card / venture-x-capital-one-travel-credit` (draft-only)

Do **not** substitute application date, catalogue effectiveFrom, first observed transaction, or research date for `accountOpenedAt`.

The two Canadian Amex NEXUS benefits are not solved merely by collecting `accountOpenedAt`, because legacy cardholders use issuer-defined fixed cohorts. Keep them blocked pending a deliberate cohort/owner-state design.

## Rolling-credit semantics

This is the largest semantic blocker.

`CreditAdvisor` currently interprets rolling schedules as:

> next eligible date = `CreditState.lastRedemptionAt + intervalMonths`

That is only valid where issuer eligibility is actually anchored to the successful prior redemption/credit event.

The research instead contains multiple other shapes:

- TD: 48 months begins when the first qualifying NEXUS fee **posts**.
- Edge-case U.S. Amex: shared benefit is anchored to the qualifying merchant-reported application-fee transaction.
- CIBC/Chase/Capital One base rows often establish “once every four years” but do not establish enough detail to equate that with PickMe’s `lastRedemptionAt`.

Until anchor semantics are resolved, the rolling rows listed in the exclusion table must remain blocked.

## Recommended importer changes

The importer should be changed before another promotion run. Recommended order:

1. **Add an explicit pack manifest.** Read base + CA remaining + US remaining + edge resolutions. If a required pack is missing, exit non-zero before mutation.
2. **Build a consolidation phase before transformation.** Key cards by `cardId` and credits by `(cardId, creditId)`. Apply explicit precedence, report duplicates and fail on unapproved conflicts in amount, currency, cadence, effective dates, merchant restrictions, enrollment, or sources.
3. **Apply edge-case dispositions as data.** Support `promote`, `blocked`, and `moveToBenefits`/equivalent review disposition rather than maintaining only two hard-coded `BLOCKED_COHORTS` tuples.
4. **Do not wholesale replace `card["credits"]` from a partial research pack.** Merge by stable `creditId`; only remove a canonical row when research explicitly supplies a removal/quarantine decision. The current replacement behavior can erase unrelated canonical credits from a partial review.
5. **Fail on unexpected ID renames.** Keep the two current aliases as migration compatibility, but require new packs to use canonical stable IDs.
6. **Validate categories against `contracts/purchase-categories.json`.** Delete the “unknown category passes through unchanged” behavior.
7. **Replace merchant slugging with canonical resolution.** `eligibleMerchants` must map through `merchant-pack.json`. Unknown names should either produce no checkout predicate or fail the checkout-mapping portion; never invent a merchant ID.
8. **Treat portal/program labels as channels, not merchants.** Keep controlled channel mappings for Amex Travel, Expedia For TD, Chase Travel and Capital One Travel.
9. **Stop keyword-based enrollment inference.** Normalize from explicit research facts. Preserve multi-step setup in instructions when the schema only allows one primary channel.
10. **Validate rolling anchors.** A `rolling` row must state which owner-state timestamp drives eligibility and that timestamp must exist in the engine. Do not assume `lastRedemptionAt`.
11. **Reject unsupported reset time zones.** A non-null timezone needs explicit evidence or a trusted normalization rule tied to issuer terms.
12. **Assert temporary end dates.** Any row described as through/until a date must have matching `effectiveTo`.
13. **Validate market/currency against the canonical card.** Fail on CAD/US or USD/CA mismatches rather than silently importing them.
14. **Move fee corrections out of hard-coded script constants.** Treat fee changes as research-derived assertions and conflict-check them against canonical state.
15. **Emit a dry-run promotion report.** Before writing, show add/update/keep/block/remove counts, missing owner-state requirements, unresolved merchant tokens, and schema-blocked rows. Require zero blocking errors for a mutation run.
16. **Do not infer completeness.** Preserve `partial`/`unknown`; only allow `complete` where the research pack explicitly proves an exhaustive issuer benefit inventory.

## Schema additions required for currently blocked shapes

No schema addition is required to safely store the 29 representable base rows after the corrections above. `accountOpenedAt`, optional `purchasePredicate`, enrollment instructions, effective dates, and fixed `Money` already cover those shapes.

The following additions are required **before promoting the corresponding blocked rows**:

| Need | Suggested model addition | Blocked examples |
|---|---|---|
| Rolling anchor other than successful redemption | Add an explicit rolling-anchor enum and matching owner-state timestamp, e.g. `qualifyingTransaction`, `creditPosted/redemption`, plus `lastQualifyingTransactionAt` where needed. | TD NEXUS, CIBC/Chase/Capital One trusted-traveler rows, U.S. Amex trusted traveler. |
| Shared alternative allowance | Add shared group ID, alternative-specific max amount, selection/consumption rule, and limit scope (account vs eligible card). | U.S. Platinum Global Entry vs TSA PreCheck. |
| Per-transaction credit cap | Add `perTransactionCreditCap: Money` (and ensure checkout remaining-value logic applies it). | CSR The Edit US$500 annual / US$250 per booking. |
| Multiple fixed uses per window | Add `usesPerWindow` + `amountPerUse`, or another denomination-aware shape. | CSR two separate US$10 DoorDash non-restaurant promos each month. |
| Seasonal calendar sub-window | Add an explicit calendar-month selector/sub-window rather than representing a December-only amount as an annual credit. | U.S. Platinum US$20 December Uber bonus. |
| Variable/formula monetary value | Either add a formula/tax-aware value type or, preferably for these rows, keep them in benefits instead of `CardCredit`. | Canadian Walmart+ 3/12 and 6/12 + taxes; U.S. Platinum Walmart+ US$12.95 + taxes. |
| Cohort schedule | **Do not add a generic cohort field yet.** First define how owner state identifies legacy vs new cohort and authoritative anniversary anchor. | Canadian Amex Platinum/Aeroplan Reserve NEXUS. |

Merchant-pack expansion is a data-quality task, not a `CardCredit` schema addition.

## Concise promotion order

1. **Do not run another importer mutation yet.** Restore the missing US remaining pack and make the importer consume all packs with explicit precedence.
2. **Quarantine the 12 published canonical rows identified above** before treating the catalogue as release-ready; keep both Venture X rows draft-only.
3. **Apply the 22 exact normalization corrections**, especially stable IDs, canonical merchant mapping, reset timezone removal, enrollment normalization, and portfolio-only predicates where checkout cannot be proven.
4. **Retain/promote the 7 as-is rows plus the 22 corrected rows** on already-published cards: 29 representable base credits total.
5. **Keep the US Platinum and CSR fee values at 895 USD and 795 USD** respectively; treat them as assertions, not new script-side mutations.
6. **Route the three variable/tax-linked Walmart+ rows to benefits** rather than fixed-money `CardCredit` unless a formula value model is deliberately added.
7. **Implement the required schedule/shared-limit/per-use/per-transaction-cap additions**, then re-review the remaining blocked credits one shape at a time.
8. **Only promote Venture X credits when the parent card itself is intentionally moved from draft to published.**

## Final production-readiness assessment

The research quality is generally stronger than the importer’s current normalization model. The biggest risk is not wrong issuer amounts; it is losing issuer semantics while converting free-form research into a fixed `CardCredit`/checkout predicate.

The safe next state is:

- preserve the 29 representable rows after correction,
- keep 18 base rows out of production promotion,
- quarantine the two unverified Crypto.com inferred rows,
- add no new `complete` coverage claims,
- and block bulk promotion until the missing US pack is present and the importer performs deterministic multi-pack conflict validation.
