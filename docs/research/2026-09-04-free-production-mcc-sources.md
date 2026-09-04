# Free-production MCC sources — hard product constraint

**Date:** 2026-09-04  
**Status:** active product constraint; strict owner-file importer and Settings UI implemented  
**Owner decision:** recurring production cost for merchant/MCC enrichment must be **$0** unless the owner explicitly revisits this decision.

## Decision

Do not integrate a paid merchant/MCC lookup provider into PickMe production merely because it improves coverage.

Mastercard Places, Plaid, MX, Visa commercial merchant products, and similar providers may still be researched or tested in sandbox, but they are **not production candidates** unless a genuinely free production tier with acceptable rights/limits is verified.

This supersedes the earlier provider ranking only on economics: Mastercard Places remains technically attractive, but it is not the current implementation target because free production access has not been verified.

## What the research found

### Free MCC taxonomies exist

There are multiple open/public MCC-code datasets and libraries that map four-digit MCC values to descriptions. These are useful for taxonomy validation, not merchant resolution.

Examples reviewed:

- `greggles/mcc-codes`
- `Rebilly/merchant-category-codes`
- `pax2pay/merchant-category`

These answer:

> `5411` means grocery stores/supermarkets.

They do **not** answer:

> this specific Metro at this location currently codes as `5411` on this network.

PickMe already has MCC taxonomy coverage, so adding another taxonomy package has little incremental ROI.

### AwardWallet is useful as a human research signal, not a production dependency

AwardWallet has a free public Merchant Lookup Tool based on how transactions from its users were categorized/bonused. It is useful for manual research and validation because it can show how a named merchant has been seen to code across issuers.

However:

- the public merchant lookup is not documented as a free merchant-MCC production API;
- its merchant tool frequently exposes issuer/category outcomes rather than a universally applicable literal four-digit MCC;
- AwardWallet's broader Web Parsing API can expose an `MCC` field only when an underlying provider supplies it, but that API has separate commercial/API access and is not a free merchant-location lookup feed;
- no redistribution/cache right for building PickMe's merchant graph was verified.

Therefore AwardWallet may be used as a **manual researched-seed / corroboration source** when licensing/attribution permits, but must not be scraped or treated as a runtime API without explicit permission.

### Visa public tools do not solve the free exact-MCC problem

Visa publishes a current public MCC manual and a free consumer-facing Back to Business merchant locator. Those are useful taxonomy/merchant-presence resources, but the public locator does not expose a reusable location-level MCC feed.

Visa Supplier Matching can return MCCs, but Visa states production requires approval and production fees; sandbox access alone does not satisfy this product constraint.

### Free owner exports can sometimes expose a literal MCC

A materially better free path exists for some **commercial/business card reporting** systems.

RBC's published Visa Business Reporting user guide documents that transaction-detail reporting includes:

- Merchant Name
- MCC
- Expense Category
- Transaction Date
- Posting Date
- Billing Amount
- Billing Currency Code

The same guide documents exporting transaction details/results to **CSV or Excel**. It defines MCC as the four-digit Merchant Category Code.

Primary source:

- RBC / Visa Business Reporting User's Guide: `https://www.rbcroyalbank.com/business/credit-cards/_assets-custom/pdf/Visa_VBR_HelpGuide_EN.pdf`

This is important because it is owner-controlled data and does not require PickMe to pay a data provider or link a bank account.

Do **not** generalize this to every personal credit-card CSV. Public consumer documentation reviewed from major Canadian issuers usually discusses MCC as a rewards-classification mechanism, but does not document a literal MCC column in ordinary transaction exports. For example, TD's consumer card guidance tells users with questions about a purchase's MCC to contact TD rather than documenting an MCC export.

### No trustworthy free production merchant/location -> exact-MCC API was verified

As of this review, no source was found that simultaneously provides:

1. merchant/location-level literal MCC;
2. useful Canadian coverage;
3. production API or legally reusable bulk data;
4. permission to persist/use the result in PickMe's graph;
5. **$0 recurring production cost**.

Future agents should re-check the market before assuming this remains true.

## Implemented free exact-MCC importer

PickMe now includes:

- `Store/Sources/CardCopilotStore/MerchantMCCExactImport.swift`
- `Store/Tests/CardCopilotStoreTests/MerchantMCCExactImportTests.swift`
- `Store/Tests/CardCopilotStoreTests/MerchantMCCLearningEraseTests.swift`
- `App/CardCopilot/Views/SettingsView.swift` — local **Import issuer MCC CSV** file picker and aggregate-only result surface.

### Accepted input

The first implementation accepts UTF-8 CSV when it contains all three semantic fields:

1. merchant/supplier name;
2. explicit `MCC`, `MCC Code`, or `Merchant Category Code`;
3. transaction/posting date.

A Visa Business Reporting source mode is available to Store adapters and tags imported evidence with `network = visa` when the export does not provide a network column. The generic Settings importer does not guess an issuer/network from the filename.

### Explicit rejection rules

The importer intentionally refuses to reinterpret any of the following as a literal MCC:

- generic category labels such as `Grocery`;
- `SIC`;
- `NAICS`;
- reward category outcomes;
- MapKit POI categories;
- four-digit numbers in unrelated columns.

This is a provenance rule, not just input validation.

### Privacy and persistence

Raw issuer files are not retained.

The importer persists only normalized MCC evidence:

- canonical PickMe merchant identity;
- literal MCC;
- optional network;
- observation date;
- an idempotency key constructed only from those retained facts plus source type.

It does **not** persist imported:

- transaction amount;
- card/account number;
- raw CSV row;
- filename;
- statement text.

The dedupe identity is scoped to:

```text
source + canonical merchant + UTC day + MCC + network
```

That design is deliberate. It prevents unrelated CSV fields from leaking indirectly through a whole-row hash and ensures multiple same-day purchases at the same merchant/MCC do not artificially inflate corroboration merely because the owner bought there more often.

Re-importing the same evidence is idempotent.

### User-facing behavior

Settings now exposes **Import issuer MCC CSV** under Merchant MCC learning.

The UI:

- uses the system file picker;
- reads the selected file locally;
- calls the Store importer rather than reimplementing parsing in App;
- displays aggregate imported/duplicate/skipped counts only;
- never uploads the file;
- does not persist the raw file.

The first UI slice supports CSV/text only. If a reporting product delivers CSV inside ZIP, manual extraction is acceptable until a dependency-light ZIP path has demonstrated enough value.

### Why imported MCC is a separate evidence kind

`ownerImportedMcc` is intentionally distinct from `directOwnerMcc`.

An issuer export may prove that the owner saw a literal MCC for a merchant, but without a trustworthy join to the specific PickMe store/location it is still **brand-level evidence**. It therefore:

- has high graph weight (`0.90`);
- may move the predicted MCC/category;
- is stronger than category inference or community evidence;
- **cannot** by itself set `MerchantMCCPrediction.isObserved`;
- **cannot** by itself set `isTrusted` or claim terminal/location verification.

A future safe local join may promote an imported row into `directOwnerMcc` only when PickMe can prove which local purchase/location it belongs to.

### Erase semantics

`Erase This iPhone's History` now clears both:

- reward-derived MCC evidence;
- imported exact-MCC evidence.

The Settings and account-deletion copy explicitly mentions local MCC learning. This also closes a pre-existing gap where reward MCC evidence could survive the local-history erase.

## Highest-ROI free architecture

The best free scalable strategy is therefore the architecture PickMe now owns rather than replacing it with a vendor:

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
literal location-anchored owner MCC when available
        +
opt-in anonymous community MCC observations
                |
                v
        MerchantMCCGraph
                |
                v
       card recommendation
```

This has effectively zero incremental data-provider cost and improves as real usage accumulates.

## Free-source priority order

1. **Location-anchored direct owner literal MCC** — strongest signal.
2. **Owner issuer-file literal MCC** — exact MCC but unlocated until safely joined.
3. **Community literal MCC observations** — scalable shared evidence; keep weaker than owner truth.
4. **Reward/category outcomes** — free, lower friction, but never fabricate an exact MCC from them.
5. **Public researched sources such as AwardWallet** — manual/periodic weak corroboration only, subject to usage rights.
6. **Open MCC taxonomies** — vocabulary/validation only.
7. **MapKit/POI category** — merchant/category context, never exact MCC truth.

## Highest-ROI next engineering work under the free constraint

### P0 — safe local purchase join

Imported rows become substantially more valuable if PickMe can join them to an existing local purchase/location without ambiguity.

Candidate join keys available transiently during import:

```text
canonical merchant
transaction/posting date window
amount
card/network when available
```

Important privacy rule: amount/card/account fields may be used **transiently for matching** but should not be copied into the MCC evidence ledger merely to make matching easier.

Promotion rule:

```text
unambiguous imported row + exactly one compatible local purchase/location
    -> location-anchored directOwnerMcc
ambiguous or zero matches
    -> keep ownerImportedMcc only
```

Do not majority-vote ambiguous matches. Do not promote a brand-level import simply because its MCC agrees with the seed.

### P1 — let real usage generate evidence

The decision-quality instrumentation already records whether MCC uncertainty actually changes the winning card. Do not build a more complex model until this produces enough field data to identify the real bottleneck.

### P1 — community flywheel

Because there is no free authoritative merchant-MCC feed, the community graph is strategically important. Improve participation and quality before adding vendor cost:

- keep upload opt-in and privacy-minimal;
- make literal-MCC reconciliation low-friction when a user can see the code;
- preserve location/network/channel provenance;
- watch conflict and winner-sensitivity metrics;
- add stronger privacy-preserving abuse controls only if real abuse/scale warrants them.

### P2 — issuer-format adapters

Add source-specific adapters only when a real export is available to test.

Good candidates are business/commercial reporting systems that explicitly label an MCC. A source adapter should mainly provide:

- known column aliases;
- known date format;
- known network if contractually/technically true;
- tests built from synthetic fixtures matching the documented shape.

Never add an adapter based only on an assumed undocumented export format.

### P2 — manual research automation without scraping

A future agent may build a **research work queue** that identifies high-value merchants where better MCC evidence could change the recommended card. A human/agent can then check public sources and record provenance.

Do not automate scraping of third-party merchant lookup tools unless their terms/API explicitly allow it.

## Revisit criteria

This $0 production constraint may be reconsidered only if the owner explicitly changes it or if a paid provider has a quantified positive ROI large enough to justify the cost.

Before proposing paid data again, show:

- measured percentage of checkouts where MCC uncertainty changes the winner;
- measured failure rate of the free graph/community/import path;
- expected provider coverage improvement;
- expected monthly cost at realistic usage;
- value of recommendation improvement relative to that cost.

Until then, optimize the free learning flywheel rather than adding a paid dependency.
