# Candidate application requirements — 2026-08-31

Research-only dossier for PickMe acquisition candidates. Facts below are written in PickMe's own words and use first-party issuer sources only. No raw issuer HTML is retained.

> **Environment note:** the requested local path `/Users/zub/Documents/Github_Projects/PickMe` was not mounted in this runtime, so local uncommitted `git status` could not be inspected. Repository rules and catalogue state were read from the connected `zubairmuwwakil/PickMe` GitHub repository. No local worktree file was touched. This document is the only repository write made by this research session.

## 1. Executive summary

### Bottom line

| cardId | research result | financial qualification | important non-financial findings |
|---|---|---|---|
| `simplii-cashback-visa` | **Complete for deterministic issuer-published requirements located** | Household annual income **at least CAD 15,000**. No issuer-published personal-income alternative found. | Must live in Canada; must be a Canadian citizen **or** permanent resident; Quebec excluded; age of majority; no bankruptcy declaration in previous 7 years. |
| `amex-simplycash-preferred` | **Complete for deterministic issuer-published requirements located** | **No issuer-published income minimum found.** No AUM or spend alternative found. | Canadian resident **and** Canadian credit file; age of majority. Amex asks for employment, income and bank information, but does not publish a qualifying amount or exact credit-score threshold for this card. |
| `bmo-cashback-world-elite` | **Complete for deterministic issuer-published requirements located** | Individual annual income **at least CAD 80,000** **OR** household annual income **at least CAD 150,000**. | Canadian citizen **or** permanent resident; no bankruptcy declaration in previous 7 years; age of majority. BMO lists application inputs separately; those are not thresholds. |
| `mbna-smart-cash-world` | **Partial** | Personal annual income **strictly greater than CAD 50,000** **OR** household annual income **at least CAD 80,000**. | Canadian resident; age of majority. MBNA explicitly says additional account qualification criteria apply as set out in the application, but does not enumerate those criteria on the reviewed public issuer pages. |
| `home-trust-preferred-visa` | **Complete for deterministic issuer-published application declarations located, with one official-source conflict** | Applicant annual income **at least CAD 15,000**. No household alternative found. | Live application requires “permanent Canadian resident,” not Quebec, age of majority, bankruptcy discharge for **at least 2 years**, no third-party account opening, and consent to a consumer report/credit check. Product FAQ is weaker on bankruptcy (“cannot currently be in bankruptcy”). |
| `rbc-cashback-preferred-we` | **Partial** | Personal annual income **at least CAD 80,000** **OR** household annual income **at least CAD 150,000**. Existing PickMe amount is correct. | No card-specific primary-applicant residency, age, bankruptcy, local-credit-file, AUM, or spend-alternative gate was found. RBC issuer-general guidance is not promoted to a card-specific deterministic rule. |

“Complete” above means complete for deterministic requirements the issuer currently publishes in the reviewed card/application surfaces. It is **not** a guarantee of approval: every credit issuer retains credit-adjudication discretion.

### High-value findings for PickMe

1. **Simplii is household-income-only in its published threshold.** The issuer states a minimum household annual income of CAD 15,000 and does not publish a separate personal-income route for this card.
2. **Amex SimplyCash Preferred has no published numeric income or credit-score minimum.** Do not normalize absence into `$0` or “no income requirement.” The correct state is “no issuer-published minimum found.”
3. **BMO is CAD 80,000 individual OR CAD 150,000 household, both `atLeast`.**
4. **MBNA operator semantics matter:** personal income is **`greaterThan 50000`**, while household income is **`atLeast 80000`**. A person reporting exactly CAD 50,000 does not satisfy the published personal route.
5. **Home Trust has an application-vs-marketing conflict:** the product FAQ says the applicant cannot *currently* be bankrupt; the live application requires the applicant to have been **discharged for at least 2 years**. The application declaration is the stronger and more directly operative gate.
6. **RBC’s existing CAD 80,000 / CAD 150,000 annotation is verified.** No AUM or declared-card-spending alternative was found for this specific personal card. RBC does publish such alternatives for at least one different business World Elite product; that is positive evidence that those routes are product-specific and must not be imported into this candidate by network or issuer analogy.
7. **No exact issuer-published credit-score minimum was found for any of the six cards.**
8. **No candidate publishes an AUM alternative or declared annual card-spending alternative on the reviewed card-specific/application sources.**

## 2. Normalized requirement-path table

`logical group` is written from the applicant's perspective. `all:core` means the requirement is conjunctive with other core requirements. `any:*` denotes explicit alternatives. Amounts are annual unless stated otherwise.

| cardId | requirement type | operator | amount/value | currency | logical group | scope | source | verifiedAt | D3 status |
|---|---|---:|---|---|---|---|---|---|---|
| `simplii-cashback-visa` | `householdAnnualIncome` | `atLeast` | `15000` | CAD | `all:core / any:financial` (only published option) | card-specific FAQ | S1, S2 | 2026-08-31 | `issuerConfirmed` |
| `simplii-cashback-visa` | `countryResidency` | `equals` | `Canada` | — | `all:core` | card-specific FAQ | S1, S2 | 2026-08-31 | `issuerConfirmed` |
| `simplii-cashback-visa` | `citizenshipStatus` | `equals` | `CanadianCitizen` | — | `all:core / any:status` | card-specific FAQ | S1, S2 | 2026-08-31 | `issuerConfirmed` |
| `simplii-cashback-visa` | `immigrationStatus` | `equals` | `PermanentResident` | — | `all:core / any:status` | card-specific FAQ | S1, S2 | 2026-08-31 | `issuerConfirmed` |
| `simplii-cashback-visa` | `provinceResidency` | `notEquals` | `Quebec` | — | `all:core` | card-specific FAQ | S1, S2 | 2026-08-31 | `issuerConfirmed` |
| `simplii-cashback-visa` | `age` | `atLeast` | `age of majority in province or territory` | — | `all:core` | card-specific FAQ | S2 | 2026-08-31 | `issuerConfirmed` |
| `simplii-cashback-visa` | `bankruptcyDeclarationLookback` | `noneWithin` | `7 years` | — | `all:core` | card-specific FAQ | S2 | 2026-08-31 | `issuerConfirmed` |
| `amex-simplycash-preferred` | `countryResidency` | `equals` | `Canada` | — | `all:core` | card-specific Eligibility section | S3 | 2026-08-31 | `issuerConfirmed` |
| `amex-simplycash-preferred` | `localCreditFile` | `exists` | `Canadian credit file` | — | `all:core` | card-specific Eligibility section | S3 | 2026-08-31 | `issuerConfirmed` |
| `amex-simplycash-preferred` | `age` | `atLeast` | `age of majority in province or territory of residence` | — | `all:core` | card-specific Eligibility section | S3 | 2026-08-31 | `issuerConfirmed` |
| `bmo-cashback-world-elite` | `individualAnnualIncome` | `atLeast` | `80000` | CAD | `all:core / any:financial` | card-specific product page | S5 | 2026-08-31 | `issuerConfirmed` |
| `bmo-cashback-world-elite` | `householdAnnualIncome` | `atLeast` | `150000` | CAD | `all:core / any:financial` | card-specific product page | S5 | 2026-08-31 | `issuerConfirmed` |
| `bmo-cashback-world-elite` | `citizenshipStatus` | `equals` | `CanadianCitizen` | — | `all:core / any:status` | BMO credit-card eligibility FAQ embedded on card page | S5 | 2026-08-31 | `issuerConfirmed` |
| `bmo-cashback-world-elite` | `immigrationStatus` | `equals` | `PermanentResident` | — | `all:core / any:status` | BMO credit-card eligibility FAQ embedded on card page | S5 | 2026-08-31 | `issuerConfirmed` |
| `bmo-cashback-world-elite` | `bankruptcyDeclarationLookback` | `noneWithin` | `7 years` | — | `all:core` | BMO credit-card eligibility FAQ embedded on card page | S5 | 2026-08-31 | `issuerConfirmed` |
| `bmo-cashback-world-elite` | `age` | `atLeast` | `18 in AB, MB, ON, PE, QC, SK; 19 in all other provinces` | — | `all:core` | BMO credit-card eligibility FAQ embedded on card page | S5 | 2026-08-31 | `issuerConfirmed` |
| `mbna-smart-cash-world` | `individualAnnualIncome` | `greaterThan` | `50000` | CAD | `all:core / any:financial` | card-specific World-account footnote | S6, S8 | 2026-08-31 | `issuerConfirmed` |
| `mbna-smart-cash-world` | `householdAnnualIncome` | `atLeast` | `80000` | CAD | `all:core / any:financial` | card-specific World-account footnote | S6, S8 | 2026-08-31 | `issuerConfirmed` |
| `mbna-smart-cash-world` | `countryResidency` | `equals` | `Canada` | — | `all:core` | issuer-general MBNA account applicant requirement; explicit scope includes MBNA credit-card accounts | S7, S8 | 2026-08-31 | `issuerConfirmed` |
| `mbna-smart-cash-world` | `age` | `atLeast` | `age of majority in province or territory of residence` | — | `all:core` | issuer-general MBNA account applicant requirement; explicit scope includes MBNA credit-card accounts | S7, S8 | 2026-08-31 | `issuerConfirmed` |
| `mbna-smart-cash-world` | `additionalQualificationCriteria` | `unspecified` | `issuer states additional criteria apply in application` | — | `all:core` | card-specific footnote, value not publicly enumerated | S6 | 2026-08-31 | `issuerConfirmed finding; requirement value unknown` |
| `home-trust-preferred-visa` | `individualAnnualIncome` | `atLeast` | `15000` | CAD | `all:core / any:financial` (only published option) | live card application declaration | S10 | 2026-08-31 | `issuerConfirmed` |
| `home-trust-preferred-visa` | `residencyStatusLiteral` | `equals` | `"permanent Canadian resident"` | — | `all:core` | live card application declaration | S10 | 2026-08-31 | `issuerConfirmed`; preserve literal semantics |
| `home-trust-preferred-visa` | `provinceResidency` | `notEquals` | `Quebec` | — | `all:core` | product page + live card application | S9, S10 | 2026-08-31 | `issuerConfirmed` |
| `home-trust-preferred-visa` | `age` | `atLeast` | `age of majority in province` | — | `all:core` | product page + live card application | S9, S10 | 2026-08-31 | `issuerConfirmed` |
| `home-trust-preferred-visa` | `bankruptcyDischargeAge` | `atLeast` | `2 years since discharge` | — | `all:core` | live card application declaration | S10 | 2026-08-31 | `issuerConfirmed` |
| `home-trust-preferred-visa` | `currentBankruptcyStatus` | `notEquals` | `currently in bankruptcy` | — | `all:core` | product-page FAQ | S9 | 2026-08-31 | `issuerConfirmed; weaker/conflicts with application gate` |
| `home-trust-preferred-visa` | `thirdPartyAccountOpening` | `equals` | `false` | — | `all:core` | live card application declaration | S10 | 2026-08-31 | `issuerConfirmed` |
| `home-trust-preferred-visa` | `creditCheckConsent` | `equals` | `true` | — | `all:application-procedure` | live card application declaration | S10 | 2026-08-31 | `issuerConfirmed` |
| `rbc-cashback-preferred-we` | `individualAnnualIncome` | `atLeast` | `80000` | CAD | `any:financial` | card-specific product page | S11 | 2026-08-31 | `issuerConfirmed` |
| `rbc-cashback-preferred-we` | `householdAnnualIncome` | `atLeast` | `150000` | CAD | `any:financial` | card-specific product page | S11 | 2026-08-31 | `issuerConfirmed` |

### Operator notes

- `atLeast 50000` and `greaterThan 50000` are intentionally different values in the normalized model.
- “Minimum” is normalized to `atLeast` unless the issuer uses stricter language.
- MBNA explicitly uses “greater than” for personal income and “$80,000 or greater” for household income.
- Home Trust's bankruptcy application declaration is a duration-from-discharge requirement, not merely a boolean `bankruptcy == false`.
- `residencyStatusLiteral: "permanent Canadian resident"` intentionally preserves Home Trust's exact concept. Do **not** silently reinterpret it as the Canadian immigration class `PermanentResident` without a more explicit issuer statement.

## 3. Card-by-card prerequisites, application inputs, and ambiguities

### `simplii-cashback-visa`

**Financial qualification.** Simplii publishes one threshold: minimum **household** annual income of CAD 15,000. The reviewed card page and FAQ do not publish a separate personal/individual-income route, AUM route, or declared annual card-spending route.

**Deterministic non-financial prerequisites.** The card-specific FAQ states that the applicant lives in Canada and is either a Canadian citizen or permanent resident, excluding Quebec; has reached age of majority in their province/territory; and has not declared bankruptcy in the last seven years. A separate FAQ answer explicitly states that the Cash Back Visa is not available in Quebec.

**Application inputs / discretion.** The public card FAQ says Simplii may contact an applicant if more information is needed, but the reviewed public card-specific surface does not enumerate a complete set of employment/bank inputs or a numeric credit-adjudication rule. Do not infer one.

**Ambiguity.** The phrase “Canadian citizen or permanent resident” is an OR alternative nested inside the other conjunctive requirements. The household-income rule is not evidence of a personal-income alternative.

### `amex-simplycash-preferred`

**Financial qualification.** **No issuer-published income minimum found.** The card-specific Eligibility section lists Canadian residency, Canadian credit file, and age of majority, but no numeric personal or household income threshold. Targeted first-party searches also found no AUM or declared annual-spending alternative for this card.

**Credit score.** **No issuer-published exact credit-score minimum found.** The requirement is a **Canadian credit file**, not a published score cutoff.

**Deterministic non-financial prerequisites.** Canadian resident **and** Canadian credit file; age of majority in the province or territory where the applicant lives.

**Application inputs / discretion.** Amex's Canadian application guidance says applicants are asked to provide employment, income, and bank account information. That is input collection, not a qualifying minimum. The card remains subject to approval; no deterministic approval score was published on the reviewed sources.

**Province treatment.** No province/territory exclusion was found for the card. The product page contains Quebec-specific fee treatment, which is positive evidence that Quebec applicants are contemplated, but fee treatment is not itself an eligibility requirement.

### `bmo-cashback-world-elite`

**Financial qualification.** Minimum CAD 80,000 individual annual income **OR** CAD 150,000 household annual income. Both normalize to `atLeast`.

**Deterministic non-financial prerequisites.** BMO's eligibility FAQ on the card page says an applicant must be a Canadian citizen or permanent resident, must not have declared bankruptcy in the past seven years, and must have reached age of majority in the province in which they live. BMO gives the age breakdown as 18 in Alberta, Manitoba, Ontario, Prince Edward Island, Quebec, and Saskatchewan, and 19 in all other provinces.

**Application inputs, not thresholds.** The same page says an online applicant will need to provide name, date of birth, contact information, SIN, address, employment status, income source(s), and rent/mortgage amount. PickMe must not convert those fields into qualifying rules unless BMO publishes an actual threshold for them.

**No alternative financial route found.** No candidate-specific AUM or declared-spending route was found. The annual-fee rebate tied to BMO Premium Chequing is a fee benefit, not an application-eligibility path.

### `mbna-smart-cash-world`

**Financial qualification.** The issuer's card footnote is unusually precise: personal annual income must be **greater than CAD 50,000**, **OR** household annual income must be **CAD 80,000 or greater**. The MBNA comparison page corroborates the same semantics.

**Deterministic non-financial prerequisites.** MBNA's “Applying for an account” page states that applicants must be Canadian residents and have reached age of majority in their province/territory of residence. This is issuer-general, but its stated scope is MBNA credit-card account applicants, so it legitimately covers this card.

**Explicit unknown.** The Smart Cash World footnote adds: “Additional account qualification criteria apply as set out in the application.” The reviewed public issuer pages do not enumerate those additional criteria. This makes the card **partial**, not complete, even though the income/residency/age rules are verified.

**Application inputs / discretion.** MBNA says Credit Specialists review applications on a personal basis and make a credit decision. No exact credit-score minimum, bankruptcy lookback, AUM route, or annual card-spend route was found for this candidate.

### `home-trust-preferred-visa`

**Financial qualification.** The product FAQ and live application both publish annual applicant income of **at least CAD 15,000**. No household-income alternative, AUM route, or declared annual card-spending route was found.

**Deterministic non-financial prerequisites from the live application.** The applicant must affirm that they are a “permanent Canadian resident,” are not a Quebec resident, are age of majority in their province, have been discharged from bankruptcy for at least two years, are not opening the account on behalf of a third party, and consent to Home Trust obtaining a Consumer Report / credit check.

**Important official-source conflict.** The marketing/product FAQ says only that the applicant “cannot currently be in bankruptcy.” The live application is stricter: discharged from bankruptcy for **at least two years**. For an eligibility engine, use the application declaration as the operative deterministic rule and retain the product-page wording as a conflicting/less-specific source. Do not collapse the two into a single vague `notBankrupt` boolean.

**Residency semantics caution.** Home Trust's wording is “permanent Canadian resident.” That wording is not precise enough to safely map to the federal immigration class `PermanentResident`. Preserve the literal issuer concept or add a dedicated normalized type until Home Trust explicitly defines it.

**Application inputs / discretion.** The application authorizes Home Trust to collect credit, identity, and financially related information from credit bureaus, financial institutions, telecommunications providers, and references and to use that information to understand eligibility. The application also states that issuance is on approved credit. None of that creates a numeric credit-score minimum.

### `rbc-cashback-preferred-we`

**Financial qualification.** RBC currently states a minimum personal income of CAD 80,000 **OR** minimum household income of CAD 150,000. Both normalize to `atLeast`. This verifies the existing PickMe catalogue annotation.

**No candidate-specific alternative financial route found.** No AUM or declared annual card-spending alternative was found for this specific personal card. Do not import qualification routes from other RBC World Elite products. For example, RBC currently publishes business revenue, annual eligible-spend, and AUM alternatives for a *different* WestJet RBC World Elite Mastercard for Business; that source is intentionally out of scope for this candidate and demonstrates why product scope matters.

**Primary-applicant non-financial prerequisites remain incomplete.** The card product page does not publish a card-specific primary-applicant residency, age, bankruptcy, citizenship/permanent-residency, or local-credit-file rule. RBC's issuer-general application article discusses what *most* applicants need and explicitly describes exceptions for newcomers, temporary foreign workers, and international students, so those general statements must not be converted into deterministic card-specific gates.

**Wrong-scope official evidence.** RBC publishes a card-specific **co-applicant** request form. That form requires the co-applicant to be a Canadian resident and age of majority and says the request is subject to credit approval. Those are co-applicant rules, not evidence of the primary-applicant gate. The PDF text layer reviewed on 2026-08-31 identifies an August 17, 2026 information date, while a rendered page/footer still exposes older 11/2025 markings; this makes the form especially unsuitable as a source for primary-applicant normalization.

**Application inputs / discretion.** RBC issuer-general guidance says applications commonly collect identity, address/housing, employment, income, and sometimes proof of income; SIN may be requested but is not mandatory in that guidance. RBC also states that approval depends on assessment of credit score, income, debt, and the applicant's overall financial profile. These are discretionary/adjudication inputs, not candidate-specific thresholds.

## 4. “No published requirement found” findings

Absence here means no qualifying rule was found on the reviewed first-party card/application/legal surfaces as of 2026-08-31. It does **not** mean the issuer promises the factor is irrelevant to credit adjudication.

| finding | cards |
|---|---|
| Exact numeric credit-score minimum | **All six** — none found. |
| AUM alternative to qualify | **All six** — none found for these specific candidates. |
| Declared annual card-spending alternative to qualify | **All six** — none found for these specific candidates. |
| Personal/individual-income alternative | `simplii-cashback-visa` — none found; issuer publishes household CAD 15,000 only. |
| Any published income minimum | `amex-simplycash-preferred` — **no issuer-published minimum found**. |
| Household-income alternative | `home-trust-preferred-visa` — none found; issuer publishes applicant annual income CAD 15,000. |
| Bankruptcy restriction/lookback | No card-applicable published rule found for `amex-simplycash-preferred`, `mbna-smart-cash-world`, or the primary applicant of `rbc-cashback-preferred-we`. |
| Card-specific primary-applicant country residency / age | `rbc-cashback-preferred-we` — not found. Issuer-general and co-applicant sources exist but are wrong scope for a deterministic primary rule. |
| Business-applicant requirement | None of the six candidates; they are personal-card candidates. |

### Explicit Amex finding

For `amex-simplycash-preferred`, the correct future-contract state is **`noIssuerPublishedMinimumFound`**, not `{ amount: 0 }`, not `null` meaning “not researched,” and not an inferred credit-score band. Amex does publish a Canadian-credit-file requirement, but no exact numeric credit-score cutoff was found.

## 5. Proposed normalized JSON records for a future `application-requirements.json`

The existing sample shape is sufficient for simple income ORs, but the real data needs a few extensions:

- `publicationStatus` to distinguish a published threshold, an explicitly researched “no published minimum found” result, and an unknown/unresearched field.
- Nested logical groups (`all` containing `any`) for citizenship/permanent-resident alternatives.
- `scope` on requirements/sources so a co-applicant or issuer-general rule cannot silently become a primary-applicant rule.
- Duration/event semantics for bankruptcy rules (`noneWithin 7 years` vs `dischargedFor atLeast 2 years`).
- A literal-preservation path for ambiguous issuer language such as Home Trust's “permanent Canadian resident.”
- `conflicts` for official-source disagreement.
- `discretionaryCriteria` separate from deterministic requirements.
- `applicationInputs` separate from thresholds.

```json
[
  {
    "cardId": "simplii-cashback-visa",
    "financialRequirements": {
      "publicationStatus": "published",
      "semantics": "any",
      "options": [
        {
          "type": "householdAnnualIncome",
          "operator": "atLeast",
          "amount": { "amount": 15000, "currency": "CAD" }
        }
      ]
    },
    "nonFinancialRequirements": {
      "semantics": "all",
      "requirements": [
        { "type": "countryResidency", "operator": "equals", "value": "CA" },
        {
          "type": "logicalGroup",
          "semantics": "any",
          "requirements": [
            { "type": "citizenshipStatus", "operator": "equals", "value": "CanadianCitizen" },
            { "type": "immigrationStatus", "operator": "equals", "value": "PermanentResident" }
          ]
        },
        { "type": "provinceResidency", "operator": "notEquals", "value": "QC" },
        { "type": "age", "operator": "atLeastJurisdictionAgeOfMajority" },
        { "type": "bankruptcyDeclarationLookback", "operator": "noneWithin", "duration": { "years": 7 } }
      ]
    },
    "applicationInputs": [],
    "discretionaryCriteria": [],
    "sourceIds": ["S1", "S2"]
  },
  {
    "cardId": "amex-simplycash-preferred",
    "financialRequirements": {
      "publicationStatus": "noIssuerPublishedMinimumFound",
      "semantics": "unknown",
      "options": []
    },
    "nonFinancialRequirements": {
      "semantics": "all",
      "requirements": [
        { "type": "countryResidency", "operator": "equals", "value": "CA" },
        { "type": "localCreditFile", "operator": "exists", "value": "CanadianCreditFile" },
        { "type": "age", "operator": "atLeastJurisdictionAgeOfMajority" }
      ]
    },
    "applicationInputs": [
      { "type": "employmentInformation", "scope": "issuerGeneral" },
      { "type": "incomeInformation", "scope": "issuerGeneral", "qualifyingThreshold": null },
      { "type": "bankAccountInformation", "scope": "issuerGeneral" }
    ],
    "discretionaryCriteria": [
      { "type": "creditApproval", "operator": "issuerDiscretion" }
    ],
    "sourceIds": ["S3", "S4"]
  },
  {
    "cardId": "bmo-cashback-world-elite",
    "financialRequirements": {
      "publicationStatus": "published",
      "semantics": "any",
      "options": [
        {
          "type": "individualAnnualIncome",
          "operator": "atLeast",
          "amount": { "amount": 80000, "currency": "CAD" }
        },
        {
          "type": "householdAnnualIncome",
          "operator": "atLeast",
          "amount": { "amount": 150000, "currency": "CAD" }
        }
      ]
    },
    "nonFinancialRequirements": {
      "semantics": "all",
      "requirements": [
        {
          "type": "logicalGroup",
          "semantics": "any",
          "requirements": [
            { "type": "citizenshipStatus", "operator": "equals", "value": "CanadianCitizen" },
            { "type": "immigrationStatus", "operator": "equals", "value": "PermanentResident" }
          ]
        },
        { "type": "bankruptcyDeclarationLookback", "operator": "noneWithin", "duration": { "years": 7 } },
        { "type": "age", "operator": "atLeastJurisdictionAgeOfMajority" }
      ]
    },
    "applicationInputs": [
      { "type": "name" },
      { "type": "dateOfBirth" },
      { "type": "contactInformation" },
      { "type": "socialInsuranceNumber" },
      { "type": "address" },
      { "type": "employmentStatus" },
      { "type": "incomeSources", "qualifyingThreshold": null },
      { "type": "housingPayment", "qualifyingThreshold": null }
    ],
    "discretionaryCriteria": [
      { "type": "creditApproval", "operator": "issuerDiscretion" }
    ],
    "sourceIds": ["S5"]
  },
  {
    "cardId": "mbna-smart-cash-world",
    "financialRequirements": {
      "publicationStatus": "published",
      "semantics": "any",
      "options": [
        {
          "type": "individualAnnualIncome",
          "operator": "greaterThan",
          "amount": { "amount": 50000, "currency": "CAD" }
        },
        {
          "type": "householdAnnualIncome",
          "operator": "atLeast",
          "amount": { "amount": 80000, "currency": "CAD" }
        }
      ]
    },
    "nonFinancialRequirements": {
      "semantics": "all",
      "requirements": [
        { "type": "countryResidency", "operator": "equals", "value": "CA", "scope": "allMBNACreditCardAccounts" },
        { "type": "age", "operator": "atLeastJurisdictionAgeOfMajority", "scope": "allMBNACreditCardAccounts" }
      ]
    },
    "applicationInputs": [],
    "discretionaryCriteria": [
      {
        "type": "additionalAccountQualificationCriteria",
        "status": "issuerSaysPresentButNotEnumerated"
      },
      { "type": "creditApproval", "operator": "issuerDiscretion" }
    ],
    "sourceIds": ["S6", "S7", "S8"]
  },
  {
    "cardId": "home-trust-preferred-visa",
    "financialRequirements": {
      "publicationStatus": "published",
      "semantics": "any",
      "options": [
        {
          "type": "individualAnnualIncome",
          "operator": "atLeast",
          "amount": { "amount": 15000, "currency": "CAD" }
        }
      ]
    },
    "nonFinancialRequirements": {
      "semantics": "all",
      "requirements": [
        {
          "type": "residencyStatusLiteral",
          "operator": "equals",
          "value": "permanent Canadian resident",
          "normalizationStatus": "preserveIssuerLiteral"
        },
        { "type": "provinceResidency", "operator": "notEquals", "value": "QC" },
        { "type": "age", "operator": "atLeastJurisdictionAgeOfMajority" },
        { "type": "bankruptcyDischargeAge", "operator": "atLeast", "duration": { "years": 2 } },
        { "type": "thirdPartyAccountOpening", "operator": "equals", "value": false },
        { "type": "creditCheckConsent", "operator": "equals", "value": true }
      ]
    },
    "applicationInputs": [
      { "type": "personalInformation" },
      { "type": "identityVerificationInformation" },
      { "type": "creditIdentityFinancialInformation", "qualifyingThreshold": null }
    ],
    "discretionaryCriteria": [
      { "type": "creditApproval", "operator": "issuerDiscretion" }
    ],
    "conflicts": [
      {
        "field": "bankruptcy",
        "preferredSourceId": "S10",
        "otherSourceId": "S9",
        "reason": "live application requires at least two years since discharge; product FAQ only says applicant cannot currently be in bankruptcy"
      }
    ],
    "sourceIds": ["S9", "S10"]
  },
  {
    "cardId": "rbc-cashback-preferred-we",
    "financialRequirements": {
      "publicationStatus": "published",
      "semantics": "any",
      "options": [
        {
          "type": "individualAnnualIncome",
          "operator": "atLeast",
          "amount": { "amount": 80000, "currency": "CAD" }
        },
        {
          "type": "householdAnnualIncome",
          "operator": "atLeast",
          "amount": { "amount": 150000, "currency": "CAD" }
        }
      ]
    },
    "nonFinancialRequirements": {
      "publicationStatus": "noCardSpecificPrimaryApplicantSetFound",
      "semantics": "unknown",
      "requirements": []
    },
    "applicationInputs": [
      { "type": "identityInformation", "scope": "issuerGeneral" },
      { "type": "addressAndHousingInformation", "scope": "issuerGeneral" },
      { "type": "employmentInformation", "scope": "issuerGeneral" },
      { "type": "incomeInformation", "scope": "issuerGeneral", "qualifyingThreshold": null },
      { "type": "proofOfIncome", "scope": "issuerGeneral", "when": "ifRequested" },
      { "type": "socialInsuranceNumber", "scope": "issuerGeneral", "required": false }
    ],
    "discretionaryCriteria": [
      { "type": "creditProfileAssessment", "operator": "issuerDiscretion", "scope": "issuerGeneral" }
    ],
    "sourceIds": ["S11", "S12", "S13"]
  }
]
```

## 6. Implementation cautions

1. **Use three-valued eligibility, not boolean-only logic.** A candidate can be `qualified`, `disqualified`, or `unknown`. Unknown is necessary when the issuer has unpublished criteria or PickMe lacks a user datum.
2. **Never convert “no published minimum found” to zero.** For Amex, `0` would falsely claim the issuer affirmatively has no minimum. Preserve a publication/evidence state.
3. **Preserve exact operators.** MBNA at exactly CAD 50,000 personal income is not a match through the personal route; household exactly CAD 80,000 is a match.
4. **Evaluate OR paths with unknown-aware logic.** If individual income fails but household income is unknown, the overall financial result is `unknown`, not `disqualified`. If either known route passes, the financial group passes.
5. **Do not mix application inputs with eligibility.** Employment status, income source, rent/mortgage, bank information, SIN, and proof documents are not thresholds unless the issuer publishes a qualifying predicate.
6. **Keep source scope machine-readable.** `issuerGeneral`, `cardSpecific`, `primaryApplicant`, `coApplicant`, `welcomeOffer`, and similar scopes prevent wrong-scope facts from leaking into the eligibility engine.
7. **Do not import network-wide World/World Elite assumptions.** The issuer must publish the route for the specific card or an explicitly encompassing issuer rule. RBC's different business World Elite card illustrates this risk: it publishes AUM/spend routes that the reviewed personal RBC candidate page does not.
8. **Model bankruptcy as event/time semantics.** Simplii/BMO are “no declaration within 7 years”; Home Trust is “discharged for at least 2 years.” These are not interchangeable.
9. **Prefer an operative application declaration over a weaker marketing summary when both are current and conflict.** Record both sources and the conflict; do not silently discard provenance.
10. **Keep Home Trust's residency phrase literal until clarified.** “Permanent Canadian resident” should not be automatically equated with the federal `PermanentResident` immigration class.
11. **For “High-value close matches,” expose the failed/unknown gate.** Example: “Income route is CAD 80k personal or CAD 150k household; household income not provided.” Never present a close match as likely approval.
12. **Treat partial cards differently from known failures.** MBNA has explicit unspecified additional criteria; RBC lacks a public card-specific primary non-financial set. A user satisfying the income route is not therefore confirmed eligible.
13. **Version eligibility evidence independently from reward contracts.** Eligibility can change without earn-rate changes. Store `verifiedAt`, source URL, source scope, and ideally `effectiveFrom` when published.
14. **Reverify dynamic application pages before release.** Home Trust's live application disclosure itself says pricing/terms are subject to change, and application flows can change faster than marketing pages.
15. **Do not use welcome-offer eligibility as application eligibility.** No welcome-offer spend or prior-card restriction was promoted into these requirements.

## 7. Exact official sources

All sources below were checked on **2026-08-31**. Only issuer-controlled pages/documents are used for verification.

### S1 — Simplii card page

- **Issuer:** Simplii Financial / CIBC
- **Title:** `Simplii Financial Cash Back Visa Card | Simplii Financial`
- **URL:** https://www.simplii.com/en/credit-cards/cash-back-visa.html
- **Relevant location:** `Top credit card FAQ` → `How do I qualify for the Simplii Financial Cash Back Visa Card?`
- **Scope:** card-specific
- **D3:** issuerConfirmed
- **Used for:** CAD 15,000 minimum household income; Canada + citizen/permanent-resident wording; Quebec exclusion.

### S2 — Simplii FAQ

- **Issuer:** Simplii Financial / CIBC
- **Title:** `Frequently Asked Questions | Simplii Financial`
- **URL:** https://www.simplii.com/en/faq.html
- **Relevant location:** `Credit card` → `How do I qualify for the Simplii Financial Cash Back Visa Card?`; `Can I apply ... if I live in Quebec?`
- **Scope:** card-specific
- **D3:** issuerConfirmed
- **Used for:** household income; Canada; citizen/permanent resident; Quebec; age of majority; no bankruptcy declaration in last 7 years.

### S3 — Amex SimplyCash Preferred product page

- **Issuer:** Amex Bank of Canada
- **Title:** `SimplyCash® Preferred Card from American Express | Amex CA`
- **URL:** https://www.americanexpress.com/en-ca/credit-cards/simply-cash-preferred/
- **Relevant location:** `Eligibility`
- **Scope:** card-specific
- **D3:** issuerConfirmed
- **Used for:** Canadian resident + Canadian credit file; age of majority; absence of a published card-specific numeric income threshold on the eligibility section.

### S4 — Amex Canadian application guidance

- **Issuer:** Amex Bank of Canada
- **Title:** `How To Apply For A Credit Card | Amex CA`
- **URL:** https://www.americanexpress.com/ca/en/credit-know-how/credit-card-application/
- **Relevant location:** `Applying for an American Express Card` → `Who can apply for a Credit Card?`
- **Scope:** issuer-general Canadian Amex credit-card applications
- **D3:** issuerConfirmed for issuer-general inputs/standard criteria; not a card-specific numeric threshold
- **Used for:** employment, income, and bank account information are requested; standard residency/credit-file/age criteria.

### S5 — BMO CashBack World Elite product page

- **Issuer:** Bank of Montreal
- **Title:** `Apply for a BMO CashBack World Elite Mastercard`
- **URL:** https://www.bmo.com/en-ca/main/personal/credit-cards/bmo-cashback-world-elite-mastercard/
- **Relevant locations:** top product summary; `How do I know if I’m eligible for a BMO credit card?`; `What information do I need to provide to apply for my card?`
- **Scope:** income is card-specific; eligibility FAQ explicitly scopes itself to BMO credit-card applicants and is embedded on the card page
- **D3:** issuerConfirmed
- **Used for:** CAD 80,000 individual / CAD 150,000 household; citizen-or-permanent-resident; 7-year bankruptcy lookback; age; application inputs.

### S6 — MBNA Smart Cash World product page

- **Issuer:** MBNA / TD Bank Group
- **Title:** `MBNA Smart Cash World Mastercard® | MBNA Canada`
- **URL:** https://www.mbna.ca/en/credit-cards/cash-back/smart-cash-world-mastercard
- **Relevant location:** World-account legal footnote (`††††`)
- **Scope:** card-specific World account
- **D3:** issuerConfirmed
- **Used for:** personal `> CAD 50,000` OR household `>= CAD 80,000`; explicit statement that additional account qualification criteria apply in the application.

### S7 — MBNA applying-for-account help

- **Issuer:** MBNA / TD Bank Group
- **Title:** `Applying for an account`
- **URL:** https://www.mbna.ca/en/help-centre/credit-cards/applying-for-an-account
- **Relevant locations:** `Who can apply?`; `How long does it take to get a decision on my application?`
- **Scope:** issuer-general MBNA credit-card account applications
- **D3:** issuerConfirmed for its explicit account-wide scope
- **Used for:** Canadian residency; age of majority; individualized credit-decision language.

### S8 — MBNA compare-cards page

- **Issuer:** MBNA / TD Bank Group
- **Title:** `Compare MBNA Credit Cards | MBNA Canada`
- **URL:** https://www.mbna.ca/en/credit-cards/compare-cards
- **Relevant location:** eligibility row for Smart Cash World
- **Scope:** card-specific comparison row
- **D3:** issuerConfirmed
- **Used for:** corroboration of Canadian resident / age and the exact `> 50,000` vs `>= 80,000` income semantics.

### S9 — Home Trust Preferred Visa product page

- **Issuer:** Home Trust Company
- **Title:** `Home Trust Preferred Visa: No Foreign Transaction Fee Credit Card`
- **URL:** https://www.hometrust.ca/credit-cards/preferred-visa-card/
- **Relevant location:** `How to apply` → `What are the requirements to apply for a Home Trust Preferred Visa credit card?`
- **Scope:** card-specific
- **D3:** issuerConfirmed
- **Used for:** “permanent Canadian resident”; age of majority; current-bankruptcy wording; CAD 15,000 annual income; Quebec exclusion.

### S10 — Home Trust live application disclosures

- **Issuer:** Home Trust Company
- **Title:** `Home Trust Preferred Visa disclosures` (application page title renders as `Welcome`)
- **URL:** https://visa.hometrust.ca/
- **Relevant locations:** `Declarations`; `Authorization for Use of Personal Information`; `Authorization for account creation`
- **Scope:** card-specific live application
- **D3:** issuerConfirmed; preferred over the weaker marketing summary where the bankruptcy wording conflicts
- **Used for:** “permanent Canadian resident”; not Quebec; annual income `>= CAD 15,000`; age of majority; discharged from bankruptcy for at least 2 years; no third-party account opening; consumer-report/credit-check consent; discretionary credit/identity/financial assessment language.

### S11 — RBC Cash Back Preferred World Elite product page

- **Issuer:** Royal Bank of Canada
- **Title:** `RBC Cash Back Preferred World Elite Mastercard | RBC Royal Bank of Canada`
- **URL:** https://www.rbcroyalbank.com/credit-cards/cash-back/rbc-preferred-world-elite-mastercard.html
- **Relevant location:** product pricing/qualification summary above `Apply Now`
- **Scope:** card-specific
- **D3:** issuerConfirmed
- **Used for:** minimum personal CAD 80,000 OR minimum household CAD 150,000.

### S12 — RBC application guidance

- **Issuer:** Royal Bank of Canada
- **Title:** `How to Apply for a Credit Card in Canada: A Complete Guide | RBC Royal Bank of Canada`
- **URL:** https://www.rbcroyalbank.com/credit-cards/product-advice/how-to-apply-for-a-credit-card.html
- **Relevant locations:** `Core eligibility requirements`; `Credit card application checklist`; `What to expect on the application form`; FAQ
- **Scope:** issuer-general guidance, explicitly framed around “most” applicants and containing exceptions
- **D3:** issuerConfirmed as general guidance only; **does not clear D3 for a card-specific primary-applicant deterministic rule**
- **Used for:** application inputs and discretionary credit-assessment context; evidence that generic RBC requirements must not be promoted to this card without scope.

### S13 — RBC card-specific co-applicant form

- **Issuer:** Royal Bank of Canada
- **Title:** `Co-Applicant Request Form — RBC® Cash Back Preferred World Elite Mastercard`
- **URL:** https://www.rbcroyalbank.com/credit-cards/cash-back/rbc-cash-back-preferred-world-elite-mastercard/rbc-cash-back-preferred-world-elite-mastercard-co-application.pdf
- **Relevant location:** `IMPORTANT – PRIMARY CARDHOLDER AND CO-APPLICANT`; co-applicant qualification paragraph; privacy section
- **Scope:** **co-applicant only**, not initial primary applicant
- **D3:** issuerConfirmed for co-applicant scope; **does not clear D3 for primary-applicant requirements**
- **Used for:** scope-control/ambiguity only. The form says a co-applicant must be a resident of Canada and age of majority and is subject to credit approval.

### Scope-control source intentionally not used as a candidate requirement

RBC also publishes a different product, the **WestJet RBC World Elite Mastercard for Business**, with multiple eligibility alternatives including business revenue, eligible annual card spend, and assets under management. That is not this candidate and none of those routes were copied into `rbc-cashback-preferred-we`:

- https://www.rbcroyalbank.com/business/credit-cards/small-business-credit-cards/westjet-rbc-world-elite-mastercard-business.html

This is a useful negative control: product-specific issuer evidence exists when RBC intends to publish those alternatives.

## Existing PickMe catalogue annotation audit

- `rbc-cashback-preferred-we`: existing `_eligibilityNote` — “Issuer states $80,000 personal or $150,000 household minimum annual income.” **Accurate, but incomplete as an application-requirements model.** Both operators are `atLeast`; no candidate-specific AUM/spend alternative was found; primary non-financial prerequisites remain unpublished/unknown at card-specific scope.
- `home-trust-preferred-visa`: existing `_eligibilityNote` — “Not available in Quebec.” **Accurate but materially incomplete.** It omits CAD 15,000 annual income, “permanent Canadian resident,” age of majority, the live application's two-year bankruptcy-discharge rule, no-third-party-opening declaration, and credit-check consent.
- `simplii-cashback-visa`, `amex-simplycash-preferred`, `bmo-cashback-world-elite`, `mbna-smart-cash-world`: no `_eligibilityNote` was present in the inspected catalogue state, so the application prerequisites researched here are currently unrepresented in that annotation mechanism.

## Research completion state

- **Complete issuer-published deterministic set located:** `simplii-cashback-visa`, `amex-simplycash-preferred`, `bmo-cashback-world-elite`, `home-trust-preferred-visa` (Home Trust carries an explicit source conflict resolved in favor of the live application for gating).
- **Partial:** `mbna-smart-cash-world` because MBNA explicitly says additional application qualification criteria exist but does not enumerate them publicly in the reviewed sources; `rbc-cashback-preferred-we` because only the card-specific financial threshold was found for the primary applicant and generic/co-applicant rules are wrong scope.
- **Completely unknown:** none.

No contract, engine, synchronized resource, release file, or application UI change is part of this research document.
