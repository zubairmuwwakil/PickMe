# Free-production MCC sources — hard product constraint

**Date:** 2026-09-04  
**Status:** active product constraint  
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

### No trustworthy free production merchant/location -> exact-MCC API was verified

As of this review, no source was found that simultaneously provides:

1. merchant/location-level literal MCC;
2. useful Canadian coverage;
3. production API or legally reusable bulk data;
4. permission to persist/use the result in PickMe's graph;
5. **$0 recurring production cost**.

Future agents should re-check the market before assuming this remains true.

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
literal owner MCC when available
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

1. **Direct owner literal MCC** — strongest signal, free when exposed by an issuer/export/reconciliation path.
2. **Community literal MCC observations** — scalable shared evidence; already live; keep weaker than direct owner truth.
3. **Reward/category outcomes** — free, lower friction, but never fabricate an exact MCC from them.
4. **Public researched sources such as AwardWallet** — manual/periodic weak corroboration only, subject to usage rights.
5. **Open MCC taxonomies** — vocabulary/validation only.
6. **MapKit/POI category** — merchant/category context, never exact MCC truth.

## Highest-ROI next engineering work under the free constraint

### P0 — let real usage generate evidence

The decision-quality instrumentation already records whether MCC uncertainty actually changes the winning card. Do not build a more complex model until this produces enough field data to identify the real bottleneck.

### P1 — improve exact-MCC ingestion from data the owner already has

Investigate issuer-specific sources that cost nothing to the app:

- CSV/downloaded transaction exports;
- statement data;
- issuer transaction-detail screens;
- email/receipt metadata only where it explicitly contains a literal MCC;
- owner reconciliation input.

Only ingest a value as direct MCC when the source actually labels it as MCC/merchant category code. Do not reinterpret SIC, generic category strings, or inferred rewards as exact MCC.

### P1 — community flywheel

Because there is no free authoritative merchant-MCC feed, the community graph is strategically important. Improve participation and quality before adding vendor cost:

- keep upload opt-in and privacy-minimal;
- make literal-MCC reconciliation low-friction when a user can see the code;
- preserve location/network/channel provenance;
- watch conflict and winner-sensitivity metrics;
- add stronger privacy-preserving abuse controls only if real abuse/scale warrants them.

### P2 — manual research automation without scraping

A future agent may build a **research work queue** that identifies high-value merchants where better MCC evidence could change the recommended card. A human/agent can then check public sources and record provenance.

Do not automate scraping of third-party merchant lookup tools unless their terms/API explicitly allow it.

## Revisit criteria

This $0 production constraint may be reconsidered only if the owner explicitly changes it or if a paid provider has a quantified positive ROI large enough to justify the cost.

Before proposing paid data again, show:

- measured percentage of checkouts where MCC uncertainty changes the winner;
- measured failure rate of the free graph/community path;
- expected provider coverage improvement;
- expected monthly cost at realistic usage;
- value of recommendation improvement relative to that cost.

Until then, optimize the free learning flywheel rather than adding a paid dependency.
