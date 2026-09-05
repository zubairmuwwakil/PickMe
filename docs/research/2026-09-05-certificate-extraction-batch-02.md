# Batch 02 corrective extraction — warranty rule fixed; adjudicator, timing, limits, and predicates still need modelling

**Date:** 2026-09-05  
**Status:** research only; no contract bytes changed.  
**Scope:** `amex-cobalt`, `amex-bonvoy`, `mbna-rewards-we`, `scotia-momentum-vi-plus`, `tangerine-moneyback-world`, `rogers-red-we`; **16 shopping benefits** total.

The original Batch 02 note was directionally useful but too compressed for the pilot handoff. This corrective pass re-read the same six cards from each card's own certificate. One earlier conclusion is now stale: catalogue v1.4 already carries `warrantyExtensionRule: "matchesOriginalCapped"` for these reviewed Extended Warranty records. That rule is correct. The residual risk is the coexistence of `extraYears: 1`, which is unsafe if any consumer treats it as an unconditional flat addition.

The remaining defects are structural: per-benefit adjudicator is not typed; claimant notice/proof timing is not typed; exclusion arrays are effectively empty; several lifetime/sub-limits are untyped; and mobile-device eligibility is much richer than the generic catalogue conditions.

## Evidence rule

Every finding below was checked against the **card's own certificate URL already recorded in `contracts/benefits-catalogue.json`**. No marketing page, comparison site, or sibling-card certificate supplied a term. Page references use the extracted PDF page indices, matching the pilot convention. Silence is recorded as silence.

The pilot requests the full supporting sentence verbatim for every field and predicate. This repository note cannot reproduce large portions of public certificates. It therefore uses **short verbatim anchors plus exact page-scoped predicate tokens**. The index is suitable for defect discovery and schema design, but **not** for a later contract-authoring gate that requires full field-level source sentences; that gate must read the original certificate directly.

`E` = mechanically evaluable from captured purchase/item/warranty/billing/time facts.  
`N` = requires causal, subjective, legal, account-status, or adjuster judgment.

---

## 1. `amex-cobalt`

Certificate: `Cobalt-Card-COI-EN.pdf` (2025-07).  
Source: `https://americanexpress.com/content/dam/amex/en-ca/insurance/pdfs/certificates-of-insurance/Cobalt-Card-COI-EN.pdf`

**Short anchors:** p.44/51/58 “Belair Insurance Company Inc.”; p.52 “at least a portion”; p.45 “up to one additional year”; p.63 “no event later than 14 days”; p.54 “within 90 days”.

### Adjudicator + published-field verification

| Benefit | Adjudicator | Catalogue verification | Claim timing |
|---|---|---|---|
| `cobalt-purchase-protection` | Belair; **no separate administrator named**; Policy `PSI018516570`; 1-800-243-0198 / +1-905-475-4822; `info.submitclaims.client.insure` (pp.51,54). | `windowDays:90` **correct**; `$1,000` occurrence **correct**; partial-charge **correct**; charged-portion payout basis **missing** (pp.51-52). | 48h initial report; 45d written-notice target; 90d proof/docs (p.54). |
| `cobalt-extended-warranty` | Belair; no separate administrator; `PSI018966745`; same claims route (pp.44,47). | `matchesOriginalCapped` + max-original 5y **correct**; `extraYears:1` unsafe standalone; **missing** full-charge predicate, $10k/item and $25k/Cardmember/policy-year limits (p.45). | notice 45d; requested docs 60d from occurrence or 30d after request; requested item 30d (p.47). |
| `cobalt-mobile-device` | Belair; no separate administrator; `PSI060355149`; same route (pp.58,62-63). | `$1,000` **correct**; fixed deductible null **correct** but 10%-of-depreciated-value formula untyped; three payment paths/start/end/claim-count rules untyped (pp.59-61). | mobile notice 14d; provider 48h; police 7d; numeric mobile-specific proof deadline **silent in sections reviewed** (pp.62-63). |

### Predicate index

- **PP:** p.52 `E:partial-charge,new-personal,90d,other-insurance-excess,charged-portion-cap,pair-set`; p.53 `E:used-refurb-demo,cash-like,animals-plants,consumables-perishables,left-behind,ancillary-cost,jewellery-baggage`; `N:wear-tear,vehicle-theft,mysterious-disappearance,inherent-defect-workmanship,war-confiscation,flood-earthquake`; p.54 `E:motorized,business,illegal-property`; `N:deliberate-abuse,fraud`.
- **EW:** p.45 `E:new-personal,full-charge,CA-US-warranty,max-original-5y,match-original-cap-1y,10k-item,25k-annual`; p.46 `E:other-insurance-excess,used-refurb-demo,motorized`; `N:physical-damage,fraud-abuse,hostilities-confiscation,negligence,improper-install,defect-recall`; p.47 `E:motorized-work-equipment,fixtures-land,jewellery,consumables,animals-plants,one-of-kind,business-inventory,overlong-or-addon-warranty`; `N:electrical-cause,sports-use-cause`.
- **MDI:** pp.59-60 `E:new-device,three-payment-paths,activation,start-rule,2y-end,billing-continuity,1000-cap,2pct-depreciation,10pct-deductible,claim-count`; `N:prior-approval,manufacturer-warranty-primary`; pp.61-62 `E:accessories,batteries,laptops,business-resale,used,refurbished-exceptions,modified,shipping,baggage`; `N:fraud-misuse-care,installation,hostilities,wear-flood-quake-defect,mysterious-disappearance,power-surge,catastrophic,cosmetic,software-network,household-crime,consequential`.

---

## 2. `amex-bonvoy`

Certificate: `Marriott-Bonvoy-Card-COI-EN.pdf` (2025-07).  
Source: `https://americanexpress.com/content/dam/amex/en-ca/insurance/pdfs/certificates-of-insurance/Marriott-Bonvoy-Card-COI-EN.pdf`

**Short anchors:** p.30/37 “Belair Insurance Company Inc.”; p.38 “at least a portion”; p.31 “up to one additional year”; p.33 “within 45 days”; p.40 “within 90 days”.

### Adjudicator + published-field verification

| Benefit | Adjudicator | Catalogue verification | Claim timing |
|---|---|---|---|
| `bonvoy-purchase-protection` | Belair; **no separate administrator named**; `PSI018516570`; 1-800-243-0198 / +1-905-475-4822; `info.submitclaims.client.insure` (pp.37,40). | 90d + $1,000 occurrence + partial charge **correct**; charged-portion payout rule **missing** (pp.37-38). | 48h report; 45d written-notice target; 90d proof (p.40). |
| `bonvoy-extended-warranty` | Belair; no separate administrator; `PSI018966745`; same route (pp.30,33). | `matchesOriginalCapped` and 5y ceiling **correct**; `extraYears:1` unsafe standalone; full-charge + $10k/item + $25k annual limits **missing** (p.31). | notice 45d; docs 60d from occurrence or 30d after request; requested item 30d (p.33). |

### Predicate index

- **PP:** p.38 `E:partial-charge,new-personal,90d,other-insurance-excess,charged-portion-cap,pair-set`; pp.39-40 `E:used-refurb-demo,cash-like,animals-plants,consumables,left-behind,ancillary,jewellery-baggage,motorized,business,illegal-property`; `N:wear-tear,vehicle-theft,mysterious-disappearance,defect-workmanship,war-confiscation,flood-earthquake,deliberate-abuse,fraud`.
- **EW:** p.31 `E:new-personal,full-charge,CA-US-warranty,max-original-5y,match-original-cap-1y,10k-item,25k-annual`; pp.32-33 `E:used-refurb-demo,motorized,work-equipment,fixtures-land,jewellery,consumables,animals-plants,one-of-kind,business-inventory,overlong-or-addon-warranty`; `N:physical-damage,fraud-abuse,hostilities,negligence,improper-install,defect-recall,electrical-cause,sports-use-cause`.

---

## 3. `mbna-rewards-we`

Certificate: `mbna-rewards-world-elite-guide-to-coverage-en.pdf`.  
Source: `https://www.mbna.ca/content/dam/mbna/document/pdf/credit-cards/mbna-rewards-world-elite-guide-to-coverage-en.pdf`

**Short anchors:** p.1/18 “TD Home and Auto Insurance Company”; p.1 “Global Excel Management Inc.”; p.42 “American Bankers Insurance Company of Florida”; p.21 “within 30 days”; p.22 “within 90 days”.

### Adjudicator + published-field verification

| Benefit | Adjudicator | Catalogue verification | Claim timing |
|---|---|---|---|
| `mbna-purchase-protection` | TD Home and Auto; separate administrator Global Excel; `TGV012`; 1-866-520-8827 / +1-519-742-9356 (pp.1,18,21). | 90d/full-cost **correct**; generic occurrence/annual nulls reasonable; **missing** $60k lifetime + $1k computer/software + $500 jewellery/fine-art sublimits (pp.18-19). | immediate-notice condition; formal notice 30d; proof 90d; late-proof outer 1y (pp.21-22). |
| `mbna-extended-warranty` | Same TD/Global Excel/`TGV012`. | `matchesOriginalCapped` and max-original null **correct**; `extraYears:1` unsafe standalone; >5y registration + $60k lifetime untyped (pp.19-20). | same 30d notice / 90d proof (pp.21-22). |
| `mbna-mobile-device` | American Bankers Insurance Company of Florida; **no different administrator company named**; `MBNA-0620`; 1-877-654-7511; `cardbenefits.assurant.com` (pp.42,47). | $1,000 + fixed-deductible null **correct**; 75%-or-plan condition directionally correct; deductible tiers/start/end/depreciation/claim-count untyped (pp.43-45). | notice 30d; provider 48h; police 7d; ordinary mobile-specific proof deadline **silent**; general outer cure 1y (pp.46-48). |

### Predicate index

- **PA:** pp.18-20 `E:full-charge,90d,60k-lifetime,1k-computer,500-jewellery-art,gift-cardholder,other-insurance,cash-like,documents,animals-plants,mail-order,golf-balls,motorized`; `N:settlement,pair-set,fraud-abuse,hostilities,wear,flood-quake-radioactive,mysterious-disappearance,inherent-defect,repair-modification-cause,consequential`.
- **EW:** pp.19-20 `E:full-charge,Canadian-warranty,match-original-cap-1y,over5y-register-within1y,60k-lifetime,gift-cardholder,other-warranty,used,motorized`; `N:manufacturer-ceases,manufacturer-obligations-only,fraud-abuse,hostilities,wear,flood-quake-radioactive,mysterious-disappearance,inherent-defect,repair-modification-cause`.
- **MDI:** pp.43-45 `E:new-device,75pct-or-plan-paths,activation,30d-start,2y-end,billing-continuity,1000-cap,2pct-depreciation,25-50-75-100-deductible,repair-charge,claim-count`; pp.45-46 `E:accessories,batteries,business-resale,used,refurbished-exceptions,modified,shipping,baggage`; `N:prior-approval,manufacturer-warranty-primary,fraud-misuse-care,installation,hostilities,wear-flood-quake-radioactive,mysterious-disappearance,defect,power-surge,catastrophic,cosmetic,software-network,household-crime,consequential`.

---

## 4. `scotia-momentum-vi-plus`

Certificate: `Momentum-Infinite-plus-COI-EN.pdf` (2021-07).  
Source: `https://www.scotiabank.com/content/dam/scotiabank/canada/common/documents/pdf/Momentum-Infinite-plus-COI-EN.pdf`

**Short anchors:** p.4 “First North American Insurance Company”; p.4 “Active Claims Management (2018) Inc.”; p.11 “aggregate maximum lifetime liability is $60,000”; p.16 “no event later than 14 days”.

### Adjudicator + published-field verification

All three shopping benefits: FNAIC; separate administrator Active Claims Management (2018) Inc. under its stated operating names; Group Policy `BNS749`; 1-800-263-0997 (PA/EW also 416-977-1552); `manulife.ca/scotia` (pp.4,12,16).

| Benefit | Catalogue verification | Claim timing |
|---|---|---|
| `scotia-purchase-security` | 90d/full-price **correct**; generic occurrence/annual nulls reasonable; $60k shared lifetime **missing** (pp.9,11). | notice ≤90d before repair/action; proof ≤1y (p.12). |
| `scotia-extended-warranty` | `matchesOriginalCapped`, max-original null, full-price **correct**; `extraYears:1` unsafe standalone; registration + $60k lifetime untyped (pp.10-11). | notice ≤90d; proof ≤1y (p.12). |
| `scotia-mobile-device` | $1,000 + fixed-deductible null **correct**; three paths/start/end/tiered deductible/depreciation/claim-count untyped (pp.13-15). | contact 14d; formal written notice outer 90d; provider 48h; police 7d; ordinary mobile-specific proof deadline **silent** (p.16; general cure p.36). |

### Predicate index

- **PS:** pp.9-12 `E:full-charge,90d,60k-lifetime,other-insurance,gift-cardholder,cash-like,bullion,art,used,animals-plants,perishables,aircraft-motorized,consumed-items,services,ancillary,business,mail-order,jewellery-baggage`; `N:settlement,pair-set,breakdown,misuse-abuse,fraud,wear,inherent-defect,mysterious-disappearance,vehicle-theft,flood-quake-radioactive,hostilities,confiscation-illegal,consequential`.
- **EW:** pp.10-12 `E:full-charge,match-original-cap-1y,registration-threshold-within1y,60k-lifetime,gift-cardholder,other-warranty,motorized,used,plants,trim,services,business,dealer-assembler-warranty`; `N:manufacturer-obligations-only,misuse-abuse,fraud,wear,defect,mysterious-disappearance,flood-quake-radioactive,hostilities,confiscation-illegal,consequential`.
- **MDI:** pp.13-16 `E:new-device,three-payment-paths,activation,30d-start,2y-end,billing-continuity,1000-cap,2pct-depreciation,25-50-75-100-deductible,claim-count,accessories-batteries,business-resale,used-refurb,modified,shipping,baggage`; `N:prior-approval,manufacturer-warranty-primary,fraud-misuse-care,installation,hostilities,wear-flood-quake-radioactive,mysterious-disappearance,defect,power-surge,catastrophic,cosmetic,software-network,household-crime,consequential`.

---

## 5. `tangerine-moneyback-world`

Certificate: `5_Tangerine_World_Mastercard_Certificate_of_Insurance_FINAL.pdf` (amended/restated 2025-10-25).  
Source: `https://www.tangerine.ca/content/dam/tangerine/en/pdfs/credit-card-cardholder-agreement/5_Tangerine_World_Mastercard_Certificate_of_Insurance_FINAL.pdf`

**Short anchors:** p.1 “American Bankers Insurance Company of Florida”; p.1 “Claim payment and administrative services are provided by the Insurer.”; p.10 “no event later than 14 days”.

### Adjudicator + published-field verification

All three shopping benefits: American Bankers Insurance Company of Florida; **no separate administrator company named** because claim/admin service is assigned to the insurer; `BNS092015`; 1-855-255-6050; `cardbenefits.assurant.com` (pp.1,6-7,10).

| Benefit | Catalogue verification | Claim timing |
|---|---|---|
| `tangerine-purchase-assurance` | 90d/full-cost **correct**; generic occurrence/annual nulls reasonable; $60k lifetime + repair/replacement charge rule untyped (pp.3-6). | immediate-before-repair condition; numeric benefit-specific notice-day ceiling **silent**; proof 90d; general outer bar 1y (pp.6-7,15). |
| `tangerine-extended-warranty` | `matchesOriginalCapped`, max-original null, full-cost **correct**; `extraYears:1` unsafe standalone; registration + $60k lifetime untyped (pp.4-6). | same immediate condition; numeric notice days **silent**; proof 90d (pp.6-7). |
| `tangerine-mobile-device` | $1,000 + fixed-deductible null **correct**; three paths/start/end/tiered deductible/depreciation/claim-count untyped (pp.7-9). | notice 14d; provider 48h; police 7d; ordinary mobile-specific proof deadline **silent**; general outer rule 1y (pp.10,15). |

### Predicate index

- **PA:** pp.3-6 `E:full-cost,90d,60k-lifetime,other-insurance,gift-cardholder,repair-charge,cash-like,bullion,art,used-refurb,animals-plants,consumables,aircraft-drones,motorized,services,ancillary,business,mail-order,jewellery-baggage`; `N:settlement,pair-set,breakdown,delivery-damage,misuse-abuse,fraud,wear,defect,mysterious-disappearance,vehicle-theft,flood-quake-radioactive,hostilities,confiscation-illegal,consequential`.
- **EW:** pp.4-6 `E:full-cost,match-original-cap-1y,long-warranty-register-within1y,60k-lifetime,gift-cardholder,other-warranty,aircraft-drones,motorized,used-refurb,plants,trim,services,business,dealer-assembler-warranty`; `N:manufacturer-obligations-only,shared-PAEW-subjective-exclusions`.
- **MDI:** pp.7-10 `E:new-device,three-payment-paths,total-cost-rule,activation,30d-start,2y-end,billing-continuity,1000-cap,2pct-depreciation,25-50-75-100-deductible,repair-charge,claim-count,accessories-batteries,business-resale,used,refurbished-exceptions,modified,shipping,baggage`; `N:prior-approval,manufacturer-warranty-primary,fraud-misuse-care,installation,hostilities,wear-flood-quake-radioactive,mysterious-disappearance,defect,power-surge,catastrophic,cosmetic,software-network,household-crime,consequential`.

---

## 6. `rogers-red-we`

Certificate: `Rogers_Bank_World_Elite_Mastercard_Certificate_of_Insurance.pdf` (2024-04).  
Source: `https://www.rogersbank.com/legaldocs/en/Rogers_Bank_World_Elite_Mastercard_Certificate_of_Insurance.pdf`

**Short anchors:** p.24 “CUMIS General Insurance Company”; p.24 “Allianz Global Assistance”; p.28 “within 30 days”; p.28 “within 90 days”; p.27 “a three-month warranty”; p.27 “maximum of one additional year”.

### Adjudicator + published-field verification

Both shopping benefits: CUMIS General Insurance Company; separate administrator **AZGA Service Canada Inc. d/b/a Allianz Global Assistance**; Group Policy `FC310040-C`; 1-866-856-7323 / +1-519-742-1723; `allianzassistanceclaims.ca` (pp.24,29,31).

| Benefit | Catalogue verification | Claim timing |
|---|---|---|
| `rogers-purchase-protection` | 90d/full-price **correct**; occurrence/annual nulls reasonable; $60k combined lifetime + pair/set rule untyped (p.26). | written notice 30d; proof 90d; late-compliance outer 1y (p.28). |
| `rogers-extended-warranty` | `matchesOriginalCapped`, max-original null, full-price **correct**; own short-warranty example proves `extraYears:1` unsafe standalone; >5y registration + $60k lifetime untyped (pp.26-27). | notice 30d; proof 90d; **do not model** separate insurer 60d payment commitment (p.28). |

### Predicate index

- **PP:** pp.26-28 `E:full-charge,90d,60k-lifetime,other-insurance,left-behind,cash-like,animals-plants,consumables,mail-online,golf-balls,used-refurb-resold,autos-trailers-motorcycles-boats,scooters-wheelchairs,lawn-equipment,airplanes-drones,hoverboards-motorized,phones,business`; `N:resident-status,settlement,pair-set,fraud-abuse,hostilities,confiscation-illegal,delay-loss-use,wear-deterioration,installation-cause,vermin,flood-quake-radioactive,environmental-material-change,sports-use,mysterious-disappearance,inherent-defect,unconditional-guarantee,forced-entry-theft,consequential,due-diligence-subrogation,false-claim`.
- **EW:** pp.26-28 `E:full-charge,Canadian-warranty,match-original-cap-1y,over5y-register-within1y,60k-lifetime,business,used-refurb-resold,motorized,airplanes-drones,phones,lifetime-warranty`; `N:original-warranty-obligations,manufacturer-ceases,shared-general-exclusions,due-diligence-subrogation,false-claim`.

---

## Consolidated defects against catalogue v1.4

| # | Scope | Defect |
|---:|---|---|
| 1 | all **16** benefits | Missing typed per-benefit adjudicator: insurer, different administrator when present, group policy, claims route. |
| 2 | all 16 | Missing typed claimant notice/proof timing; some benefits need more than one notice field. |
| 3 | all 16 | Catalogue exclusion/condition representation is far thinner than the certificate predicate sets. |
| 4 | all reviewed EW | `warrantyExtensionRule: matchesOriginalCapped` is now **correct**; residual `extraYears:1` can still mislead downstream code if read independently. |
| 5 | Cobalt + Bonvoy EW | Missing $10k/item and $25k annual limits plus full-charge predicate. |
| 6 | Cobalt + Bonvoy PP | Missing charged-portion payout basis. |
| 7 | MBNA PA/EW | Missing $60k lifetime; PA also misses $1k computer/software and $500 jewellery/fine-art sublimits; EW registration untyped. |
| 8 | Scotia PA/EW | Missing $60k lifetime; EW registration untyped. |
| 9 | Tangerine PA/EW | Missing $60k lifetime; PA repair/replacement charge rule and EW registration untyped. |
| 10 | Rogers PP/EW | Missing $60k lifetime; EW >5y registration untyped. |
| 11 | all four MDI records | Payment paths, start/end, depreciation, deductible formula/tiers, prior approval, and claim-count rules are incompletely typed. |
| 12 | Tangerine PA/EW | Numeric notice deadline is silent in the benefit sections; preserve immediate-notice condition without inventing days. |
| 13 | MBNA/Scotia/Tangerine MDI | No ordinary mobile-specific numeric proof deadline found; do not turn a general one-year outside/cure rule into `proofDays:365`. |
| 14 | Rogers PP/EW | Insurer's post-proof payment commitment is not claimant timing and must stay out of coverage predicates. |

## Batch conclusion

The current catalogue has already fixed the core Extended Warranty duration rule for these six cards. The next gated authoring pass should target the still-unmodelled facts above: **per-benefit adjudicator, claimant timing, lifetime/sub-limits, structured mobile eligibility, and certificate predicate sets**.

No `contracts/` bytes were changed.