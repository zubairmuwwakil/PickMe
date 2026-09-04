# Merchant MCC provider evaluation — exact/network MCC acquisition

**Date:** 2026-09-04  
**Status:** research complete for first provider decision; re-verify vendor terms before implementation  
**Owner:** PickMe merchant/MCC architecture  
**Related architecture:** `docs/superpowers/specs/2026-09-04-merchant-mcc-production-architecture-design.md`

## Question

What is the highest-ROI way to add more **literal or network-supplied MCC evidence** to PickMe without making the app dependent on continuous bank linking?

The important distinction is exact evidence vs categorization:

- A provider returning a literal `merchant_category_code`/`mccCode` can feed the MCC graph as provider evidence.
- A provider returning only “grocery”, “food”, “retail”, SIC, NAICS, or its own category taxonomy **must not** be promoted to a literal MCC.

The current graph already knows how to combine weaker and stronger evidence. The provider decision is therefore about acquiring better evidence, not replacing the recommendation engine.

## Recommendation

### First POC: Mastercard Places

Mastercard Places is the strongest first proof-of-concept found in this review.

Why it fits PickMe unusually well:

1. It is a **merchant-location database**, not an account-aggregation product.
2. Mastercard’s official Places API model includes location identity, latitude/longitude, merchant hierarchy, and `mccCode`.
3. PickMe already resolves a high-confidence nearby merchant using MapKit/GPS, so the new provider can plug into an existing location-resolution seam instead of requiring a new user workflow.
4. It requires no bank credentials, transaction history, purchase amount, card linking, or persistent user identity for a location lookup.
5. Its MCC should naturally be treated as **Mastercard-network external location evidence**, which matches the dimensions already supported by `MerchantMCCGraph`.

This is a POC recommendation, **not yet a production-provider decision**. Production data access, Canada coverage, rate/pricing, data-use/storage terms, and empirical accuracy must pass the gates in `docs/superpowers/plans/2026-09-04-mastercard-places-mcc-poc.md`.

## Ranked candidates

| Rank | Provider/path | Exact MCC? | Account linking? | Best role | Decision |
|---|---|---:|---:|---|---|
| 1 | Mastercard Places | Yes: API model exposes `mccCode` | No | Location/network MCC evidence | **POC first** |
| 2 | Plaid Transactions | Yes, nullable/beta | Yes | Owner transaction evidence for supported institutions | Optional later provider |
| 3 | MX Transactions | Yes, nullable | Yes | Owner transaction evidence / fallback aggregator | Evaluate if Plaid coverage is insufficient |
| 4 | Mastercard Transaction Notifications | Yes, real-time notification payload | Card enrollment/consent; heavier security surface | Future real-time Mastercard purchase feed | Strategic later, not current POC |
| 5 | Visa Merchant Search | Merchant enrichment / network merchant data | No bank link, but commercial access | Potential runtime lookup | **Do not use for persistent graph under public terms** without explicit contractual permission |
| 6 | OFX/QFX standard export | No verified MCC field; standard defines SIC | File import | Statement/transaction import for other evidence | Reject as generic exact-MCC source |
| 7 | Flinks Enrich/categorization | No public literal-MCC field verified | Usually financial-data connection | Merchant normalization/category enrichment | Not useful for exact MCC objective today |

## 1. Mastercard Places

### Verified capabilities

Mastercard Developers describes Places as access to Mastercard’s global database of merchant locations. Mastercard’s product page describes it as a global view of Mastercard-accepting merchant locations online and offline.

The official Mastercard `places-client-tutorial` OpenAPI specification defines:

- production and sandbox Places endpoints;
- merchant category-code resources;
- place/location resources;
- a `PlaceInfo` model that includes merchant/location fields and `mccCode`;
- location filtering including latitude/longitude and merchant identifiers.

This is materially different from a generic POI category. The provider is exposing Mastercard merchant-location data with an MCC field.

### Trust classification for PickMe

Do **not** treat a Places result as universal terminal truth.

Initial proposed evidence mapping:

```text
kind: externalLocationReport
network: mastercard
merchantKey: PickMe canonical merchant ID
place/location: resolved physical store
mcc: Mastercard Places mccCode
sourceConfidence: provider-specific calibrated value
sourceReference: provider/version-safe reference, if contract permits
```

A direct owner-observed literal MCC at that purchase remains stronger.

### Why this is ahead of Plaid

Plaid can return literal MCCs, but only after linking financial institutions and only where its beta MCC field is populated. Places can potentially answer the **merchant/location** question directly, which is already the question PickMe asks before checkout.

That avoids:

- requiring bank consent during card recommendation;
- continuous transaction synchronization;
- institution-specific MCC fill-rate dependency;
- turning the MCC feature into an aggregation product.

### Open questions that block production

Before production use, verify with Mastercard/current contract:

- real Canadian merchant coverage and freshness;
- whether `mccCode` is location-specific and how network/acquirer variance should be interpreted;
- production pricing and quotas;
- allowed caching/retention of Places-derived fields;
- whether data may be combined with PickMe’s persistent MCC graph/community evidence;
- redistribution/display restrictions;
- required attribution;
- production onboarding requirements.

**Never copy Mastercard Places results into the shipped static 500-merchant seed until the applicable license explicitly allows that use.**

### Primary sources

- Mastercard Developers API catalogue — Places: https://developer.mastercard.com/apis
- Mastercard Places product page: https://www.mastercard.com/at/de/business/insights-intelligence/economic-market-insights/solutions/places.html
- Mastercard official Places client tutorial: https://github.com/Mastercard/places-client-tutorial
- Official tutorial OpenAPI specification: https://github.com/Mastercard/places-client-tutorial/blob/master/api/openapi.yaml
- Mastercard Places reference app: https://github.com/Mastercard/location-intelligence-places-reference-app
- Mastercard Developers terms: https://developer.mastercard.com/terms-of-use

## 2. Plaid Transactions

Plaid Transactions exposes `merchant_category_code`, documented as typically a four-digit ISO 18245 string. Plaid also explicitly says:

- the field is beta;
- it is populated primarily for card transactions;
- coverage varies by institution;
- values are subject to change.

Plaid Transactions supports credit accounts and Canadian institutions as part of its financial-data aggregation model.

### Good use

If PickMe later offers an **optional linked-account exact-MCC provider**, Plaid is a strong POC candidate because it can associate the MCC with the owner’s actual transaction rather than merely a merchant prior.

That should enter as provider/transaction evidence only when a literal MCC is actually present. Null or category-only rows must not create a guessed MCC.

### Why it is not first

- Requires account linking and ongoing consent/data synchronization.
- MCC field coverage is institution-dependent and beta.
- Adds a much larger privacy/onboarding/product dependency than a location-only provider.

### Primary sources

- Transactions API: https://plaid.com/docs/api/products/transactions/
- Transactions overview: https://plaid.com/docs/transactions/

## 3. MX Transactions

MX transaction models expose `merchant_category_code` as an integer and also have merchant/merchant-location identifiers. Official example responses show the field may be `null`, so the existence of the schema does not prove good Canadian fill rate.

MX is therefore worth a controlled comparison if Plaid’s Canadian issuer coverage or MCC fill rate is weak, but it should not be integrated simply because the field exists.

### Primary sources

- MX Transactions overview: https://docs.mx.com/api-reference/nexus/reference/transactions-overview
- MX Platform transaction example: https://docs.mx.com/api-reference/platform-api/reference/read-transaction-by-account

## 4. Mastercard Transaction Notifications

Mastercard also offers Transaction Notifications: consumers can consent to share real-time purchase alerts with a third-party app/service. This is strategically interesting because a notification payload can include a merchant category code and transaction context.

It is **not** the current high-ROI implementation path.

The public enrollment/consent examples imply a much heavier card-data/security/compliance surface than Places. PickMe’s current strategy deliberately avoids turning merchant learning into a card-credential ingestion system. Revisit only if Mastercard offers an onboarding/tokenization path whose PCI/security and user-friction economics are clearly acceptable.

### Primary source

- Mastercard Developers API catalogue — Transaction Notifications: https://developer.mastercard.com/apis

## 5. Visa Merchant Search

Visa Merchant Search can enrich transactions, search merchants from public merchant/location information, and locate nearby Visa-accepting merchants. It is relevant technically, but its current public product terms are a serious constraint for PickMe’s persistent learning graph.

The public terms restrict using Merchant Search information to the stated purposes and prohibit using it to compile/enhance databases or storing the information in lookup tables, except transaction-specific storage permitted by the terms.

That is directly in tension with a persistent crowdsourced merchant→MCC graph.

### Decision

Do **not** ingest Visa Merchant Search output into PickMe’s reusable MCC graph under the public terms. A future runtime-only use could be reconsidered after legal/product review, or if Visa grants explicit contractual rights for PickMe’s intended use.

### Primary sources

- Merchant Search overview: https://developer.visa.com/capabilities/merchant_search/overview
- Merchant Search docs: https://developer.visa.com/capabilities/merchant_search/docs
- Merchant Search product terms: https://developer.visa.com/capabilities/merchant_search/product-terms
- Merchant Search FAQ: https://developer.visa.com/capabilities/merchant_search/frequently-asked-questions

## 6. OFX/QFX statement import

A file-import path initially looked attractive because it could avoid account linking entirely.

The current FDX OFX Banking 2.3 specification supports the CreditCard message set, but the standard transaction structure provides `<SIC>` — **Standard Industrial Code** — rather than a verified Merchant Category Code field.

SIC/category information can still be useful as weaker classification evidence, but the generic OFX/QFX standard cannot be treated as an exact-MCC source.

Individual issuers may include proprietary extension fields. If a future real export from an issuer contains an explicit MCC, ingest that field based on the issuer-specific format/provenance, not by interpreting standard `<SIC>` as MCC.

### Primary sources

- FDX OFX Work Group/current specs: https://financialdataexchange.org/about-fdx/ofx-work-group/
- OFX Banking 2.3 PDF: https://financialdataexchange.org/common/Uploaded%20files/OFX%20files/OFX%20Banking%20Specification%20v2.3.pdf

## 7. Flinks

Flinks provides Canadian/US transaction categorization and merchant normalization. Those are useful capabilities, but the public documentation reviewed does not establish a literal MCC field suitable for PickMe’s exact-MCC evidence path.

Do not pay integration cost for this objective unless Flinks can contractually/documentedly provide literal MCCs with adequate Canadian coverage.

### Primary source

- Flinks categorization guide: https://docs.flinks.com/guides/enrich/categorization-guide

## High-ROI provider-call policy

Even if Mastercard Places or another provider passes the POC, **do not call it for every nearby merchant by default**.

The measurement work now in `CategoryResolutionMetricsStore` can identify the valuable population:

```text
MCC graph has meaningful uncertainty
        AND
plausible MCC branches produce different winning cards
        => external MCC lookup has direct decision ROI
```

If all plausible MCCs produce the same winning card, buying a more precise MCC answer does not improve the checkout decision.

This gives PickMe a scalable provider policy:

1. resolve locally first;
2. score plausible MCC branches locally;
3. call an external provider only when the winner is MCC-sensitive or another explicitly defined quality gate requires it;
4. cache only if provider terms permit;
5. keep local fallback for network/provider failure.

This lowers API spend, latency, privacy exposure, and vendor dependency simultaneously.

## Provider abstraction rule

Do not let vendor DTOs leak into recommendation logic.

Every accepted provider should normalize into the existing evidence boundary, conceptually:

```text
Provider response
    -> validated provider observation
    -> MerchantMCCEvidence
    -> MerchantMCCGraph
    -> Purchase Routes / checkout scoring
```

A future agent may replace Mastercard, Plaid, MX, or the backend without rewriting card semantics.

## What would change this ranking

Re-rank providers if any of these become true:

- Mastercard Places production terms forbid the required runtime/cache use;
- Canadian coverage or MCC accuracy is poor;
- Places pricing makes decision-sensitive calls uneconomic;
- a network/issuer/open-banking API supplies transaction MCC with lower friction;
- Apple exposes reliable MCC data directly to apps;
- Plaid/MX Canadian MCC fill rates become high enough that optional linking produces much stronger owner-specific truth at acceptable cost;
- Visa or another network provides explicit contractual permission for reusable merchant/MCC graph enrichment.

The ranking is a 2026-09-04 decision aid, not a permanent architectural constraint.
