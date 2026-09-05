# Batch 02 corrective extraction — warranty rule fixed; adjudicator, timing, limits, and predicates still need modelling

**Date:** 2026-09-05  
**Status:** research only; no contract bytes changed.  
**Scope:** `amex-cobalt`, `amex-bonvoy`, `mbna-rewards-we`, `scotia-momentum-vi-plus`, `tangerine-moneyback-world`, `rogers-red-we`; **16 shopping benefits**.

The original Batch 02 note was too compressed for the pilot handoff. This corrective pass re-read the same six cards from each card's own certificate. Catalogue v1.4 has already corrected the Extended Warranty duration rule with `warrantyExtensionRule: "matchesOriginalCapped"`. The residual modelling risk is `extraYears: 1` if any downstream code interprets that scalar independently as an unconditional one-year addition.

## Evidence rule

Only the certificate URL already recorded for that exact card in `contracts/benefits-catalogue.json` was used. No marketing page, comparison site, or sibling-card certificate supplied a term. Page numbers are extracted-PDF indices, matching the pilot. Silence stays silence.

The pilot asks for the full supporting sentence on every field/predicate. This research note cannot republish large portions of public certificates, so it keeps a small set of short verbatim anchors and an exact page-scoped predicate ledger. It is sufficient for defect discovery/schema design, **not** for a later contract-authoring gate that requires full source sentences; that gate must read the original certificate directly.

`E` = mechanically evaluable from captured facts. `N` = requires causal, subjective, legal, account-status, or adjuster judgment.

---

## 1. `amex-cobalt`

Source: `Cobalt-Card-COI-EN.pdf` (2025-07), `https://americanexpress.com/content/dam/amex/en-ca/insurance/pdfs/certificates-of-insurance/Cobalt-Card-COI-EN.pdf`.

**Anchors:** p.44/51/58 “Belair Insurance Company Inc.”; p.52 “at least a portion”; p.45 “up to one additional year”; p.63 “no event later than 14 days”; p.54 “within 90 days”.

**Adjudicator:** Belair; **no separate administrator named**; claims 1-800-243-0198 / +1-905-475-4822 / `info.submitclaims.client.insure`; policies PP `PSI018516570`, EW `PSI018966745`, MDI `PSI060355149` (pp.44,47,51,54,58,63).

- **PP pp.51-54** — verify: 90d **correct**, $1k/occurrence **correct**, partial-charge **correct**, charged-portion payout **missing**. Timing: 48h report; 45d written; 90d proof. Predicates: p.52 `E:partial-charge,new-personal,90d,other-insurance,charged-portion,pair-set`; pp.53-54 `E:used-refurb-demo,cash-like,animals-plants,consumables,left-behind,ancillary,jewellery-baggage,motorized,business,illegal-property`; `N:wear,vehicle-theft,mysterious-disappearance,defect-workmanship,war-confiscation,flood-quake,abuse,fraud`.
- **EW pp.45-47** — verify: rule + 5y ceiling **correct**; `extraYears` unsafe standalone; **missing** full-charge, $10k/item, $25k/year. Timing: notice 45d; docs 60d occurrence or 30d after request; requested item 30d. Predicates: `E:new-personal,full-charge,CA-US-warranty,max5y,match-original-cap1y,limits,other-insurance,used-refurb-demo,motorized,work-equipment,fixtures-land,jewellery,consumables,animals-plants,one-of-kind,business-inventory,addon-warranty`; `N:physical-damage,fraud-abuse,hostilities,negligence,installation,defect-recall,electrical-cause,sports-use`.
- **MDI pp.59-63** — verify: $1k **correct**, fixed deductible null **correct**; 10%-depreciated-value deductible plus payment/start/end/claim-count rules untyped. Timing: notice 14d; provider 48h; police 7d; numeric mobile proof deadline **silent**. Predicates: `E:new-device,three-payment-paths,activation,start-rule,2y-end,billing-continuity,1000-cap,2pct-depreciation,10pct-deductible,claim-count,accessories,batteries,laptops,business-resale,used,refurb-exceptions,modified,shipping,baggage`; `N:prior-approval,manufacturer-warranty,fraud-misuse-care,installation,hostilities,wear-flood-quake-defect,mysterious-disappearance,power-surge,catastrophic,cosmetic,software-network,household-crime,consequential`.

---

## 2. `amex-bonvoy`

Source: `Marriott-Bonvoy-Card-COI-EN.pdf` (2025-07), `https://americanexpress.com/content/dam/amex/en-ca/insurance/pdfs/certificates-of-insurance/Marriott-Bonvoy-Card-COI-EN.pdf`.

**Anchors:** p.30/37 “Belair Insurance Company Inc.”; p.38 “at least a portion”; p.31 “up to one additional year”; p.33 “within 45 days”; p.40 “within 90 days”.

**Adjudicator:** Belair; **no separate administrator named**; same Amex claims route; PP `PSI018516570`, EW `PSI018966745` (pp.30,33,37,40).

- **PP pp.37-40** — verify: 90d/$1k/partial-charge **correct**; charged-portion payout **missing**. Timing: 48h report; 45d written; 90d proof. Predicates: `E:partial-charge,new-personal,90d,other-insurance,charged-portion,pair-set,used-refurb-demo,cash-like,animals-plants,consumables,left-behind,ancillary,jewellery-baggage,motorized,business,illegal-property`; `N:wear,vehicle-theft,mysterious-disappearance,defect-workmanship,war-confiscation,flood-quake,abuse,fraud`.
- **EW pp.31-33** — verify: rule + 5y ceiling **correct**; `extraYears` unsafe standalone; **missing** full-charge/$10k-item/$25k-year. Timing: notice 45d; docs 60d occurrence or 30d request; requested item 30d. Predicates: `E:new-personal,full-charge,CA-US-warranty,max5y,match-original-cap1y,limits,used-refurb-demo,motorized,work-equipment,fixtures-land,jewellery,consumables,animals-plants,one-of-kind,business-inventory,addon-warranty`; `N:physical-damage,fraud-abuse,hostilities,negligence,installation,defect-recall,electrical-cause,sports-use`.

---

## 3. `mbna-rewards-we`

Source: `mbna-rewards-world-elite-guide-to-coverage-en.pdf`, `https://www.mbna.ca/content/dam/mbna/document/pdf/credit-cards/mbna-rewards-world-elite-guide-to-coverage-en.pdf`.

**Anchors:** p.1/18 “TD Home and Auto Insurance Company”; p.1 “Global Excel Management Inc.”; p.42 “American Bankers Insurance Company of Florida”; p.21 “within 30 days”; p.22 “within 90 days”.

**PA/EW adjudicator:** TD Home and Auto; separate administrator Global Excel; policy `TGV012`; 1-866-520-8827 / +1-519-742-9356 (pp.1,18,21). **MDI:** American Bankers; no different administrator company named; `MBNA-0620`; 1-877-654-7511; `cardbenefits.assurant.com` (pp.42,47).

- **PA pp.18-22** — verify: 90d/full-charge **correct**; null generic occurrence/annual reasonable; **missing** $60k lifetime, $1k computer/software, $500 jewellery/fine-art. Timing: immediate condition; formal notice 30d; proof 90d; late-proof outer 1y. Predicates: `E:full-charge,90d,lifetime-sublimits,gift-cardholder,other-insurance,cash-like,documents,animals-plants,mail-order,golf-balls,motorized`; `N:settlement,pair-set,fraud-abuse,hostilities,wear,flood-quake-radioactive,mysterious-disappearance,defect,repair-modification,consequential`.
- **EW pp.19-22** — verify: rule + max-original null **correct**; `extraYears` unsafe standalone; **missing** >5y registration/$60k lifetime. Timing: 30d notice; 90d proof. Predicates: `E:full-charge,Canadian-warranty,match-original-cap1y,over5y-register1y,60k,gift-cardholder,other-warranty,used,motorized`; `N:manufacturer-ceases,manufacturer-obligations,fraud-abuse,hostilities,wear,flood-quake-radioactive,mysterious-disappearance,defect,repair-modification`.
- **MDI pp.43-48** — verify: $1k + fixed-deductible null + 75%-or-plan direction **correct**; tiers/start/end/depreciation/claim-count untyped. Timing: notice 30d; provider 48h; police 7d; ordinary mobile proof deadline **silent**; general outer cure 1y. Predicates: `E:new-device,75pct-or-plan,activation,30d-start,2y-end,billing-continuity,1000,2pct,25-50-75-100-deductible,repair-charge,claim-count,accessories,batteries,business-resale,used,refurb-exceptions,modified,shipping,baggage`; `N:prior-approval,manufacturer-warranty,fraud-misuse-care,installation,hostilities,wear-flood-quake-radioactive,mysterious-disappearance,defect,power-surge,catastrophic,cosmetic,software-network,household-crime,consequential`.

---

## 4. `scotia-momentum-vi-plus`

Source: `Momentum-Infinite-plus-COI-EN.pdf` (2021-07), `https://www.scotiabank.com/content/dam/scotiabank/canada/common/documents/pdf/Momentum-Infinite-plus-COI-EN.pdf`.

**Anchors:** p.4 “First North American Insurance Company”; p.4 “Active Claims Management (2018) Inc.”; p.11 “aggregate maximum lifetime liability is $60,000”; p.16 “no event later than 14 days”.

**Adjudicator:** FNAIC; separate administrator Active Claims Management (2018) Inc.; `BNS749`; 1-800-263-0997 (PA/EW also 416-977-1552); `manulife.ca/scotia` (pp.4,12,16).

- **PS pp.9-12** — verify: 90d/full-price **correct**; generic limit nulls reasonable; $60k lifetime **missing**. Timing: notice ≤90d before repair/action; proof ≤1y. Predicates: `E:full-charge,90d,60k,other-insurance,gift-cardholder,cash-like,bullion,art,used,animals-plants,perishables,aircraft-motorized,consumed-items,services,ancillary,business,mail-order,jewellery-baggage`; `N:settlement,pair-set,breakdown,misuse-abuse,fraud,wear,defect,mysterious-disappearance,vehicle-theft,flood-quake-radioactive,hostilities,confiscation-illegal,consequential`.
- **EW pp.10-12** — verify: rule/max-original-null/full-price **correct**; `extraYears` unsafe standalone; registration/$60k untyped. Timing: notice ≤90d; proof ≤1y. Predicates: `E:full-charge,match-original-cap1y,registration1y,60k,gift-cardholder,other-warranty,motorized,used,plants,trim,services,business,dealer-assembler`; `N:manufacturer-obligations,misuse-abuse,fraud,wear,defect,mysterious-disappearance,flood-quake-radioactive,hostilities,confiscation-illegal,consequential`.
- **MDI pp.13-16** — verify: $1k/fixed-deductible-null **correct**; payment/start/end/tiers/depreciation/claim-count untyped. Timing: 14d contact; 90d written outer; provider 48h; police 7d; ordinary mobile proof deadline **silent**. Predicates: `E:new-device,three-payment-paths,activation,30d-start,2y-end,billing-continuity,1000,2pct,25-50-75-100-deductible,claim-count,accessories-batteries,business-resale,used-refurb,modified,shipping,baggage`; `N:prior-approval,manufacturer-warranty,fraud-misuse-care,installation,hostilities,wear-flood-quake-radioactive,mysterious-disappearance,defect,power-surge,catastrophic,cosmetic,software-network,household-crime,consequential`.

---

## 5. `tangerine-moneyback-world`

Source: `5_Tangerine_World_Mastercard_Certificate_of_Insurance_FINAL.pdf` (2025-10-25), `https://www.tangerine.ca/content/dam/tangerine/en/pdfs/credit-card-cardholder-agreement/5_Tangerine_World_Mastercard_Certificate_of_Insurance_FINAL.pdf`.

**Anchors:** p.1 “American Bankers Insurance Company of Florida”; p.1 “Claim payment and administrative services are provided by the Insurer.”; p.10 “no event later than 14 days”.

**Adjudicator:** American Bankers; **no separate administrator company named**; `BNS092015`; 1-855-255-6050; `cardbenefits.assurant.com` (pp.1,6-7,10).

- **PA pp.3-7** — verify: 90d/full-cost **correct**; generic limit nulls reasonable; $60k lifetime + repair/replacement charge rule untyped. Timing: immediate-before-repair condition; numeric benefit-specific notice days **silent**; proof 90d; general outer bar 1y. Predicates: `E:full-cost,90d,60k,other-insurance,gift-cardholder,repair-charge,cash-like,bullion,art,used-refurb,animals-plants,consumables,aircraft-drones,motorized,services,ancillary,business,mail-order,jewellery-baggage`; `N:settlement,pair-set,breakdown,delivery-damage,misuse-abuse,fraud,wear,defect,mysterious-disappearance,vehicle-theft,flood-quake-radioactive,hostilities,confiscation-illegal,consequential`.
- **EW pp.4-7** — verify: rule/max-original-null/full-cost **correct**; `extraYears` unsafe standalone; registration/$60k untyped. Timing: immediate condition; numeric notice days **silent**; proof 90d. Predicates: `E:full-cost,match-original-cap1y,long-warranty-register1y,60k,gift-cardholder,other-warranty,aircraft-drones,motorized,used-refurb,plants,trim,services,business,dealer-assembler`; `N:manufacturer-obligations,shared-PAEW-subjective-exclusions`.
- **MDI pp.7-10** — verify: $1k/fixed-deductible-null **correct**; payment/start/end/tiers/depreciation/claim-count untyped. Timing: 14d notice; provider 48h; police 7d; ordinary mobile proof deadline **silent**; general outer rule 1y. Predicates: `E:new-device,three-payment-paths,total-cost-rule,activation,30d-start,2y-end,billing-continuity,1000,2pct,25-50-75-100-deductible,repair-charge,claim-count,accessories-batteries,business-resale,used,refurb-exceptions,modified,shipping,baggage`; `N:prior-approval,manufacturer-warranty,fraud-misuse-care,installation,hostilities,wear-flood-quake-radioactive,mysterious-disappearance,defect,power-surge,catastrophic,cosmetic,software-network,household-crime,consequential`.

---

## 6. `rogers-red-we`

Source: `Rogers_Bank_World_Elite_Mastercard_Certificate_of_Insurance.pdf` (2024-04), `https://www.rogersbank.com/legaldocs/en/Rogers_Bank_World_Elite_Mastercard_Certificate_of_Insurance.pdf`.

**Anchors:** p.24 “CUMIS General Insurance Company”; p.24 “Allianz Global Assistance”; p.28 “within 30 days”; p.28 “within 90 days”; p.27 “a three-month warranty”; p.27 “maximum of one additional year”.

**Adjudicator:** CUMIS; separate administrator AZGA Service Canada Inc. d/b/a Allianz Global Assistance; `FC310040-C`; 1-866-856-7323 / +1-519-742-1723; `allianzassistanceclaims.ca` (pp.24,29,31).

- **PP pp.26-28** — verify: 90d/full-price **correct**; generic limit nulls reasonable; $60k lifetime + pair/set untyped. Timing: notice 30d; proof 90d; late-compliance outer 1y. Predicates: `E:full-charge,90d,60k,other-insurance,left-behind,cash-like,animals-plants,consumables,mail-online,golf-balls,used-refurb-resold,autos-trailers-motorcycles-boats,scooters-wheelchairs,lawn-equipment,airplanes-drones,hoverboards-motorized,phones,business`; `N:resident-status,settlement,pair-set,fraud-abuse,hostilities,confiscation-illegal,delay-loss-use,wear-deterioration,installation-cause,vermin,flood-quake-radioactive,environmental-material-change,sports-use,mysterious-disappearance,defect,unconditional-guarantee,forced-entry-theft,consequential,due-diligence-subrogation,false-claim`.
- **EW pp.26-28** — verify: rule/max-original-null/full-price **correct**; certificate short-warranty example makes `extraYears` unsafe standalone; >5y registration/$60k untyped. Timing: notice 30d; proof 90d; **exclude** insurer's separate 60d payment commitment. Predicates: `E:full-charge,Canadian-warranty,match-original-cap1y,over5y-register1y,60k,business,used-refurb-resold,motorized,airplanes-drones,phones,lifetime-warranty`; `N:manufacturer-obligations,manufacturer-ceases,shared-general-exclusions,due-diligence-subrogation,false-claim`.

---

## Consolidated defect table

| Scope | Defect |
|---|---|
| all **16** benefits | Per-benefit adjudicator and claimant timing are untyped; current condition/exclusion representation is materially incomplete. |
| all reviewed EW | `warrantyExtensionRule` is now correct; standalone `extraYears:1` remains a downstream modelling risk. |
| Cobalt/Bonvoy | EW item/annual limits missing; PP charged-portion payout basis missing. |
| MBNA | PA/EW lifetime/sublimits or registration missing; MDI structured eligibility/deductible/timing facts incomplete. |
| Scotia | PA/EW lifetime/registration missing; MDI structured eligibility/deductible/timing facts incomplete. |
| Tangerine | PA/EW lifetime/registration and PA repair-charge fact missing; numeric PA/EW notice days are silent; MDI structured facts incomplete. |
| Rogers | PP/EW lifetime and EW registration missing; insurer payment-response timing must not be confused with claimant timing. |
| MBNA/Scotia/Tangerine MDI | No ordinary mobile-specific numeric proof deadline found; do not map a general one-year outside/cure rule to `proofDays:365`. |

## Batch conclusion

The six-card pass is complete. The next gated contract-authoring step should focus on **per-benefit adjudicator, claimant timing, lifetime/sub-limits, structured mobile eligibility, and predicate representation**. No `contracts/` bytes were changed.