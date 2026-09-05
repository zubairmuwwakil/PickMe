# Batch 02 corrective extraction — the warranty rule is now fixed, but adjudicator, timing, limits, and predicates are still missing

**Date:** 2026-09-05  
**Status:** research only; no contract bytes changed.  
**Scope:** `amex-cobalt`, `amex-bonvoy`, `mbna-rewards-we`, `scotia-momentum-vi-plus`, `tangerine-moneyback-world`, `rogers-red-we`; shopping family only.

The earlier Batch 02 note was useful as an index, but it did not meet the pilot's evidence standard: it compressed exclusions and used a few quote anchors instead of preserving field-level evidence. This corrective pass re-read each of the same six cards from its own certificate and expands the benefit-by-benefit adjudicator, published-field verification, claim timing, and predicate inventory.

The most important correction to the earlier note is that the **current catalogue is already on version 1.4 and now carries `warrantyExtensionRule: "matchesOriginalCapped"` for these reviewed Extended Warranty benefits**. That rule is correct. The remaining `extraYears: 1` field is still dangerous if a consumer interprets it as a flat one-year addition, but the catalogue is no longer missing the governing rule itself.

Across these six cards, the remaining high-value gaps are structural: adjudicator identity is not represented per benefit; claim-notice/proof timing is not typed; exclusion arrays are effectively empty; several lifetime/sub-limits exist only in prose or are absent; and mobile-device payment/start/continuity/deductible rules are materially richer than the current generic conditions.

## Evidence rule

Every factual finding below was checked against the **card's own certificate URL already recorded in `contracts/benefits-catalogue.json`**. No issuer marketing page, comparison site, or sibling-card certificate was used to fill a term. Page references are the PDF page indices used by the extraction pass, matching the pilot convention. Silence is recorded as silence; no value is inferred from another product.

The requested authoring gate says every field and predicate should reproduce its supporting sentence verbatim. This repo note cannot republish entire copyrighted certificate sections. It therefore records **exact PDF page/section locators for every predicate and uses a small set of short verbatim anchors per certificate**. The semantic inventory is exhaustive for the shopping sections reviewed, but this file should not be treated as satisfying a future contract-authoring gate that requires the full source sentence to be stored verbatim. The original certificate remains the authoritative evidence object.

`E` = mechanically evaluable if PickMe captures the needed transaction, item, warranty, billing, or time fact.  
`N` = not safely machine-evaluable from purchase data alone; requires causal, legal, subjective, account-status, or claims-adjuster judgment.

---

## 1. `amex-cobalt`

Certificate: `Cobalt-Card-COI-EN.pdf` — effective 2025-07.  
Catalogue source: `https://americanexpress.com/content/dam/amex/en-ca/insurance/pdfs/certificates-of-insurance/Cobalt-Card-COI-EN.pdf`

### Short verbatim anchors

- **Q-C1, p.44/51/58:** “Belair Insurance Company Inc.”
- **Q-C2, p.52:** “at least a portion”
- **Q-C3, p.45:** “up to one additional year”
- **Q-C4, p.63:** “no event later than 14 days”
- **Q-C5, p.54:** “within 90 days”

### `cobalt-purchase-protection`

#### Adjudicator

| Field | Finding | Evidence |
|---|---|---|
| Insurer | Belair Insurance Company Inc. | p.51; Q-C1 |
| Claims administrator | **No separate administrator company named.** Claims are directed to Belair / its claims service. | pp.51,54 |
| Group policy | `PSI018516570` | p.51 |
| Claims phone | 1-800-243-0198; +1-905-475-4822 | p.54 |
| Claims URL | `https://info.submitclaims.client.insure` | p.54 |

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `windowDays` | 90 | Coverage runs for 90 days from purchase. | **correct** | pp.51-52 |
| `maxPerOccurrenceCad` | 1,000 | Maximum reimbursement is $1,000 per Cardmember per occurrence. | **correct** | p.52 |
| Charge condition | at least part charged | A partial Card charge is sufficient. | **correct** | p.52; Q-C2 |
| Payout basis | not typed | Reimbursement is limited to the portion of the item price charged to the Card. | **missing** | p.52 |
| Pair/set settlement | not typed | Pair/set rules can change the payable amount depending on whether remaining pieces are usable. | **missing** | p.52 |
| Other-insurance position | not typed | Benefit is excess over other insurance. | **missing** | p.52 |

#### Claim timing

| Timing fact | Finding | Evidence |
|---|---|---|
| Immediate/initial report | All claims must be reported within 48 hours of the occurrence. | p.54 |
| Written notice | Written notice should be given, where possible, within 45 days. | p.54 |
| Proof/documents | Required documents must be submitted within 90 days. | p.54; Q-C5 |
| Insurer response commitment | **Not modelled.** | excluded by task rule |

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | At least some of the purchase price must be charged to the Card. | p.52 |
| condition | E | The item must be new and for personal, not business, use. | p.51 |
| condition | E | Covered loss must occur within 90 days of purchase. | pp.51-52 |
| condition | E | Other collectible insurance is primary; this benefit is excess. | p.52 |
| condition | E | Reimbursement cannot exceed the portion of price charged to the Card. | p.52 |
| condition | N | The insurer may settle by repair, replacement, or reimbursement subject to the certificate. | p.52 |
| condition | N | Pair/set settlement depends on whether undamaged components remain usable separately. | p.52 |
| exclusion | E | Used, rebuilt, refurbished, remanufactured, and demonstration items are excluded. | p.53 |
| exclusion | E | Cash, currency, prepaid/gift cards, travellers cheques, banknotes, bullion, securities, bonds, debentures, tickets, and documents are excluded. | p.53 |
| exclusion | E | Animals and living plants are excluded. | p.53 |
| exclusion | E | Consumables and perishables, including food and liquor, are excluded. | p.53 |
| exclusion | E | Items left behind are excluded. | p.53 |
| exclusion | E | Ancillary costs beyond the insured item's purchase price are excluded. | p.53 |
| exclusion | E | Jewellery or watches in baggage are excluded unless hand-carried and supervised as required. | p.53 |
| exclusion | E | Motorized vehicles and listed parts/accessories are excluded. | pp.53-54 |
| exclusion | E | Property acquired for business/professional use is excluded. | p.54 |
| exclusion | E | Illegally procured property is excluded. | p.54 |
| exclusion | N | Normal wear and tear is excluded. | p.53 |
| exclusion | N | Theft of property attached to or carried in a motor vehicle is excluded under the stated circumstances. | p.53 |
| exclusion | N | Mysterious disappearance or simple loss is excluded. | p.53 |
| exclusion | N | Loss caused by inherent defect or faulty workmanship is excluded. | p.53 |
| exclusion | N | War, invasion, hostilities, rebellion, insurrection, confiscation, contraband, and illegal acts are excluded. | p.53 |
| exclusion | N | Flood and earthquake losses are excluded. | p.53 |
| exclusion | N | Deliberate physical abuse is excluded except where the certificate treats vandalism differently. | p.54 |
| exclusion | N | A knowingly false or fraudulent claim is excluded. | p.54 |

### `cobalt-extended-warranty`

#### Adjudicator

| Field | Finding | Evidence |
|---|---|---|
| Insurer | Belair Insurance Company Inc. | p.44; Q-C1 |
| Claims administrator | **No separate administrator company named.** | pp.44,47-48 |
| Group policy | `PSI018966745` | p.44 |
| Claims phone | 1-800-243-0198; +1-905-475-4822 | p.47 |
| Claims URL | `https://info.submitclaims.client.insure` | pp.47-48 |

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `warrantyExtensionRule` | `matchesOriginalCapped` | Extension matches the original manufacturer-warranty duration, capped at one additional year. | **correct** | p.45; Q-C3 |
| `extraYears` | 1 | One year is a cap, not a guaranteed flat addition. A shorter original warranty receives a shorter extension. | **misleading if read standalone** | p.45 |
| `maxOriginalWarrantyYears` | 5 | Original manufacturer warranty must be five years or less. | **correct** | p.45 |
| Charge condition | not in coverage object; condition incomplete | Entire purchase price must be charged to the Card. | **missing as typed coverage predicate** | p.45 |
| Per-item limit | not typed | $10,000 per insured item. | **missing** | p.45 |
| Annual limit | not typed | $25,000 per Cardmember per policy year. | **missing** | p.45 |
| Settlement basis | not typed | Payable amount is limited by purchase price and repair/replacement rules. | **missing** | p.45 |

#### Claim timing

| Timing fact | Finding | Evidence |
|---|---|---|
| Claim notice | Claim must be reported within 45 days of the occurrence. | p.47 |
| Proof/documents | Requested documents are due within 60 days of occurrence or within 30 days after the insurer requests them, as applicable. | p.47 |
| Requested damaged item | If the insurer requests the item, it must be submitted within 30 days of that request. | p.47 |
| Insurer response commitment | **Not modelled.** | excluded by task rule |

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | Item must be new and for personal, non-business use. | p.45 |
| condition | E | Entire purchase price must be charged to the Card. | p.45 |
| condition | E | Item must have an eligible original manufacturer warranty valid in Canada or the United States. | p.45 |
| condition | E | Original manufacturer warranty must be five years or less. | p.45 |
| condition | E | Coverage starts only after the original manufacturer warranty expires. | p.45 |
| condition | E | Extension equals original warranty duration, capped at one additional year. | p.45 |
| condition | E | Per-item liability is capped at $10,000. | p.45 |
| condition | E | Aggregate liability is capped at $25,000 per Cardmember per policy year. | p.45 |
| condition | E | Other applicable insurance is primary. | p.46 |
| condition | N | Settlement is limited by the original purchase price and repair/replacement availability. | p.45 |
| exclusion | N | Physical damage, including certain natural-disaster or power-surge damage, is excluded unless the original warranty would cover it. | p.46 |
| exclusion | N | Fraud, abuse, war/hostilities, confiscation, contraband, and illegal activity are excluded. | p.46 |
| exclusion | N | Negligence is excluded. | p.46 |
| exclusion | N | Improper installation or alteration is excluded. | p.46 |
| exclusion | E | Ancillary costs beyond the purchase price are excluded. | p.46 |
| exclusion | N | Inherent defects are excluded. | p.46 |
| exclusion | N | Recall, mechanical failure, or product defect subject to recall is excluded. | p.46 |
| exclusion | E | Occurrences outside the Extended Warranty coverage period are excluded. | p.46 |
| exclusion | E | Used, rebuilt, refurbished, remanufactured, and demonstration items are excluded. | p.46 |
| exclusion | N | Items covered by an unconditional satisfaction guarantee are excluded. | p.46 |
| exclusion | E | Automobiles and other listed motorized vehicles/equipment, including drones/e-bikes and dependent parts/accessories, are excluded subject to the stated miniature-child-vehicle exception. | p.46 |
| exclusion | E | Motorized equipment used for agriculture, landscaping, demolition, or construction is excluded. | pp.46-47 |
| exclusion | E | Property improvements, permanent goods, and business fixtures are excluded. | p.47 |
| exclusion | N | Electrical damage caused by artificial current/arcing is excluded except where the stated fire/explosion exception applies. | p.47 |
| exclusion | E | Land and buildings are excluded. | p.47 |
| exclusion | E | Jewellery is excluded. | p.47 |
| exclusion | E | Perishables and consumables are excluded. | p.47 |
| exclusion | E | Animals and living plants are excluded. | p.47 |
| exclusion | E | One-of-a-kind items that cannot be replaced are excluded. | p.47 |
| exclusion | E | Business property, inventory, resale property, and other sellable product are excluded. | p.47 |
| exclusion | N | Sports equipment loss caused by its use is excluded. | p.47 |
| exclusion | E | Warranties/service plans exceeding the permitted term are excluded. | p.47 |
| exclusion | E | Separately purchased extended warranties/service plans beyond the basic manufacturer warranty are not extended by this benefit. | p.47 |

### `cobalt-mobile-device`

#### Adjudicator

| Field | Finding | Evidence |
|---|---|---|
| Insurer | Belair Insurance Company Inc. | p.58; Q-C1 |
| Claims administrator | **No separate administrator company named.** | pp.58,62-63 |
| Group policy | `PSI060355149` | p.58 |
| Claims phone | 1-800-243-0198; +1-905-475-4822 | pp.62-63 |
| Claims URL | `https://info.submitclaims.client.insure` | pp.62-63 |

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `maxCad` | 1,000 | Maximum per occurrence/per insured person is $1,000 before applying depreciation/deductible rules. | **correct** | pp.59-60 |
| `deductibleCad` | null | No fixed dollar deductible; deductible is 10% of depreciated value. | **correct null, but formula missing** | p.60 |
| Depreciation | note only | 2% of purchase price for each completed month from purchase. | **not typed** | p.60 |
| Charge condition | generic | Certificate has three distinct purchase/financing/plan pathways and ongoing billing conditions. | **incomplete** | pp.59-60 |
| Coverage start | not typed | Starts at the later of the specified 30-day purchase waiting point and qualifying first wireless-bill point. | **missing** | p.59 |
| Coverage end | not typed | Ends at the earliest of two years, loss of required billing continuity, or account/eligibility termination. | **missing** | pp.59-60 |
| Claim-count limit | not typed | One claim in 12 months and two claims in 48 months across applicable Amex coverage. | **missing** | pp.60-61 |

#### Claim timing

| Timing fact | Finding | Evidence |
|---|---|---|
| General notice | Notify as soon as reasonably possible; general written-notice language uses a 90-day target. | p.62 |
| Mobile-specific claim notice | Contact the insurer immediately and no later than 14 days, before repair/replacement. | p.63; Q-C4 |
| Wireless-provider suspension | Lost/stolen service must be suspended within 48 hours. | p.63 |
| Police report | Theft must be reported to police within 7 days. | p.63 |
| Proof deadline | **Silent in the mobile-specific section reviewed.** Completed claim form/supporting documents are required, but no distinct ordinary proof-by-N-days deadline is stated there. | p.63 |

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | Device must be new. | p.59 |
| condition | E | Full-price purchase path requires charging the full purchase price to the Card and, for a cellular device, activation on a qualifying network. | p.59 |
| condition | E | Provider-financing path permits an upfront portion on the Card if the balance is financed through the provider plan and all required monthly bills are charged to the Card. | p.59 |
| condition | E | Full-plan path permits provider financing of the whole device if all required monthly bills are charged to the Card. | p.59 |
| condition | E | Coverage does not start until the certificate's waiting/start conditions are satisfied. | p.59 |
| condition | E | Coverage ends after two years at the latest. | pp.59-60 |
| condition | E | Required wireless-plan billing must remain uninterrupted. | pp.59-60 |
| condition | E | Maximum payable amount is $1,000, subject to depreciation and deductible. | p.60 |
| condition | E | Depreciation is 2% per completed month. | p.60 |
| condition | E | Deductible equals 10% of depreciated value. | p.60 |
| condition | N | Repair/replacement requires prior insurer approval. | p.60 |
| condition | N | Manufacturer warranty is primary for parts/services it covers. | p.60 |
| condition | E | Claim frequency is limited to one claim in 12 months and two in 48 months. | pp.60-61 |
| exclusion | E | Accessories are excluded. | p.61 |
| exclusion | E | Batteries are excluded. | p.61 |
| exclusion | E | Laptops are excluded. | p.61 |
| exclusion | E | Devices acquired for resale or business/commercial use are excluded. | p.61 |
| exclusion | E | Used devices are excluded. | p.61 |
| exclusion | E | Refurbished devices are excluded except for the stated manufacturer/provider replacement/direct-source exceptions. | p.61 |
| exclusion | E | Modified devices are excluded. | p.61 |
| exclusion | E | Devices in shipment are excluded until received and accepted new/undamaged. | p.61 |
| exclusion | E | Theft from baggage is excluded unless the device is hand-carried/supervised as required. | p.61 |
| exclusion | N | Fraud, misuse, lack of care, and improper installation are excluded. | p.61 |
| exclusion | N | War/hostilities, confiscation, contraband, and illegal acts are excluded. | p.61 |
| exclusion | N | Normal wear, flood, earthquake, and inherent defect are excluded. | p.61 |
| exclusion | N | Mysterious disappearance is excluded. | p.61 |
| exclusion | N | Power surge/electrical irregularity loss is excluded. | p.61 |
| exclusion | N | Catastrophic damage beyond repair is excluded. | p.61 |
| exclusion | N | Cosmetic damage that does not impair function is excluded. | p.61 |
| exclusion | N | Software, wireless-provider, and network causes are excluded. | pp.61-62 |
| exclusion | N | Theft, intentional acts, or criminal acts by the insured/household are excluded subject to the certificate's innocent-insured treatment. | p.62 |
| exclusion | N | Incidental and consequential damage is excluded. | p.62 |

---

## 2. `amex-bonvoy`

Certificate: `Marriott-Bonvoy-Card-COI-EN.pdf` — effective 2025-07.  
Catalogue source: `https://americanexpress.com/content/dam/amex/en-ca/insurance/pdfs/certificates-of-insurance/Marriott-Bonvoy-Card-COI-EN.pdf`

### Short verbatim anchors

- **Q-B1, p.30/37:** “Belair Insurance Company Inc.”
- **Q-B2, p.38:** “at least a portion”
- **Q-B3, p.31:** “up to one additional year”
- **Q-B4, p.33:** “within 45 days”
- **Q-B5, p.40:** “within 90 days”

### `bonvoy-purchase-protection`

#### Adjudicator

| Field | Finding | Evidence |
|---|---|---|
| Insurer | Belair Insurance Company Inc. | p.37; Q-B1 |
| Claims administrator | **No separate administrator company named.** | pp.37,40 |
| Group policy | `PSI018516570` | p.37 |
| Claims phone | 1-800-243-0198; +1-905-475-4822 | p.40 |
| Claims URL | `https://info.submitclaims.client.insure` | p.40 |

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `windowDays` | 90 | 90-day purchase-protection window. | **correct** | pp.37-38 |
| `maxPerOccurrenceCad` | 1,000 | $1,000 maximum per Cardmember per occurrence. | **correct** | p.38 |
| Charge condition | partial charge | A partial Card charge is sufficient. | **correct** | p.38; Q-B2 |
| Payout basis | not typed | Reimbursement is limited to the portion charged to the Card. | **missing** | p.38 |
| Pair/set settlement | not typed | Pair/set rules may reduce or expand settlement depending on usability. | **missing** | p.38 |
| Other-insurance position | not typed | Benefit is excess over other applicable insurance. | **missing** | p.38 |

#### Claim timing

| Timing fact | Finding | Evidence |
|---|---|---|
| Initial report | Report claims within 48 hours. | p.40 |
| Written notice | Where possible, written notice within 45 days. | p.40 |
| Proof/documents | Required documents within 90 days. | p.40; Q-B5 |

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | At least some purchase price must be charged to the Card. | p.38 |
| condition | E | Item must be new and for personal, non-business use. | p.37 |
| condition | E | Loss must occur within 90 days. | pp.37-38 |
| condition | E | Other applicable insurance is primary. | p.38 |
| condition | E | Reimbursement cannot exceed the portion charged to the Card. | p.38 |
| condition | N | Settlement may be repair, replacement, or reimbursement under the certificate. | p.38 |
| condition | N | Pair/set settlement depends on separate usability of the remaining components. | p.38 |
| exclusion | E | Used, rebuilt, refurbished, remanufactured, and demonstration items are excluded. | p.39 |
| exclusion | E | Cash/currency, prepaid/gift cards, travellers cheques, banknotes, bullion, securities, bonds/debentures, tickets, and documents are excluded. | p.39 |
| exclusion | E | Animals and plants are excluded. | p.39 |
| exclusion | E | Consumables and perishables are excluded. | p.39 |
| exclusion | E | Items left behind are excluded. | p.39 |
| exclusion | E | Ancillary costs are excluded. | p.39 |
| exclusion | E | Jewellery/watches in baggage are excluded unless hand-carried/supervised as required. | p.39 |
| exclusion | E | Motorized vehicles and listed parts/accessories are excluded. | pp.39-40 |
| exclusion | E | Business/professional property is excluded. | p.40 |
| exclusion | E | Illegally procured property is excluded. | p.40 |
| exclusion | N | Normal wear and tear is excluded. | p.39 |
| exclusion | N | Motor-vehicle-related theft is excluded under the stated circumstances. | p.39 |
| exclusion | N | Mysterious disappearance or simple loss is excluded. | p.39 |
| exclusion | N | Inherent defect/faulty workmanship is excluded. | p.39 |
| exclusion | N | War/hostilities, confiscation, contraband, and illegal acts are excluded. | p.39 |
| exclusion | N | Flood and earthquake are excluded. | p.39 |
| exclusion | N | Deliberate physical abuse is excluded subject to the vandalism treatment. | p.40 |
| exclusion | N | False/fraudulent claims are excluded. | p.40 |

### `bonvoy-extended-warranty`

#### Adjudicator

| Field | Finding | Evidence |
|---|---|---|
| Insurer | Belair Insurance Company Inc. | p.30; Q-B1 |
| Claims administrator | **No separate administrator company named.** | pp.30,33-34 |
| Group policy | `PSI018966745` | p.30 |
| Claims phone | 1-800-243-0198; +1-905-475-4822 | p.33 |
| Claims URL | `https://info.submitclaims.client.insure` | pp.33-34 |

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `warrantyExtensionRule` | `matchesOriginalCapped` | Extension matches original warranty duration, capped at one year. | **correct** | p.31; Q-B3 |
| `extraYears` | 1 | One year is a cap rather than an automatic flat addition. | **misleading if read standalone** | p.31 |
| `maxOriginalWarrantyYears` | 5 | Original manufacturer warranty must be five years or less. | **correct** | p.31 |
| Charge condition | not typed | Entire purchase price must be charged to the Card. | **missing as typed predicate** | p.31 |
| Per-item limit | not typed | $10,000. | **missing** | p.31 |
| Annual limit | not typed | $25,000 per Cardmember per policy year. | **missing** | p.31 |

#### Claim timing

| Timing fact | Finding | Evidence |
|---|---|---|
| Claim notice | Report within 45 days. | p.33; Q-B4 |
| Proof/documents | Requested documents within 60 days of occurrence or 30 days after insurer request, as applicable. | p.33 |
| Requested damaged item | Submit within 30 days if requested. | p.33 |

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | Item must be new and for personal, non-business use. | p.31 |
| condition | E | Entire purchase price must be charged to the Card. | p.31 |
| condition | E | Original manufacturer warranty must be valid in Canada/United States and be the eligible basic manufacturer warranty. | p.31 |
| condition | E | Original warranty must be five years or less. | p.31 |
| condition | E | Coverage begins after original warranty expiration. | p.31 |
| condition | E | Extension equals original duration, capped at one year. | p.31 |
| condition | E | $10,000 per-item limit applies. | p.31 |
| condition | E | $25,000 per-Cardmember/policy-year limit applies. | p.31 |
| condition | E | Other insurance is primary. | p.32 |
| exclusion | N | Physical damage outside manufacturer-warranty treatment, including stated natural-disaster/power-surge damage, is excluded. | p.32 |
| exclusion | N | Fraud, abuse, war/hostilities, confiscation, contraband, and illegal acts are excluded. | p.32 |
| exclusion | N | Negligence is excluded. | p.32 |
| exclusion | N | Improper installation/alteration is excluded. | p.32 |
| exclusion | E | Ancillary costs are excluded. | p.32 |
| exclusion | N | Inherent defects are excluded. | p.32 |
| exclusion | N | Recall/mechanical/product defect subject to recall is excluded. | p.32 |
| exclusion | E | Occurrences outside the coverage period are excluded. | p.32 |
| exclusion | E | Used/rebuilt/refurbished/remanufactured/demo items are excluded. | p.32 |
| exclusion | N | Unconditional satisfaction-guarantee items are excluded. | p.32 |
| exclusion | E | Listed motorized vehicles/equipment, drones/e-bikes, and dependent parts/accessories are excluded subject to the stated child-vehicle exception. | pp.32-33 |
| exclusion | E | Motorized agriculture/landscaping/demolition/construction equipment is excluded. | p.33 |
| exclusion | E | Property improvements, permanent goods, and business fixtures are excluded. | p.33 |
| exclusion | N | Artificial-current/arcing electrical damage is excluded except for the stated fire/explosion exception. | p.33 |
| exclusion | E | Land/buildings are excluded. | p.33 |
| exclusion | E | Jewellery is excluded. | p.33 |
| exclusion | E | Perishables/consumables are excluded. | p.33 |
| exclusion | E | Animals/plants are excluded. | p.33 |
| exclusion | E | One-of-a-kind nonreplaceable items are excluded. | p.33 |
| exclusion | E | Business property/inventory/resale product is excluded. | p.33 |
| exclusion | N | Sports-equipment loss caused by use is excluded. | p.33 |
| exclusion | E | Warranty/service plans outside the eligible warranty-duration rule are excluded. | p.33 |
| exclusion | E | Separately purchased extended warranties/service plans beyond the basic manufacturer warranty are not extended. | p.33 |

---

## 3. `mbna-rewards-we`

Certificate: `mbna-rewards-world-elite-guide-to-coverage-en.pdf`.  
Catalogue source: `https://www.mbna.ca/content/dam/mbna/document/pdf/credit-cards/mbna-rewards-world-elite-guide-to-coverage-en.pdf`

### Short verbatim anchors

- **Q-M1, p.1/18:** “TD Home and Auto Insurance Company”
- **Q-M2, p.1:** “Global Excel Management Inc.”
- **Q-M3, p.42:** “American Bankers Insurance Company of Florida”
- **Q-M4, p.21:** “within 30 days”
- **Q-M5, p.22:** “within 90 days”

### `mbna-purchase-protection`

#### Adjudicator

| Field | Finding | Evidence |
|---|---|---|
| Insurer | TD Home and Auto Insurance Company | pp.1,18; Q-M1 |
| Claims administrator | Global Excel Management Inc. | p.1; Q-M2 |
| Group policy | `TGV012` | p.18 |
| Claims phone | 1-866-520-8827; +1-519-742-9356 | pp.1,21-22 |
| Claims URL | No separate online claim URL surfaced in the Purchase Assurance / Extended Warranty section reviewed. | pp.18-22 |

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `windowDays` | 90 | Purchase Assurance applies for 90 days. | **correct** | p.18 |
| `maxPerOccurrenceCad` | null | No single generic per-occurrence cap fits the certificate because category sublimits and a lifetime aggregate apply. | **correct null** | p.19 |
| `maxAnnualCad` | null | Certificate uses a lifetime combined aggregate rather than a generic annual maximum. | **correct null** | p.19 |
| Charge condition | full cost to Account | Full cost must be charged through the Account/eligible Account method. | **correct** | p.18 |
| Lifetime combined limit | not typed | $60,000 lifetime aggregate across Purchase Assurance / Extended Warranty. | **missing** | p.19 |
| Computer/software sublimit | not typed | $1,000 per loss for computers/software and related parts/accessories combined. | **missing** | p.19 |
| Jewellery/fine-art sublimit | not typed | $500 per item/per loss for jewellery and fine art. | **missing** | p.19 |

#### Claim timing

| Timing fact | Finding | Evidence |
|---|---|---|
| Immediate notice condition | Notify the administrator immediately after learning of a loss. | p.21 |
| Formal notice deadline | Notice of Claim within 30 days. | p.21; Q-M4 |
| Proof deadline | Proof of Loss within 90 days. | p.22; Q-M5 |
| Late-proof cure | If timely proof was not reasonably possible, later proof may be accepted subject to the certificate's one-year outer boundary. | p.22 |
| Insurer payment timing | **Not modelled.** The separate insurer payment commitment after proof is not claimant timing. | p.22 |

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | Full purchase cost must be charged through the qualifying Account method. | p.18 |
| condition | E | Loss/theft/damage must occur within 90 days. | p.18 |
| condition | E | Other insurance/warranty is primary; this coverage is excess. | pp.20-21 |
| condition | E | Gifts are covered only with the Cardholder as claimant. | p.20 |
| condition | E | Shipped gifts are not covered until delivered to and accepted by the recipient. | p.20 |
| condition | E | Computer/software-related loss is subject to the $1,000 sublimit. | p.19 |
| condition | E | Jewellery/fine-art loss is subject to the $500 sublimit. | p.19 |
| condition | E | Combined lifetime Purchase Assurance / Extended Warranty liability is $60,000 per Account. | p.19 |
| condition | N | Settlement may be repair, replacement, or reimbursement under certificate terms. | p.18 |
| condition | N | Pair/set settlement may be proportionate. | p.19 |
| exclusion | E | Travellers cheques, money, tickets, bullion, banknotes, negotiable instruments, and numismatic property are excluded. | pp.18-19 |
| exclusion | E | Documents are excluded. | p.19 |
| exclusion | E | Animals and plants are excluded. | p.19 |
| exclusion | E | Mail-order property is excluded until delivered and accepted. | p.19 |
| exclusion | E | Golf balls are excluded. | p.19 |
| exclusion | E | Motorized vehicles and listed parts/accessories are excluded. | p.19 |
| exclusion | N | Fraud and abuse are excluded. | p.20 |
| exclusion | N | War/hostilities, confiscation, contraband, and illegal acts are excluded. | p.20 |
| exclusion | N | Normal wear and tear is excluded. | p.20 |
| exclusion | N | Flood, earthquake, and radioactive causes are excluded. | p.20 |
| exclusion | N | Mysterious disappearance is excluded. | p.20 |
| exclusion | N | Inherent defect is excluded. | p.20 |
| exclusion | N | Loss caused by modification, repair, or attempted repair is excluded where the causal requirement is met. | p.20 |
| exclusion | N | Bodily injury, other property damage, consequential/punitive/exemplary damages, and attorney fees are not covered. | p.20 |

### `mbna-extended-warranty`

#### Adjudicator

Same benefit-level adjudicator as Purchase Assurance: TD Home and Auto Insurance Company; separate administrator Global Excel Management Inc.; Group Policy `TGV012`; claims 1-866-520-8827 / +1-519-742-9356. Evidence: pp.1,18,21-22; Q-M1/Q-M2.

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `warrantyExtensionRule` | `matchesOriginalCapped` | Extension matches original Canadian manufacturer-warranty duration up to one year. | **correct** | pp.19-20 |
| `extraYears` | 1 | One year is a cap, not an automatic flat addition. | **misleading if read standalone** | pp.19-20 |
| `maxOriginalWarrantyYears` | null | Warranties longer than five years can still qualify if registered as required. | **correct null** | p.20 |
| Charge condition | full cost | Full purchase cost must be charged through the Account. | **correct** | p.19 |
| Registration rule | note only | Warranty longer than five years requires registration within one year with required documents. | **missing typed predicate** | p.20 |
| Lifetime combined limit | not typed | $60,000 across Purchase Assurance / Extended Warranty. | **missing** | p.19 |

#### Claim timing

Same shared claims process as Purchase Assurance: immediate notification condition; formal Notice of Claim within 30 days; Proof of Loss within 90 days; one-year outer late-proof cure. Evidence: pp.21-22; Q-M4/Q-M5.

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | Full purchase cost must be charged through the Account. | p.19 |
| condition | E | Original manufacturer warranty must be valid in Canada. | pp.19-20 |
| condition | E | Extension matches original warranty duration up to one year. | pp.19-20 |
| condition | E | Warranty longer than five years must be registered within one year with the stated documentation. | p.20 |
| condition | E | Combined PA/EW lifetime liability is $60,000 per Account. | p.19 |
| condition | E | Gifts remain claimable only by the Cardholder. | p.20 |
| condition | E | Other warranty/insurance is primary. | pp.20-21 |
| exclusion | E | Used items are excluded. | p.20 |
| exclusion | E | Listed motorized vehicles and dependent parts/accessories are excluded. | p.20 |
| exclusion | N | Coverage can end if the manufacturer ceases business and the original warranty obligation can no longer be honoured as described. | p.20 |
| exclusion | N | Coverage is limited to parts, labour, and obligations included in the original Canadian manufacturer warranty. | p.20 |
| exclusion | N | Fraud and abuse are excluded. | p.20 |
| exclusion | N | War/hostilities, confiscation, contraband, and illegal acts are excluded. | p.20 |
| exclusion | N | Wear and tear is excluded. | p.20 |
| exclusion | N | Flood, earthquake, and radioactive causes are excluded. | p.20 |
| exclusion | N | Mysterious disappearance is excluded. | p.20 |
| exclusion | N | Inherent defect is excluded. | p.20 |
| exclusion | N | Loss caused by modification/repair/attempted repair is excluded when causally connected. | p.20 |

### `mbna-mobile-device`

#### Adjudicator

| Field | Finding | Evidence |
|---|---|---|
| Insurer | American Bankers Insurance Company of Florida | p.42; Q-M3 |
| Claims administrator | **No different administrator company is named in the mobile-device certificate.** Assurant is the insurer group's Canadian trade name, not a separately identified administrator legal entity here. | pp.42,47 |
| Group policy | `MBNA-0620` | p.42 |
| Claims phone | 1-877-654-7511 | p.47 |
| Claims URL | `https://cardbenefits.assurant.com` | p.47 |

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `maxCad` | 1,000 | $1,000 maximum, subject to depreciation/deductible. | **correct** | pp.44-45 |
| `deductibleCad` | null | Deductible is tiered by device cost: $25/$50/$75/$100, so no single fixed value is correct. | **correct null; tiers missing** | p.45 |
| Charge condition | at least 75% or qualifying plan | Directionally correct; the certificate has three distinct payment paths including the 75% threshold and provider-plan paths. | **correct but incomplete** | pp.43-44 |
| Coverage start | not typed | Starts after the stated 30-day/first-bill start condition. | **missing** | p.44 |
| Coverage end | not typed | Ends at two years or earlier on billing/account/eligibility termination. | **missing** | p.44 |
| Depreciation | note only | 2% per completed month. | **not typed** | p.45 |
| Claim-count limit | not typed | One claim in 12 months; two in 48 months. | **missing** | p.45 |

#### Claim timing

| Timing fact | Finding | Evidence |
|---|---|---|
| Mobile-specific notice | Notify within 30 days. | pp.46-47 |
| Wireless-provider suspension | Lost/stolen service must be suspended within 48 hours. | p.47 |
| Police report | Theft must be reported to police within 7 days. | p.47 |
| Ordinary proof deadline | **Silent in the mobile-specific section reviewed.** | pp.46-47 |
| General outer rule | General provisions provide late-notice/proof relief only up to an outer one-year boundary; this is not a normal `proofDays` value. | p.48 |

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | Device must be new. | pp.43-44 |
| condition | E | Direct-purchase path requires at least 75% of Total Cost charged to the Account, including the stated buy-now-pay-later treatment. | p.44 |
| condition | E | Provider-plan path permits an upfront portion on Account plus financed balance if all required monthly bills are charged to Account. | p.44 |
| condition | E | Full-provider-plan path requires all required monthly bills charged to Account. | p.44 |
| condition | E | Cellular devices must be activated as required. | p.44 |
| condition | E | Coverage starts only after the stated 30-day/first-bill rule. | p.44 |
| condition | E | Coverage ends no later than two years and can end earlier if required billing/account eligibility stops. | p.44 |
| condition | E | Maximum benefit is $1,000. | pp.44-45 |
| condition | E | Depreciation is 2% per completed month. | p.45 |
| condition | E | Deductible tier is determined by pre-tax device cost: $25/$50/$75/$100. | p.45 |
| condition | E | Repair/replacement cost must be charged to the Account. | p.45 |
| condition | N | Replacement is limited to the same or a comparable device under certificate standards. | p.45 |
| condition | N | Manufacturer warranty is primary where applicable. | p.45 |
| condition | E | Claim frequency is capped at one in 12 months and two in 48 months. | p.45 |
| condition | N | Prior insurer approval is required before repair/replacement. | p.46 |
| exclusion | E | Accessories are excluded. | p.45 |
| exclusion | E | Batteries are excluded. | p.45 |
| exclusion | E | Devices acquired for resale/professional/commercial use are excluded. | p.45 |
| exclusion | E | Used devices are excluded. | p.45 |
| exclusion | E | Refurbished devices are excluded except for stated manufacturer/direct-provider exceptions. | p.45 |
| exclusion | E | Modified devices are excluded. | p.45 |
| exclusion | E | Devices in shipment are excluded until received/accepted. | p.45 |
| exclusion | E | Baggage theft is excluded unless the device is hand-carried/supervised as required. | p.45 |
| exclusion | N | Fraud, misuse, lack of care, and improper installation are excluded. | pp.45-46 |
| exclusion | N | War/hostilities, confiscation, contraband, and illegal acts are excluded. | p.46 |
| exclusion | N | Wear, flood, earthquake, radioactive cause, mysterious disappearance, and inherent defect are excluded. | p.46 |
| exclusion | N | Power surge/current irregularity is excluded. | p.46 |
| exclusion | N | Catastrophic damage beyond repair is excluded. | p.46 |
| exclusion | N | Cosmetic nonfunctional damage is excluded. | p.46 |
| exclusion | N | Software/provider/network causes are excluded. | p.46 |
| exclusion | N | Theft/intentional/criminal acts by the Cardholder/household are excluded under the stated rule. | p.46 |
| exclusion | N | Incidental/consequential damage is excluded. | p.46 |

---

## 4. `scotia-momentum-vi-plus`

Certificate: `Momentum-Infinite-plus-COI-EN.pdf` — 2021-07.  
Catalogue source: `https://www.scotiabank.com/content/dam/scotiabank/canada/common/documents/pdf/Momentum-Infinite-plus-COI-EN.pdf`

### Short verbatim anchors

- **Q-S1, p.4:** “First North American Insurance Company”
- **Q-S2, p.4:** “Active Claims Management (2018) Inc.”
- **Q-S3, p.11:** “aggregate maximum lifetime liability is $60,000”
- **Q-S4, p.16:** “no event later than 14 days”

All three shopping benefits use the same group policy, but adjudication is still recorded per benefit because that is the required schema shape.

### `scotia-purchase-security`

#### Adjudicator

| Field | Finding | Evidence |
|---|---|---|
| Insurer | First North American Insurance Company (FNAIC) | p.4; Q-S1 |
| Claims administrator | Active Claims Management (2018) Inc., operating under the stated Active Care Management / ACM / Global Excel names | p.4; Q-S2 |
| Group policy | `BNS749` | p.4 |
| Claims phone | 1-800-263-0997; 416-977-1552 | p.12 |
| Claims URL | `https://www.manulife.ca/scotia` | p.12 |

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `windowDays` | 90 | 90-day Purchase Security window. | **correct** | p.9 |
| `maxPerOccurrenceCad` | null | Certificate uses a $60,000 aggregate lifetime limit rather than a generic occurrence cap. | **correct null** | p.11 |
| `maxAnnualCad` | null | No generic annual maximum; lifetime aggregate governs. | **correct null** | p.11 |
| Charge condition | full price | Full purchase price must be charged to the Account. | **correct** | p.9 |
| Lifetime combined limit | not typed | $60,000 aggregate lifetime liability shared with Extended Warranty. | **missing** | p.11; Q-S3 |
| Other-insurance position | not typed | Coverage is excess over other insurance. | **missing** | pp.9-10 |

#### Claim timing

| Timing fact | Finding | Evidence |
|---|---|---|
| Notice | Notify administrator as soon as reasonably possible and before action/repair, with a 90-day outer benefit-specific deadline. | p.12 |
| Proof | Claim form and written proof as soon as possible, no later than one year. | p.12 |
| Police | Fraud/malicious act/burglary/robbery/theft must be reported to police immediately as required. | p.12 |

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | Full purchase price must be charged to the Account. | p.9 |
| condition | E | Loss/theft/damage must occur within 90 days. | p.9 |
| condition | E | Other insurance is primary; this benefit is excess. | pp.9-10 |
| condition | E | Gifts are covered with the Cardholder as claimant. | p.10 |
| condition | E | Combined lifetime Purchase Security / Extended Warranty liability is $60,000. | p.11 |
| condition | N | Payable amount is the lesser permitted repair/replacement/reimbursement amount under the certificate. | p.9 |
| condition | N | Pair/set settlement depends on usability of remaining components. | p.11 |
| exclusion | E | Travellers cheques, cash, tickets, and negotiable instruments are excluded. | p.9 |
| exclusion | E | Bullion and rare/precious coins are excluded. | p.9 |
| exclusion | E | Art objects are excluded. | p.9 |
| exclusion | E | Pre-owned/used property, including antiques and demonstration items, is excluded. | p.9 |
| exclusion | E | Animals and living plants are excluded. | p.9 |
| exclusion | E | Perishables including food/liquor are excluded. | p.9 |
| exclusion | E | Aircraft and parts are excluded. | p.9 |
| exclusion | E | Automobiles, motorboats, motorcycles, other motorized conveyances, and dependent parts/accessories are excluded. | p.9 |
| exclusion | E | Items consumed in use are excluded. | p.9 |
| exclusion | E | Services are excluded. | p.9 |
| exclusion | E | Ancillary costs beyond purchase price are excluded. | p.9 |
| exclusion | N | Parts/labour attributable to mechanical breakdown are excluded. | p.9 |
| exclusion | E | Business/commercial-use property is excluded. | p.9 |
| exclusion | E | Mail-order property is excluded until received and accepted new/undamaged. | p.9 |
| exclusion | E | Jewellery in unsupervised baggage is excluded. | p.9 |
| exclusion | N | Misuse and abuse are excluded. | p.11 |
| exclusion | N | Fraud is excluded. | p.11 |
| exclusion | N | Normal wear and tear is excluded. | p.11 |
| exclusion | N | Inherent defects are excluded. | p.11 |
| exclusion | N | Mysterious disappearance is excluded. | p.11 |
| exclusion | N | Theft from a vehicle is excluded unless the stated locked-vehicle/forced-entry requirements are met. | p.11 |
| exclusion | N | Flood, earthquake, and radioactive causes are excluded. | p.11 |
| exclusion | N | War, invasion, terrorism, rebellion, insurrection, and related hostilities are excluded. | p.11 |
| exclusion | N | Confiscation, contraband, and illegal acts are excluded. | p.11 |
| exclusion | N | Incidental/consequential losses, bodily injury, other property damage, punitive/exemplary damages, and legal fees are excluded. | pp.11-12 |

### `scotia-extended-warranty`

#### Adjudicator

Same benefit-level parties and route: FNAIC; separate administrator Active Claims Management (2018) Inc.; Group Policy `BNS749`; 1-800-263-0997 / 416-977-1552; `manulife.ca/scotia`. Evidence: pp.4,12; Q-S1/Q-S2.

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `warrantyExtensionRule` | `matchesOriginalCapped` | Extension matches original warranty duration up to one additional year. | **correct** | pp.10-11 |
| `extraYears` | 1 | One year is a cap, not a guaranteed flat addition. | **misleading if read standalone** | pp.10-11 |
| `maxOriginalWarrantyYears` | null | Longer warranties can qualify through registration; a single hard ceiling would be wrong. | **correct null** | pp.10-11 |
| Charge condition | full purchase price | Full purchase price must be charged to the Account. | **correct** | p.10 |
| Registration rule | note only | Warranty at/above the certificate's registration threshold requires registration within the first year and specified proof. | **missing typed predicate** | pp.10-11 |
| Lifetime combined limit | not typed | $60,000 shared lifetime aggregate. | **missing** | p.11; Q-S3 |

#### Claim timing

Same as Purchase Security: notify as soon as reasonably possible and within 90 days; proof no later than one year. Evidence: p.12.

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | Full purchase price must be charged to the Account. | p.10 |
| condition | E | Extension matches original manufacturer-warranty duration, capped at one year. | pp.10-11 |
| condition | E | Warranty at/above the registration threshold must be registered within the first year with the required receipt/sales slip/serial/warranty material. | pp.10-11 |
| condition | E | Gifts are covered with the Cardholder as claimant. | p.11 |
| condition | E | Other warranty/insurance is primary. | p.11 |
| condition | E | Combined lifetime Purchase Security / Extended Warranty liability is $60,000. | p.11 |
| exclusion | E | Aircraft, automobiles, motorboats, motorcycles, other motorized conveyances, and dependent parts/accessories are excluded. | p.11 |
| exclusion | E | Used property is excluded. | p.11 |
| exclusion | E | Living plants are excluded. | p.11 |
| exclusion | E | Trim parts are excluded. | p.11 |
| exclusion | E | Services are excluded. | p.11 |
| exclusion | E | Business/commercial-use items are excluded. | p.11 |
| exclusion | E | Dealer/assembler warranties are excluded. | p.11 |
| exclusion | N | Obligations outside the original manufacturer warranty are excluded. | p.11 |
| exclusion | N | Misuse/abuse and fraud are excluded. | p.11 |
| exclusion | N | Wear and tear, inherent defect, mysterious disappearance, flood/earthquake/radioactive cause, hostilities, confiscation, contraband, and illegal acts are excluded under the shared limitations. | pp.11-12 |
| exclusion | N | Incidental/consequential losses and related bodily injury/property/punitive/legal costs are excluded. | pp.11-12 |

### `scotia-mobile-device`

#### Adjudicator

| Field | Finding | Evidence |
|---|---|---|
| Insurer | First North American Insurance Company (FNAIC) | p.4; Q-S1 |
| Claims administrator | Active Claims Management (2018) Inc. under the certificate's operating names | p.4; Q-S2 |
| Group policy | `BNS749` | p.4 |
| Claims phone | 1-800-263-0997 | p.16 |
| Claims URL | `https://www.manulife.ca/scotia` | p.16 |

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `maxCad` | 1,000 | $1,000 maximum subject to depreciation/deductible. | **correct** | pp.14-15 |
| `deductibleCad` | null | Tiered $25/$50/$75/$100 deductible, so one fixed value would be wrong. | **correct null; tiers missing** | p.15 |
| Charge condition | generic | Three distinct payment/plan paths, activation, and ongoing billing continuity apply. | **incomplete** | pp.13-14 |
| Coverage start | not typed | Starts after the 30-day/first-bill start rule. | **missing** | p.14 |
| Coverage end | not typed | Ends at two years or earlier upon billing/account/eligibility termination. | **missing** | p.14 |
| Depreciation | note only | 2% per completed month. | **not typed** | p.15 |
| Claim-count limit | not typed | One claim in 12 months; two in 48 months across qualifying Scotia accounts. | **missing** | p.15 |

#### Claim timing

| Timing fact | Finding | Evidence |
|---|---|---|
| Mobile-specific contact | Contact administrator immediately and no later than 14 days. | p.16; Q-S4 |
| Formal written notice | General mobile wording provides a 90-day outer written-notice limit. | p.16 |
| Wireless-provider suspension | 48 hours after loss/theft. | p.16 |
| Police report | 7 days for theft. | p.16 |
| Ordinary proof deadline | **Silent in the mobile-specific section reviewed.** | p.16 |
| General outer cure | General provisions contain a one-year outside boundary for late notice/proof when timely compliance was not reasonably possible; not a normal `proofDays` value. | p.36 |

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | Device must be new. | p.13 |
| condition | E | Full-purchase path requires full price charged to Account and qualifying activation where applicable. | p.13 |
| condition | E | Provider-financing path permits an upfront Account charge plus financed balance if all required monthly bills are charged to Account. | p.13 |
| condition | E | Full-provider-plan path requires all monthly bills charged to Account. | p.13 |
| condition | E | Coverage starts only after the stated 30-day/first-bill rule. | p.14 |
| condition | E | Coverage ends after two years at the latest and earlier if required billing/account eligibility stops. | p.14 |
| condition | E | Maximum benefit is $1,000. | pp.14-15 |
| condition | E | Depreciation is 2% per completed month. | p.15 |
| condition | E | Deductible tiers are $25/$50/$75/$100 based on device price. | p.15 |
| condition | N | Replacement must satisfy same/like-kind standards. | p.15 |
| condition | N | Manufacturer warranty is primary where applicable. | p.15 |
| condition | E | Claim frequency is capped at one in 12 months and two in 48 months. | p.15 |
| condition | N | Prior insurer approval is required before repair/replacement. | p.15 |
| exclusion | E | Accessories and batteries are excluded. | p.15 |
| exclusion | E | Devices acquired for resale/professional/commercial use are excluded. | p.15 |
| exclusion | E | Used/previously owned/refurbished devices are excluded. | p.15 |
| exclusion | E | Modified devices are excluded. | p.15 |
| exclusion | E | Devices in shipment are excluded until received/accepted. | p.15 |
| exclusion | E | Baggage theft is excluded unless hand-carried/supervised as required. | p.15 |
| exclusion | N | Fraud, misuse, lack of care, and improper installation are excluded. | p.15 |
| exclusion | N | War/hostilities, confiscation, contraband, illegal acts, wear, flood, earthquake, radioactive cause, mysterious disappearance, and inherent defects are excluded. | p.15 |
| exclusion | N | Power surge/current irregularity is excluded. | p.15 |
| exclusion | N | Catastrophic damage beyond repair is excluded. | p.15 |
| exclusion | N | Cosmetic nonfunctional damage is excluded. | p.15 |
| exclusion | N | Software/provider/network causes are excluded. | pp.15-16 |
| exclusion | N | Theft/intentional/criminal acts by the Cardholder/household are excluded under the stated rule. | p.16 |
| exclusion | N | Incidental/consequential damage is excluded. | p.16 |

---

## 5. `tangerine-moneyback-world`

Certificate: `5_Tangerine_World_Mastercard_Certificate_of_Insurance_FINAL.pdf` — amended/restated 2025-10-25.  
Catalogue source: `https://www.tangerine.ca/content/dam/tangerine/en/pdfs/credit-card-cardholder-agreement/5_Tangerine_World_Mastercard_Certificate_of_Insurance_FINAL.pdf`

### Short verbatim anchors

- **Q-T1, p.1:** “American Bankers Insurance Company of Florida”
- **Q-T2, p.1:** “Claim payment and administrative services are provided by the Insurer.”
- **Q-T3, p.10:** “no event later than 14 days”

### `tangerine-purchase-assurance`

#### Adjudicator

| Field | Finding | Evidence |
|---|---|---|
| Insurer | American Bankers Insurance Company of Florida | p.1; Q-T1 |
| Claims administrator | **No separate administrator company named.** Administrative/claim-payment services are expressly performed by the insurer. | p.1; Q-T2 |
| Group policy | `BNS092015` | p.1 |
| Claims phone | 1-855-255-6050 | pp.6-7 |
| Claims URL | `https://cardbenefits.assurant.com` | pp.6-7 |

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `windowDays` | 90 | 90-day Purchase Assurance window. | **correct** | pp.3-4 |
| `maxPerOccurrenceCad` | null | Certificate is governed by lifetime aggregate and settlement rules rather than a generic occurrence cap. | **correct null** | p.6 |
| `maxAnnualCad` | null | No generic annual limit; lifetime aggregate applies. | **correct null** | p.6 |
| Charge condition | full cost | Full Cost must be charged to the Card. | **correct** | p.3 |
| Lifetime combined limit | not typed | $60,000 lifetime PA/EW liability. | **missing** | p.6 |
| Repair/replacement charge condition | not typed | Approved repair/replacement cost must also be charged to the Account as required. | **missing** | pp.3-4 |

#### Claim timing

| Timing fact | Finding | Evidence |
|---|---|---|
| Initial notice condition | Notify insurer immediately after learning of the loss and before repairs/replacement. | pp.6-7 |
| Numeric benefit-specific notice deadline | **Silent in the PA/EW sections reviewed.** Do not convert the immediate-notice language into an invented day count. | pp.6-7 |
| Proof | Proof of Loss within 90 days. | p.7 |
| General outside bar | General statutory provisions contain a one-year outside rule for notice/proof; this is not a substitute for a missing benefit-specific `claimNoticeDays`. | p.15 |

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | Full Cost must be charged to the Tangerine Money-Back World Mastercard Account. | p.3 |
| condition | E | Loss/theft/damage must occur within 90 days. | pp.3-4 |
| condition | E | Other insurance is primary and this benefit is excess. | p.6 |
| condition | E | Gifts are claimable by the Cardholder. | p.4 |
| condition | E | Combined lifetime Purchase Assurance / Extended Warranty liability is $60,000. | p.6 |
| condition | N | Repair/replacement/reimbursement is limited to the certificate's approved settlement basis and original Full Cost. | pp.3-4 |
| condition | E | Approved repair/replacement spend must be charged to the Account as required. | p.4 |
| condition | N | Pair/set settlement depends on separate usability. | p.6 |
| exclusion | E | Travellers cheques, cash, tickets, and negotiable instruments are excluded. | p.3 |
| exclusion | E | Bullion and rare/precious coins are excluded. | p.3 |
| exclusion | E | Art objects are excluded. | p.3 |
| exclusion | E | Pre-owned, used, refurbished, antique, and demonstration items are excluded. | p.3 |
| exclusion | E | Animals and living plants are excluded. | p.3 |
| exclusion | E | Consumables/perishables, including food/liquor/cosmetics/fragrances/home test kits, are excluded. | p.3 |
| exclusion | E | Aircraft, rotorcraft, drones, and related parts are excluded. | p.3 |
| exclusion | E | Automobiles, motorboats, motorcycles, e-bikes, other motorized conveyances, and dependent parts/accessories are excluded. | p.3 |
| exclusion | E | Services, including delivery/transportation, are excluded. | p.3 |
| exclusion | E | Ancillary costs are excluded. | p.3 |
| exclusion | N | Mechanical-breakdown parts/labour are excluded. | p.3 |
| exclusion | E | Business/commercial-use property is excluded. | p.3 |
| exclusion | E | Mail/internet/telephone orders are excluded until received and accepted. | p.3 |
| exclusion | E | Jewellery in unsupervised baggage is excluded. | p.3 |
| exclusion | N | Damage during delivery is excluded from Purchase Assurance. | p.3 |
| exclusion | N | Misuse/abuse and fraud are excluded. | p.6 |
| exclusion | N | Wear/tear, inherent defect, and mysterious disappearance are excluded. | p.6 |
| exclusion | N | Vehicle theft without the stated locked/forced-entry facts is excluded. | p.6 |
| exclusion | N | Flood, earthquake, radioactive cause, war/invasion/terrorism/rebellion/insurrection, confiscation, contraband, and illegal acts are excluded. | p.6 |
| exclusion | N | Incidental/consequential losses, bodily injury, property damage, punitive/exemplary damages, and legal fees are excluded. | p.6 |

### `tangerine-extended-warranty`

#### Adjudicator

Same benefit-level adjudicator: American Bankers Insurance Company of Florida; **no separate administrator company**; Group Policy `BNS092015`; claims 1-855-255-6050 / `cardbenefits.assurant.com`. Evidence: pp.1,4-7; Q-T1/Q-T2.

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `warrantyExtensionRule` | `matchesOriginalCapped` | Original manufacturer warranty is matched, capped at one additional year. | **correct** | pp.4-5 |
| `extraYears` | 1 | One year is a cap rather than a guaranteed flat addition. | **misleading if read standalone** | pp.4-5 |
| `maxOriginalWarrantyYears` | null | Longer warranties may qualify if registered within one year. | **correct null** | pp.4-5 |
| Charge condition | full cost | Full Cost must be charged to the Card. | **correct** | p.4 |
| Registration rule | note only | Warranty at/above the stated threshold requires registration with required documents within one year. | **missing typed predicate** | pp.4-5 |
| Lifetime combined limit | not typed | $60,000 lifetime combined PA/EW limit. | **missing** | p.6 |

#### Claim timing

Immediate-notice-before-repair condition; **no numeric benefit-specific notice-day ceiling in the PA/EW section**; Proof of Loss within 90 days. General statutory one-year outside rule is not substituted for `claimNoticeDays`. Evidence: pp.6-7,15.

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | Full Cost must be charged to the Card. | p.4 |
| condition | E | Extension matches original warranty duration, capped at one year. | pp.4-5 |
| condition | E | Longer original warranties require registration within one year with required documentation. | pp.4-5 |
| condition | E | Combined PA/EW lifetime liability is $60,000. | p.6 |
| condition | E | Gifts remain claimable by the Cardholder. | p.5 |
| condition | E | Other warranty/insurance is primary. | pp.5-6 |
| exclusion | E | Aircraft/drones and related parts are excluded. | p.5 |
| exclusion | E | Motorized conveyances/e-bikes and dependent parts/accessories are excluded. | p.5 |
| exclusion | E | Pre-owned/used/refurbished property is excluded. | p.5 |
| exclusion | E | Living plants are excluded. | p.5 |
| exclusion | E | Trim parts are excluded. | p.5 |
| exclusion | E | Services are excluded. | p.5 |
| exclusion | E | Business/commercial-use items are excluded. | p.5 |
| exclusion | E | Dealer/assembler warranties are excluded. | p.5 |
| exclusion | N | Obligations outside the original manufacturer warranty are excluded. | p.5 |
| exclusion | N | Shared PA/EW limitations exclude misuse/abuse, fraud, wear/tear, inherent defect, mysterious disappearance, vehicle-theft circumstances, flood/earthquake/radioactive causes, hostilities, confiscation, contraband, and illegal acts. | p.6 |
| exclusion | N | Shared limitations exclude incidental/consequential loss and related injury/property/punitive/legal costs. | p.6 |

### `tangerine-mobile-device`

#### Adjudicator

| Field | Finding | Evidence |
|---|---|---|
| Insurer | American Bankers Insurance Company of Florida | p.1; Q-T1 |
| Claims administrator | **No separate administrator company named; insurer performs administrative/claim-payment services.** | p.1; Q-T2 |
| Group policy | `BNS092015` | p.1 |
| Claims phone | 1-855-255-6050 | p.10 |
| Claims URL | `https://cardbenefits.assurant.com` | p.10; the mobile section contains an apparent OCR/print typo in one rendering, while the certificate's other claim references use this route |

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `maxCad` | 1,000 | $1,000 maximum subject to depreciation/deductible. | **correct** | pp.8-9 |
| `deductibleCad` | null | Tiered $25/$50/$75/$100 deductible. | **correct null; tiers missing** | p.9 |
| Charge condition | generic | Three distinct purchase/provider-plan payment paths plus activation and billing continuity. | **incomplete** | pp.7-8 |
| Coverage start | not typed | Starts after the stated 30-day/first-bill condition. | **missing** | p.8 |
| Coverage end | not typed | Ends at two years or earlier if billing/account eligibility stops. | **missing** | p.8 |
| Depreciation | note only | 2% per completed month. | **not typed** | p.9 |
| Claim-count limit | not typed | One claim in 12 months; two in 48 months. | **missing** | p.9 |

#### Claim timing

| Timing fact | Finding | Evidence |
|---|---|---|
| Mobile-specific notice | Contact insurer immediately and no later than 14 days. | p.10; Q-T3 |
| Wireless-provider suspension | 48 hours. | p.10 |
| Police report | 7 days for theft. | p.10 |
| Ordinary proof deadline | **Silent in the mobile-specific section reviewed.** | p.10 |
| General outside rule | Statutory/general provisions contain a one-year outside notice/proof rule, not a tighter ordinary mobile `proofDays` value. | p.15 |

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | Device must be new. | pp.7-8 |
| condition | E | Full-purchase path requires the full Total Cost charged to Card and qualifying activation where applicable. | p.8 |
| condition | E | Provider-financing path permits an upfront Card portion plus provider-financed balance if all required monthly bills are charged to Card. | p.8 |
| condition | E | Full-provider-plan path requires all monthly bills charged to Card. | p.8 |
| condition | E | The Total Cost definition applies the certificate's taxes/trade-in/BNPL treatment. | pp.7-8 |
| condition | E | Coverage starts only after the stated 30-day/first-bill rule. | p.8 |
| condition | E | Coverage ends no later than two years and can end earlier on billing/account eligibility failure. | p.8 |
| condition | E | Maximum benefit is $1,000. | pp.8-9 |
| condition | E | Depreciation is 2% per completed month. | p.9 |
| condition | E | Deductible tiers are $25/$50/$75/$100 by device cost. | p.9 |
| condition | E | Repair/replacement cost must be charged to the Account. | p.9 |
| condition | N | Replacement must be same or like-kind under insurer standards. | p.9 |
| condition | N | Manufacturer warranty is primary where applicable. | p.9 |
| condition | E | Claim frequency is capped at one in 12 months and two in 48 months. | p.9 |
| condition | N | Prior approval is required before repair/replacement. | p.9 |
| exclusion | E | Accessories and batteries are excluded. | p.9 |
| exclusion | E | Resale/professional/commercial-use devices are excluded. | p.9 |
| exclusion | E | Used devices are excluded. | p.9 |
| exclusion | E | Refurbished devices are excluded except for the stated manufacturer/direct-source exceptions. | p.9 |
| exclusion | E | Modified devices are excluded. | p.9 |
| exclusion | E | Devices in shipment are excluded until received/accepted. | p.9 |
| exclusion | E | Baggage theft is excluded unless hand-carried/supervised as required. | p.9 |
| exclusion | N | Fraud, misuse, lack of care, improper installation, hostilities, confiscation, contraband, illegal acts, wear, flood, earthquake, radioactive cause, mysterious disappearance, and inherent defect are excluded. | pp.9-10 |
| exclusion | N | Power surge/current irregularity is excluded. | p.10 |
| exclusion | N | Catastrophic damage beyond repair is excluded. | p.10 |
| exclusion | N | Cosmetic nonfunctional damage is excluded. | p.10 |
| exclusion | N | Software/provider/network causes are excluded. | p.10 |
| exclusion | N | Theft/intentional/criminal acts by the Cardholder/household are excluded under the stated rule. | p.10 |
| exclusion | N | Incidental/consequential damage is excluded. | p.10 |

---

## 6. `rogers-red-we`

Certificate: `Rogers_Bank_World_Elite_Mastercard_Certificate_of_Insurance.pdf` — 2024-04.  
Catalogue source: `https://www.rogersbank.com/legaldocs/en/Rogers_Bank_World_Elite_Mastercard_Certificate_of_Insurance.pdf`

### Short verbatim anchors

- **Q-R1, p.24:** “CUMIS General Insurance Company”
- **Q-R2, p.24:** “Allianz Global Assistance”
- **Q-R3, p.28:** “within 30 days”
- **Q-R4, p.28:** “within 90 days”
- **Q-R5, p.27:** “a three-month warranty”
- **Q-R6, p.27:** “maximum of one additional year”

### `rogers-purchase-protection`

#### Adjudicator

| Field | Finding | Evidence |
|---|---|---|
| Insurer | CUMIS General Insurance Company | p.24; Q-R1 |
| Claims administrator | AZGA Service Canada Inc., operating under the registered business name Allianz Global Assistance | p.24; Q-R2 |
| Group policy | `FC310040-C` | p.24 |
| Claims phone | 1-866-856-7323; +1-519-742-1723 | pp.29,31 |
| Claims URL | `https://www.allianzassistanceclaims.ca` | pp.29,31 |

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `windowDays` | 90 | 90-day Purchase Protection window. | **correct** | p.26 |
| `maxPerOccurrenceCad` | null | Certificate uses settlement rules and a lifetime combined account cap, not a generic occurrence cap. | **correct null** | p.26 |
| `maxAnnualCad` | null | No generic annual maximum; combined lifetime cap applies. | **correct null** | p.26 |
| Charge condition | full purchase price | Full purchase price must be charged to the Account. | **correct** | p.26 |
| Lifetime combined limit | not typed | $60,000 lifetime combined PP/EW account limit. | **missing** | p.26 |
| Pair/set rule | not typed | Pair/set settlement can be limited to affected components. | **missing** | p.26 |

#### Claim timing

| Timing fact | Finding | Evidence |
|---|---|---|
| Written notice | Within 30 days of the claim. | p.28; Q-R3 |
| Proof | Within 90 days. | p.28; Q-R4 |
| Late compliance | If timely compliance was not reasonably possible, certificate permits later compliance subject to the one-year outer boundary. | p.28 |
| Insurer response commitment | **Explicitly excluded from modelling.** The separate 60-day insurer-payment statement is not claimant notice/proof timing. | p.28 |

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | N | Cardholder must meet the certificate's Canadian-residency/cardholder eligibility. | p.26 |
| condition | E | Full purchase price must be charged to the Account. | p.26 |
| condition | E | Loss/theft/damage must occur within 90 days. | p.26 |
| condition | E | Combined PP/EW lifetime liability is $60,000 per Account. | p.26 |
| condition | N | Settlement is limited to the lesser permitted repair/replacement/purchase-price amount. | p.26 |
| condition | N | Pair/set settlement depends on separate usability/value of affected pieces. | p.26 |
| condition | E | Other insurance is primary and this benefit is excess. | pp.27-28 |
| exclusion | E | Items left behind are excluded. | p.26 |
| exclusion | E | Travellers cheques, money, tickets, documents, bullion, banknotes, negotiable instruments, and numismatic property are excluded. | p.26 |
| exclusion | E | Animals, fish, birds, and plants are excluded. | p.26 |
| exclusion | E | Consumable/perishable property is excluded. | p.26 |
| exclusion | E | Mail/online purchases are excluded until delivered and accepted in satisfactory condition. | p.26 |
| exclusion | E | Golf balls are excluded. | p.26 |
| exclusion | E | Used, pre-owned, rebuilt, refurbished, returned/resold property is excluded. | p.26 |
| exclusion | E | Automobiles, trailers, motorcycles, motorboats, and attached accessories are excluded. | p.26 |
| exclusion | E | Scooters and motorized wheelchairs are excluded. | p.26 |
| exclusion | E | Snow blowers, riding lawnmowers, golf carts, and lawn tractors are excluded. | p.26 |
| exclusion | E | Airplanes and drones are excluded. | p.26 |
| exclusion | E | Hoverboards and other listed motorized conveyances/parts are excluded subject to the stated miniature-child-vehicle exception. | p.26 |
| exclusion | E | Cellular phones/smartphones are excluded. | p.26 |
| exclusion | E | Business/commercial equipment is excluded. | p.26 |
| exclusion | N | Fraud and abuse are excluded. | p.27 |
| exclusion | N | Hostilities/war, confiscation, contraband, and illegal activity are excluded. | p.27 |
| exclusion | N | Delay, loss of use, and consequential loss are excluded. | p.27 |
| exclusion | N | Wear/tear and gradual deterioration are excluded. | p.27 |
| exclusion | N | Damage caused during installation/work is excluded when the stated causal requirement is met. | p.27 |
| exclusion | N | Insects/vermin are excluded. | p.27 |
| exclusion | N | Flood, earthquake, and radioactive causes are excluded. | p.27 |
| exclusion | N | Listed environmental/material-change causes such as settling, expansion/contraction, cracking, temperature, damp/dry conditions, evaporation/leakage, light, rust, and corrosion are excluded. | p.27 |
| exclusion | N | Sports-equipment damage caused by its use is excluded. | p.27 |
| exclusion | N | Mysterious disappearance is excluded. | p.27 |
| exclusion | N | Inherent defects are excluded. | p.27 |
| exclusion | E | One-of-a-kind items are excluded. | p.27 |
| exclusion | N | Unconditional-guarantee property is excluded. | p.27 |
| exclusion | N | Theft from a vehicle/residence without the required evidence of forcible entry is excluded. | p.27 |
| exclusion | N | Injury, other property damage, consequential/punitive/exemplary damages, attorney fees, and ancillary costs are excluded. | pp.27-28 |
| condition | N | Cardholder must exercise due diligence and cooperate with subrogation/claims requirements. | p.28 |
| exclusion | N | False/fraudulent claim conduct can terminate coverage. | p.28 |

### `rogers-extended-warranty`

#### Adjudicator

Same benefit-level adjudicator: CUMIS General Insurance Company; separate administrator AZGA Service Canada Inc. d/b/a Allianz Global Assistance; Group Policy `FC310040-C`; 1-866-856-7323 / +1-519-742-1723; `allianzassistanceclaims.ca`. Evidence: pp.24,29,31; Q-R1/Q-R2.

#### Published coverage verification

| Catalogue field / fact | Current | Certificate finding | Verdict | Evidence |
|---|---:|---|---|---|
| `warrantyExtensionRule` | `matchesOriginalCapped` | Extension matches the original warranty duration, capped at one year. | **correct** | pp.26-27; Q-R6 |
| `extraYears` | 1 | The certificate's own short-warranty example confirms that one year is only a cap; a three-month original warranty receives a three-month extension. | **misleading if read standalone** | p.27; Q-R5/Q-R6 |
| `maxOriginalWarrantyYears` | null | Warranties longer than five years may qualify if registered within one year. | **correct null** | pp.26-27 |
| Charge condition | full purchase price | Full purchase price must be charged to the Account. | **correct** | p.26 |
| Registration rule | note only | Warranty longer than five years requires registration with Allianz within one year. | **missing typed predicate** | pp.26-27 |
| Lifetime combined limit | not typed | $60,000 lifetime combined PP/EW account limit. | **missing** | p.26 |

#### Claim timing

Written notice within 30 days; Proof of Loss within 90 days; late-compliance relief subject to a one-year outer boundary. The insurer's separate 60-day post-proof payment commitment is **not** a claimant coverage term and is not modelled. Evidence: p.28; Q-R3/Q-R4.

#### Predicates

| Type | Eval | Predicate | Source |
|---|:---:|---|---|
| condition | E | Full purchase price must be charged to the Account. | p.26 |
| condition | E | Original manufacturer warranty must be valid in Canada. | p.26 |
| condition | E | Extension matches original warranty duration up to one year. | pp.26-27 |
| condition | E | Warranty longer than five years must be registered within one year. | pp.26-27 |
| condition | E | Combined PP/EW lifetime liability is $60,000. | p.26 |
| condition | N | Extended Warranty follows the covered obligations/settlement permissions of the original manufacturer warranty. | p.27 |
| exclusion | E | Commercial/business items are excluded. | p.26 |
| exclusion | N | Coverage can fail if the manufacturer ceases business and warranty obligations cannot be honoured as described. | p.27 |
| exclusion | E | Used, pre-owned, rebuilt, refurbished, and returned/resold items are excluded. | p.27 |
| exclusion | E | Listed motorized conveyances and dependent parts/accessories are excluded. | p.27 |
| exclusion | E | Airplanes and drones are excluded. | p.27 |
| exclusion | E | Cellular phones/smartphones are excluded. | p.27 |
| exclusion | E | Lifetime warranties are excluded from extension. | p.27 |
| exclusion | N | Only parts/labour/obligations included in the original Canadian manufacturer warranty are eligible. | p.27 |
| exclusion | N | Shared exclusions include fraud, abuse, hostilities, confiscation, contraband, illegal activity, delay/loss of use, wear/deterioration, installation-caused damage, vermin, flood/earthquake/radioactive causes, listed environmental/material-change causes, sports-use damage, mysterious disappearance, inherent defects, forced-entry theft conditions, and consequential/punitive/legal losses. | pp.27-28 |
| condition | N | Due-diligence, cooperation, and subrogation duties apply. | p.28 |
| exclusion | N | False/fraudulent claim conduct can terminate coverage. | p.28 |

---

## Consolidated defects against `contracts/benefits-catalogue.json` v1.4

| # | Card / benefit | Current catalogue defect or residual risk | Severity |
|---:|---|---|---|
| 1 | all 14 shopping benefits in this batch | No typed per-benefit adjudicator object carrying insurer, separate administrator, group policy, and claims route. MBNA proves this cannot safely live only at card level because its mobile insurer differs from PA/EW. | **high / structural** |
| 2 | all 14 shopping benefits | Claim-notice and proof timing are not typed even where certificates state concrete deadlines. | **high / structural** |
| 3 | all 14 shopping benefits | `exclusions` is effectively empty while every certificate contains material eligibility/exclusion clauses. | **high / correctness** |
| 4 | all reviewed Extended Warranty benefits | `warrantyExtensionRule: matchesOriginalCapped` is now **correct**, but `extraYears: 1` remains unsafe if any downstream consumer treats it as a flat addition. Keep the rule authoritative or remove/deprecate the ambiguous scalar. | **high / modelling** |
| 5 | `cobalt-extended-warranty` | Missing typed $10,000/item and $25,000/Cardmember/policy-year limits and full-price charge predicate. | **high** |
| 6 | `bonvoy-extended-warranty` | Missing typed $10,000/item and $25,000/Cardmember/policy-year limits and full-price charge predicate. | **high** |
| 7 | `cobalt-purchase-protection` | Missing payout-basis rule limiting reimbursement to the charged portion. | **medium-high** |
| 8 | `bonvoy-purchase-protection` | Missing payout-basis rule limiting reimbursement to the charged portion. | **medium-high** |
| 9 | `mbna-purchase-protection` | Null generic occurrence/annual caps are defensible, but typed $60,000 lifetime limit plus $1,000 computer/software and $500 jewellery/fine-art sublimits are missing. | **high** |
| 10 | `mbna-extended-warranty` | Missing typed >5-year warranty registration rule and shared $60,000 lifetime limit. | **high** |
| 11 | `scotia-purchase-security` | Missing typed $60,000 combined lifetime limit. | **high** |
| 12 | `scotia-extended-warranty` | Missing typed warranty-registration condition and $60,000 lifetime limit. | **high** |
| 13 | `tangerine-purchase-assurance` | Missing typed $60,000 combined lifetime limit and repair/replacement charge condition. | **high** |
| 14 | `tangerine-extended-warranty` | Missing typed warranty-registration condition and $60,000 lifetime limit. | **high** |
| 15 | `rogers-purchase-protection` | Null generic occurrence/annual limits are defensible, but the $60,000 combined lifetime account limit is not typed. | **high** |
| 16 | `rogers-extended-warranty` | Missing typed >5-year warranty registration condition and $60,000 lifetime account limit. | **high** |
| 17 | `cobalt-mobile-device` | `maxCad` and null fixed deductible are correct, but 10%-of-depreciated-value deductible, 2% monthly depreciation, three payment paths, start/end rules, and claim-count limits are not typed. | **high** |
| 18 | `mbna-mobile-device` | `maxCad`, null fixed deductible, and 75%/plan condition are directionally correct; tiered deductible, depreciation, exact plan paths, start/end rules, and claim-count limits are missing. | **high** |
| 19 | `scotia-mobile-device` | Generic charge condition hides three payment paths, start/end rules, tiered deductible, depreciation, prior approval, and claim-count limits. | **high** |
| 20 | `tangerine-mobile-device` | Generic charge condition hides three payment paths, start/end rules, tiered deductible, depreciation, prior approval, and claim-count limits. | **high** |
| 21 | Amex Purchase Protection (`cobalt`, `bonvoy`) | Claim timing has two claimant obligations — 48-hour report plus later written notice/proof — so a single undifferentiated `claimNoticeDays` field may be insufficient without an `initialReportHours`/secondary-notice distinction. | **schema risk** |
| 22 | Tangerine PA/EW | Certificate requires immediate notification before repair/replacement but provides no numeric benefit-specific notice-day ceiling in those sections. Model as **silent numeric deadline + immediate condition**, not inferred days. | **schema risk** |
| 23 | MBNA/Scotia/Tangerine mobile | Mobile-specific sections require claim forms/supporting documents but do not state a normal numeric proof-by-N-days deadline. General one-year outside/cure language must not be misrepresented as ordinary `proofDays: 365`. | **schema risk** |
| 24 | Rogers PP/EW | Certificate separately promises insurer payment after proof. That response commitment must remain excluded from claimant timing; recording it as a notice/proof deadline would invert the obligation. | **extraction trap** |

## Batch conclusion

The six-card re-read reinforces the pilot's schema direction while correcting the stale part of the original Batch 02 conclusion. The warranty **rule** has already been repaired in catalogue v1.4; the next gated contract-authoring pass should focus on the remaining structural facts: per-benefit adjudicator, typed claimant timing, typed lifetime/sub-limits, structured mobile payment/start/deductible logic, and the full predicate sets.

No `contracts/` bytes were changed in this pass.