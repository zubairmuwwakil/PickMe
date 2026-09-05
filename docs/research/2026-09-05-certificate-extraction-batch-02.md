# Batch 02 — six more cards confirm the warranty model is wrong and adjudicators are per-benefit

**Date:** 2026-09-05  
**Status:** research only; no contract bytes changed.  
**Scope:** `amex-cobalt`, `amex-bonvoy`, `mbna-rewards-we`, `scotia-momentum-vi-plus`, `tangerine-moneyback-world`, `rogers-red-we`; shopping family only.

The highest-value defect is now repeated across all six cards: `extraYears: 1` is not a faithful Extended Warranty rule. Each certificate extends by the original manufacturer-warranty duration, capped at one additional year. Short warranties therefore receive a short extension, not an automatic extra year.

The batch also confirms that adjudication cannot live at card level. MBNA uses TD Home and Auto + Global Excel for Purchase Assurance / Extended Warranty but American Bankers / Assurant for Mobile Device. Scotia uses FNAIC plus a separately named claims administrator. Amex and Tangerine name no separate administrator company for the reviewed benefits. Rogers uses CUMIS plus AZGA Service Canada Inc. d/b/a Allianz Global Assistance.

## Evidence rule

Every finding below comes from the card's own certificate URL already recorded in `contracts/benefits-catalogue.json`; no marketing page, comparison site, or sibling-card certificate was used. Page references are the PDF page indices surfaced by text extraction, matching the pilot convention.

This public research file intentionally does **not** reproduce wholesale certificate wording. It keeps short verbatim quote anchors plus exact page locators and compact predicate inventories. That is compatible with the repo's raw-source policy, but it means this file is **not yet sufficient for the pilot's stronger “verbatim quote on every field” authoring gate**. A later local/private extraction step should attach the full required field-level snippets before contract promotion. Silence is recorded as silence; no value is inferred from another card.

`E` = mechanically evaluable if PickMe captures the needed purchase/item/event fact. `N` = requires subjective, causal, legal, or adjuster judgment.

---

## 1. `amex-cobalt`

Certificate: `Cobalt-Card-COI-EN.pdf` (effective 2025-07).

### Adjudicator and coverage verification

| Benefit | Adjudicator | Published-field verification | Claim timing |
|---|---|---|---|
| `cobalt-purchase-protection` | Belair Insurance Company Inc.; no separate administrator company named; Policy `PSI018516570`; claims 1-800-243-0198 / +905-475-4822; `info.submitclaims.client.insure` (pp.51,54). | `windowDays:90` **correct**; `maxPerOccurrenceCad:1000` **correct**; partial-card-charge eligibility **correct**. Missing payout-basis fact: only the charged portion is reimbursable (p.52). | hard report: 48h; written notice target: 45d; proof: 90d (p.54). |
| `cobalt-extended-warranty` | Belair; no separate administrator; Policy `PSI018966745`; same claims route (pp.44,47-48). | `maxOriginalWarrantyYears:5` **correct**. `extraYears:1` **wrong/overstated**: extension equals original warranty, capped at 1yr. **Missing:** entire-price charge condition and $10k/item + $25k/Cardmember/policy-year limits (p.45). | notice 45d; requested documents 60d from occurrence or 30d after request (p.47). |
| `cobalt-mobile-device` | Belair; no separate administrator; Policy `PSI060355149`; same claims route (pp.58,62-63). | `maxCad:1000` **correct**; fixed `deductibleCad:null` **correct** because deductible is 10% of depreciated value. Published charge condition is **incomplete**: three purchase/plan paths, activation/continuity rules and coverage-start rules matter (pp.59-61). | call no later than 14d; provider suspension 48h after loss/theft; police 7d for theft. No distinct numeric proof deadline surfaced in the mobile section (pp.62-63). |

Short quote anchors: Q-C1 “Belair Insurance Company Inc.”; Q-C2 “entire purchase price”; Q-C3 “at least a portion”; Q-C4 “no event later than 14 days”.

### Predicate inventory

- **Purchase Protection, pp.52-54.** E: partial charge; 90d; other-insurance excess; used/refurbished/demo; cash/securities/tickets; animals/plants; consumables/perishables; left-behind items; unsupervised jewellery; motorized vehicles/parts; business property; illegally procured property. N: wear/tear; mysterious disappearance; inherent defect/workmanship; war/confiscation/contraband/illegal acts; flood/earthquake; deliberate abuse; fraud. Pair/set and repair-vs-replace settlement rules also apply.
- **Extended Warranty, pp.45-47.** E: full charge; new/nonbusiness item; warranty valid Canada/US and <=5yr; extension equals original term capped 1yr; $10k/$25k limits; other-insurance excess; used/refurbished/demo; vehicles/motorized equipment; fixtures/land; jewellery; consumables; animals/plants; one-of-kind; business inventory; sports-use loss; separately purchased extended cover. N: fraud/abuse/negligence; war/confiscation/illegal acts; inherent defect/recall; improper installation/alteration.
- **Mobile Device, pp.59-63.** E: purchase/plan payment path; cellular activation; 30/91-day start interaction; two-year end; uninterrupted plan billing; one-claim/12mo and two/48mo caps; accessories/batteries/business/used/modified/shipping/baggage exclusions; manufacturer warranty primary; prior approval. N: misuse/lack of care; improper installation; inherent defect; catastrophic/cosmetic damage; software/network cause; intentional/criminal acts.

---

## 2. `amex-bonvoy`

Certificate: `Marriott-Bonvoy-Card-COI-EN.pdf` (effective 2025-07).

### Adjudicator and coverage verification

| Benefit | Adjudicator | Published-field verification | Claim timing |
|---|---|---|---|
| `bonvoy-purchase-protection` | Belair Insurance Company Inc.; no separate administrator; Policy `PSI018516570`; claims 1-800-243-0198 / +905-475-4822; `info.submitclaims.client.insure` (pp.37,40). | 90d and $1,000/occurrence **correct**; partial charge **correct**. **Missing:** payout is limited to the charged portion (p.38). | report 48h; written notice target 45d; proof 90d (p.40). |
| `bonvoy-extended-warranty` | Belair; no separate administrator; Policy `PSI018966745`; same claims route (pp.30,33-34). | five-year original-warranty ceiling **correct**. `extraYears:1` **wrong/overstated**. **Missing:** entire-price charge condition and $10k/item + $25k/Cardmember/policy-year limits (p.31). | notice 45d; documents 60d from occurrence or 30d after request (p.33). |

Short quote anchors: Q-B1 “Belair Insurance Company Inc.”; Q-B2 “entire purchase price”; Q-B3 “at least a portion”; Q-B4 “within 45 days”.

### Predicate inventory

Independently checked in this card's own certificate. **PP pp.38-40:** E: partial charge, 90d, excess insurance, used/refurbished/demo, cash/securities/tickets, animals/plants, consumables, left-behind items, unsupervised jewellery, motorized vehicles, business property, illegally procured property, pair/set rules. N: wear/tear, mysterious disappearance, inherent defect/workmanship, war/confiscation/illegal acts, flood/earthquake, deliberate abuse, fraud. **EW pp.31-33:** E: full charge, new/nonbusiness item, Canada/US warranty <=5yr, original-term doubling capped 1yr, $10k/$25k limits, used/refurbished/demo, vehicles/machinery, fixtures/land, jewellery, consumables, animals/plants, one-of-kind, business inventory, sports-use loss, separately purchased cover. N: fraud/abuse/negligence, war/confiscation/illegal acts, inherent defect/recall, improper installation/alteration.

---

## 3. `mbna-rewards-we`

Certificate: `mbna-rewards-world-elite-guide-to-coverage-en.pdf`.

### Adjudicator and coverage verification

| Benefit | Adjudicator | Published-field verification | Claim timing |
|---|---|---|---|
| `mbna-purchase-protection` | TD Home and Auto Insurance Company; separate administrator Global Excel Management Inc.; Policy `TGV012`; 1-866-520-8827 / +1-519-742-9356; no separate online claim URL surfaced in Part 4 (pp.1,18,21-22). | 90d **correct**; generic per-occurrence/annual nulls are reasonable, but the catalogue does not type the $60k lifetime combined limit or computer/software $1k and jewellery/fine-art $500 sublimits. Full-cost charge **correct**. | notice 30d; proof 90d (pp.21-22). |
| `mbna-extended-warranty` | same TD / Global Excel / `TGV012`. | `extraYears:1` **wrong/overstated**. `maxOriginalWarrantyYears:null` **correct** because >5yr warranties can qualify if registered. Full-cost condition **correct**; registration rule needs structured representation. | notice 30d; proof 90d. |
| `mbna-mobile-device` | American Bankers Insurance Company of Florida (Assurant); Group Policy `MBNA-0620`; no different administrator company named; 1-877-654-7511; `cardbenefits.assurant.com` (pp.42,47). | $1,000 **correct**; fixed deductible null **correct** because $25/$50/$75/$100 tiers apply. Payment condition is directionally correct but **incomplete**: exact 75%/plan pathways, 30-day start and uninterrupted billing are material (pp.43-45). | notice 30d; provider 48h; police 7d. No distinct normal proof-by-N-days deadline surfaced in the mobile-specific section; general written-notice rule is 90d (pp.47-48). |

Short quote anchors: Q-M1 “TD Home and Auto Insurance Company”; Q-M2 “Global Excel Management Inc.”; Q-M3 “American Bankers Insurance Company of Florida”; Q-M4 “no event later than 30 days”.

### Predicate inventory

**PA/EW pp.18-22:** E: full charge; 90d; $60k lifetime; $1k computer/software and $500 jewellery/fine-art sublimits; gifts claimant=cardholder; other insurance/warranty excess; cash/negotiables/documents; animals/plants; undelivered mail order; golf balls; motorized vehicles; used items; Canadian warranty; >5yr registration; manufacturer-only obligations. N: fraud, abuse, war/confiscation/illegal acts, wear/tear, flood/earthquake/radioactive cause, mysterious disappearance, inherent defect, modification/repair causation. **Mobile pp.43-48:** E: >=75%/plan payment paths, activation, 30d start, two-year end, uninterrupted billing, $1k/depreciation/tiered deductible, claim-count limits, accessories/batteries/business/used/refurbished/modified/shipping/baggage exclusions. N: misuse/lack of care, improper installation, inherent defect, catastrophic/cosmetic damage, software/network cause, criminal acts.

---

## 4. `scotia-momentum-vi-plus`

Certificate: `Momentum-Infinite-plus-COI-EN.pdf` (2021-07).

### Adjudicator and coverage verification

All three shopping benefits are under FNAIC Group Policy `BNS749`. Separate claims administrator: Active Claims Management (2018) Inc., operating as Active Care Management / ACM / Global Excel Management / Global Excel. Claims: 1-800-263-0997 or 416-977-1552; `manulife.ca/scotia` (pp.4,12,16).

| Benefit | Published-field verification | Claim timing |
|---|---|---|
| `scotia-purchase-security` | 90d **correct**; full-price charge **correct**; generic per-occurrence/annual nulls are reasonable. **Missing typed fact:** $60k aggregate lifetime limit shared with EW (p.11). | notice <=90d before repairs/actions; proof <=1 year (p.12). |
| `scotia-extended-warranty` | `extraYears:1` **wrong/overstated**; `maxOriginalWarrantyYears:null` **correct** because warranties >=5yr may qualify after registration; full-price condition correct. Missing $60k lifetime limit and structured registration rule. | notice <=90d; proof <=1 year. |
| `scotia-mobile-device` | $1,000 **correct**; fixed deductible null **correct** because tiered; payment condition **incomplete**: three paths, 30-day start and billing continuity matter (pp.13-16). | initial contact <=14d; provider 48h; police 7d; written notice outer limit 90d. No distinct numeric proof deadline in the mobile section. |

Short quote anchors: Q-S1 “First North American Insurance Company”; Q-S2 “Active Claims Management (2018) Inc.”; Q-S3 “aggregate maximum lifetime liability is $60,000”; Q-S4 “no event later than 14 days”.

### Predicate inventory

**PS/EW pp.9-12:** E: full charge, 90d, $60k lifetime, other-insurance excess, used/preowned, cash/negotiables, art, animals/plants, perishables, aircraft/vehicles, services/ancillary cost, breakdown labour, business use, undelivered orders, unsupervised jewellery; EW registration for >=5yr; dealer/assembler warranty excluded. N: misuse/abuse, fraud, wear/tear, inherent defect, mysterious disappearance, war/terrorism/confiscation/illegal acts, flood/earthquake/radioactive cause. **Mobile pp.13-16:** E: three payment paths, activation, 30d start, two-year end, uninterrupted bills, $1k/depreciation/tiered deductible, prior approval, claim-count limit, accessories/batteries/business/used/refurbished/modified/shipping/baggage exclusions. N: misuse/lack of care, improper installation, inherent defect, catastrophic/cosmetic damage, software/network cause, intentional/criminal acts.

---

## 5. `tangerine-moneyback-world`

Certificate: `5_Tangerine_World_Mastercard_Certificate_of_Insurance_FINAL.pdf` (amended/restated 2025-10-25).

### Adjudicator and coverage verification

American Bankers Insurance Company of Florida, Group Policy `BNS092015`. Claim payment/admin services are performed by the insurer; **no different administrator company is named**. Claims: 1-855-255-6050; `cardbenefits.assurant.com` (pp.1,6-7,10).

| Benefit | Published-field verification | Claim timing |
|---|---|---|
| `tangerine-purchase-assurance` | 90d **correct**; full-cost charge **correct**; generic per-occurrence/annual nulls are reasonable. **Missing typed fact:** $60k lifetime combined PA/EW limit (p.6). | notify immediately before repairs; no numeric benefit-specific notice-day ceiling; proof 90d (pp.6-7). |
| `tangerine-extended-warranty` | `extraYears:1` **wrong/overstated**; original-warranty max null **correct** because >=5yr warranties can qualify with registration within 1yr; full cost correct. Missing structured registration + $60k lifetime limit (pp.4-6). | immediate notice; proof 90d. |
| `tangerine-mobile-device` | $1,000 **correct**; fixed deductible null **correct** because tiered. Generic payment condition **incomplete**: three paths, activation, 30-day start, two-year end and uninterrupted billing are material (pp.7-10). | notice <=14d; provider 48h; police 7d. General provisions impose a one-year outer notice/proof limit; no tighter mobile-specific proof deadline was found (pp.10,15). |

Short quote anchors: Q-T1 “American Bankers Insurance Company of Florida”; Q-T2 “Claim payment and administrative services are provided by the Insurer.”; Q-T3 “maximum lifetime liability of $60,000”.

### Predicate inventory

**PA/EW pp.3-7:** E: full cost, 90d, $60k lifetime, other-insurance excess, cash/negotiables, bullion, art, used/refurbished, animals/plants, consumables, aircraft/vehicles, services/ancillary cost, breakdown labour, business use, undelivered orders, unsupervised jewellery, shipping damage; EW >=5yr registration, dealer/assembler warranties and non-manufacturer obligations excluded. N: misuse/abuse, fraud, wear/tear, inherent defect, mysterious disappearance, war/terrorism/confiscation/illegal acts, flood/earthquake/radioactive cause. **Mobile pp.7-11:** E: three payment paths, activation, 30d start, two-year end, uninterrupted bills, $1k/depreciation/tiered deductible, claim-count limit, prior approval, accessories/batteries/business/used/refurbished/modified/shipping/baggage exclusions. N: misuse/lack of care, improper installation, inherent defect, catastrophic/cosmetic damage, software/network cause, intentional/criminal acts.

---

## 6. `rogers-red-we`

Certificate: `Rogers_Bank_World_Elite_Mastercard_Certificate_of_Insurance.pdf` (effective 2024-04-09).

### Adjudicator and coverage verification

CUMIS General Insurance Company, master Policy `FC310040-C`. Separate administrator: Allianz Global Assistance, registered business name of AZGA Service Canada Inc. Claims: 1-866-856-7323 / (519) 742-1723; `allianzassistanceclaims.ca` (pp.24,28-29).

| Benefit | Published-field verification | Claim timing |
|---|---|---|
| `rogers-purchase-protection` | 90d **correct**; full-price charge **correct**; generic per-occurrence/annual nulls reasonable. **Missing typed fact:** $60k lifetime combined PP/EW limit (p.26). | written notice <=30d; proof <=90d. Ignore insurer's separate 60-day payment commitment (p.28). |
| `rogers-extended-warranty` | `extraYears:1` **wrong/overstated**; original-warranty max null **correct** because warranties exceeding 5yr can qualify after registration within 1yr; full-price condition correct. Missing structured registration + $60k lifetime limit (pp.26-27). | written notice <=30d; proof <=90d. |

Short quote anchors: Q-R1 “CUMIS General Insurance Company”; Q-R2 “registered business name of AZGA Service Canada Inc.”; Q-R3 “full purchase price”; Q-R4 “not later than 30 days”.

### Predicate inventory

**PP pp.26-28:** E: Canadian cardholder/good standing, full price, 90d, $60k lifetime, excess insurance, left-behind items, money/negotiables, animals/plants, consumables, undelivered mail/online orders, golf balls, used/rebuilt/refurbished/resold, motor vehicles/equipment, aircraft/drones, phones, business property, pair/set rule. **EW pp.26-28:** E: full price, Canadian-valid warranty, >5yr registration within 1yr, extension equal original term capped 1yr, $60k lifetime, commercial use excluded, used items, motorized property, phones, lifetime warranties, manufacturer-warranty obligations only. **Both:** N: fraud/abuse, war/confiscation/illegal acts, wear/deterioration, installation causation, insects/vermin, flood/earthquake/radioactive cause, environmental deterioration, sports-use damage, mysterious disappearance, inherent defect, one-of-kind, consequential damages. E: forced-entry condition for theft, due diligence/cooperation, other-insurance exhaustion.

---

## Consolidated catalogue defects

| # | Card / benefit | Defect against current catalogue | Priority |
|---|---|---|---|
| 1 | all six Extended Warranty benefits | `extraYears: 1` overstates short warranties. Rule is **original warranty duration, capped at one additional year**. | **P0 correctness** |
| 2 | Cobalt + Bonvoy EW | Entire-price charge condition is missing from `conditions`. | **P0 correctness** |
| 3 | Cobalt + Bonvoy EW | $10,000/item and $25,000/Cardmember/policy-year limits are not represented in coverage. | P1 |
| 4 | Cobalt + Bonvoy PP | Catalogue does not represent that payout is limited to the portion charged to the Card. | **P0 decision semantics** |
| 5 | MBNA PA/EW | $60,000 lifetime combined limit plus computer/software and jewellery/fine-art sublimits are not typed; current notes do not make them machine-evaluable. | P1 |
| 6 | Scotia PS/EW | $60,000 aggregate lifetime limit is not typed. | P1 |
| 7 | Tangerine PA/EW | $60,000 lifetime combined limit is not typed. | P1 |
| 8 | Rogers PP/EW | $60,000 lifetime combined limit is not typed. | P1 |
| 9 | MBNA / Scotia / Tangerine / Rogers EW | `maxOriginalWarrantyYears:null` is reasonable, but the **registration threshold and one-year registration deadline** are only prose/notes or absent from structured fields. Thresholds are card-specific: MBNA/Rogers use >5yr; Scotia/Tangerine use >=5yr. | **P0 predicate semantics** |
| 10 | Cobalt / MBNA / Scotia / Tangerine mobile | Published payment conditions collapse materially different eligibility paths, start dates and billing-continuity rules into generic prose. | **P0 predicate semantics** |
| 11 | all 16 reviewed shopping benefits | `exclusions: []` is materially false/incomplete; every certificate contains substantive exclusions. | **P0 correctness** |
| 12 | all 16 reviewed shopping benefits | `certificateQuote: null` despite directly locatable certificate evidence. | P1 provenance |
| 13 | all six cards | Current card-level `certificate.underwriter` cannot represent per-benefit insurer/administrator shape. MBNA is the clearest counterexample. | **P0 schema** |
| 14 | all reviewed benefits | Claimant notice/proof deadlines are not modelled. These vary materially: 14d, 30d, 45d, 48h, 90d, and one-year proof rules appear across this batch. | P1 claims UX |

## Cross-card findings worth preserving

1. **Do not normalize warranty-registration thresholds across issuers.** MBNA and Rogers say registration is needed when the original warranty exceeds five years; Scotia and Tangerine trigger at five years or more.
2. **`deductibleCad:null` is correct for the reviewed mobile benefits.** Amex uses a percentage deductible; MBNA/Scotia/Tangerine use tiers. A single CAD scalar would misstate them.
3. **Claim timing needs two layers.** A hard initial report deadline can coexist with a later written-notice rule. Cobalt Mobile, for example, has a 14-day call deadline plus a broader written-notice provision.
4. **Do not ingest insurer response SLAs.** Rogers' payment-within-60-days language is an insurer obligation after satisfactory proof; it is not a claimant deadline.
5. **The pilot schema's per-benefit adjudicator decision is validated again.** MBNA alone requires two insurer shapes inside one card.

## Batch boundary

Stopped at six cards as required. No travel, rental, or medical family was reviewed; no `contracts/` file, schema, version, engine resource, Android resource, or released byte was changed. The next session should resume after `rogers-red-we` in catalogue order and must continue using each card's own certificate.