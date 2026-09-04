# Free-production MCC sources — hard product constraint

**Date:** 2026-09-04  
**Status:** active constraint; strict CSV import + safe local purchase join shipped  
**Owner decision:** recurring production cost for merchant/MCC enrichment must be **$0** unless the owner explicitly revisits this decision.

## Decision

Do not add a paid merchant/MCC provider to PickMe merely because it improves coverage.

Mastercard Places, Plaid, MX, Visa commercial merchant products and similar services may be researched or tested, but they are not production dependencies unless a genuinely free production tier with acceptable rights/limits is verified or the owner explicitly changes the economics constraint.

The product should first improve the free learning flywheel already under PickMe's control.

## Research result

### Free MCC taxonomies are not the missing piece

Open MCC datasets can tell us that `5411` means grocery stores/supermarkets. They cannot reliably tell us that a particular Canadian merchant/location currently settles under `5411` on a given network.

Examples reviewed include `greggles/mcc-codes`, `Rebilly/merchant-category-codes`, and `pax2pay/merchant-category`. These remain useful for vocabulary/validation only.

### Public merchant lookup tools are research signals, not runtime feeds

AwardWallet's public merchant lookup can be useful for human corroboration, but no free production merchant-MCC API plus redistribution/cache right was verified. It therefore must not be scraped or treated as PickMe's runtime source without explicit permission.

### Commercial network/provider APIs do not satisfy the current cost rule

Technically attractive products such as Mastercard Places, Plaid, MX and Visa merchant/supplier products remain future options. No trustworthy source was verified that simultaneously provides:

1. merchant/location-level literal MCC;
2. useful Canadian coverage;
3. production API or legally reusable bulk data;
4. permission to persist/use the result in PickMe's graph; and
5. **$0 recurring production cost**.

Future agents should re-check the market rather than assuming this remains true forever.

## Strong free source: owner issuer exports

Some business/commercial card reporting systems expose literal MCCs in data the cardholder already owns.

RBC's published Visa Business Reporting guide documents transaction-detail fields including:

- Merchant Name
- MCC
- Expense Category
- Transaction Date
- Posting Date
- Billing Amount
- Billing Currency Code

and documents CSV/Excel export.

Primary source reviewed:

- RBC / Visa Business Reporting User's Guide: `https://www.rbcroyalbank.com/business/credit-cards/_assets-custom/pdf/Visa_VBR_HelpGuide_EN.pdf`

Do not generalize this to ordinary personal-card CSVs. Many consumer exports do not expose a literal MCC.

## What is implemented

### Strict local MCC CSV importer

Files:

- `Store/Sources/CardCopilotStore/MerchantMCCExactImport.swift`
- `Store/Tests/CardCopilotStoreTests/MerchantMCCExactImportTests.swift`
- `App/CardCopilot/Views/SettingsView.swift`

Settings exposes **Import issuer MCC CSV**.

A row is accepted as literal MCC evidence only when it contains:

1. a merchant/supplier field;
2. explicit `MCC`, `MCC Code`, or `Merchant Category Code`; and
3. a transaction/posting date.

The importer does **not** reinterpret category, SIC, NAICS, MapKit POI type, reward outcome, or an arbitrary four-digit field as an MCC.

Raw issuer files are not retained.

### Safe local purchase join — shipped

The previously planned local join is now implemented. See:

- `docs/superpowers/specs/2026-09-04-issuer-mcc-local-join-design.md`

A valid imported literal MCC can be upgraded from brand-level `ownerImportedMcc` to location-anchored `directOwnerMcc` only when it matches **exactly one** existing located purchase on the same iPhone.

Current promotion gates are deliberately conservative:

```text
deterministic canonical merchant match
+ explicit CAD amount matching local amountCad within $0.01
+ transaction date within 1 UTC day OR posting date within 4 UTC days
+ exact card-network agreement when the import knows the network
+ existing local latitude/longitude
+ exactly one compatible local purchase
= directOwnerMcc
```

Anything ambiguous stays `ownerImportedMcc` rather than being guessed.

Currency is a hard safety rule: a numeric `USD 42.17` must never match a local `CAD 42.17` merely because the numbers are equal. Direct promotion therefore requires an explicit CAD currency field in the issuer row under the current data model.

### Persistence/privacy

For unlocated evidence PickMe stores only normalized merchant, literal MCC, optional network, date and a non-sensitive idempotency key.

For a safely joined row, PickMe may additionally retain the already-local purchase coordinates and an opaque local-purchase UUID in the idempotency reference.

The MCC learner does not persist imported:

- amount;
- card/account number;
- raw card ID;
- raw CSV row;
- filename;
- statement text.

Amount/currency/network used for matching exist only during the import operation.

### Evidence semantics

`ownerImportedMcc` remains high-weight (`0.90`) brand-level owner evidence. It can move the predicted MCC/category but cannot by itself create location trust.

A safely joined row is `directOwnerMcc`. It can project to `.observedMcc` for the matching location because PickMe has both a literal issuer MCC and an unambiguous local purchase/location join.

Direct evidence is now **location-local for trust**: another branch of the same chain may weakly inform the brand posterior, but only exact place-ID or <=75 m coordinate evidence can contribute to `directObservationCount`, `isObserved`, or `isTrusted` for the queried location.

### Idempotency

Unlocated evidence dedupes by:

```text
source + canonical merchant + UTC day + MCC + network
```

so shopping frequency and unrelated transaction fields do not inflate brand confidence.

Safely joined evidence dedupes around the opaque local purchase UUID, allowing distinct real purchases to become distinct direct observations without persisting amount/card details.

### Erase semantics

**Erase This iPhone's History** clears imported MCC evidence and reward-derived MCC learning along with the other local history covered by that control.

### Purchase Routes

Imported and safely joined evidence are consumed by the same MerchantMCCGraph used by checkout and Purchase Routes. Do not create a second MCC resolver for route optimization.

## Highest-ROI free architecture

```text
open MCC taxonomy
        +
500-merchant researched prior
        +
MapKit/GPS merchant identity
        +
local learned aliases
        +
owner reward/category reconciliation
        +
owner explicit-MCC CSV imports
        +
safe local purchase/location joins
        +
opt-in anonymous community MCC observations
                |
                v
        MerchantMCCGraph
                |
                v
       card recommendation
```

This keeps incremental data-provider cost effectively zero and improves from real use.

## Current priority order

1. **Location-anchored direct owner literal MCC** — strongest evidence.
2. **Safely joined owner issuer-file MCC** — now automatically reaches the same direct evidence class when the local join is unique.
3. **Unlocated owner issuer-file literal MCC** — strong brand evidence.
4. **Community literal MCC observations** — scalable shared evidence, always weaker than owner truth.
5. **Reward/category outcomes** — free and low-friction; never fabricate an exact MCC.
6. **Public researched sources** — manual/periodic corroboration subject to usage rights.
7. **Open MCC taxonomies / MapKit category** — vocabulary/context, not literal merchant MCC truth.

## Next work under the free constraint

### P1 — measure join and decision yield

Before making the matcher more permissive, collect aggregate-only local diagnostics such as:

- import rows with enough fields to attempt a join;
- safely joined rows;
- ambiguous rows;
- rows lacking local location;
- currency/network mismatches;
- percentage of joins that actually change the winning card.

Do not record merchant, amount, card, or location in those diagnostics.

### P1 — source-specific issuer adapters

Add an adapter only when a real/documented export format is available. An adapter may safely tighten:

- column names;
- currency semantics;
- transaction vs posting-date behavior;
- known network;
- issuer transaction identifiers, if available.

A verified issuer transaction ID that can be joined locally would be preferable to heuristic date/amount matching.

### P1 — community flywheel

Keep literal-MCC community sharing opt-in and privacy-minimal. Improve participation/quality only when field data shows it meaningfully changes recommendations.

A local issuer-file import must never silently become a community upload merely because the row was safely joined.

### P2 — manual research queue

A future tool may prioritize merchants where MCC uncertainty can change the recommended card, then let a human/agent verify public evidence. Do not scrape third-party lookup tools without explicit permission.

## Revisit paid providers only with measured ROI

Before proposing paid merchant data again, show:

- percentage of checkouts where MCC uncertainty changes the winner;
- failure/coverage rate of seed + local learning + imports + community;
- expected provider coverage improvement;
- realistic monthly production cost;
- estimated value of the resulting recommendation improvement.

Until then, optimize the free learning flywheel rather than adding a paid dependency.
