# US remaining recurring-credit promotion review — 2026-08-31

## Decision

The US remaining pack is structurally valid and closes the missing research input identified by
the earlier promotion review. It covers 74 canonical US card IDs and contains 52 proposed credit
rows: 19 high-confidence, 33 medium-confidence, and 42 separately refused claims.

All 74 parent cards are currently draft catalogue entries. This review approves 13 fixed-value
high-confidence rows for normalization onto those draft cards and quarantines six high-confidence
rows that the current `CardCredit` contract cannot represent exactly. Medium-confidence rows are
retained in research only. As a result, this import changes no published-card recommendation,
portfolio, reminder, or checkout behavior.

## Coverage

| Status | Cards |
|---|---:|
| Complete | 37 |
| Partial | 15 |
| Unknown | 22 |
| **Total** | **74** |

The 74 card IDs are unique, all resolve to canonical catalogue cards, and do not overlap the base
research pack. The pack's credit IDs are also unique. Card-level `creditCoverage` may be promoted
for all 74 rows because it records review completeness rather than asserting a credit exists.

## Approved draft-only credits

| Card | Credit | Checkout behavior |
|---|---|---|
| `american-express-green-card` | `amex-green-clear-plus-credit` | Portfolio/reminder only; CLEAR+ is not a canonical merchant. |
| `american-express-the-business-platinum-card` | `amex-business-platinum-clear-plus-credit` | Portfolio/reminder only; shared account cap retained. |
| `american-express-delta-skymiles-gold-business` | `amex-delta-gold-business-delta-stays-credit` | Portfolio/reminder only; Delta Stays has no contract channel or merchant ID. |
| `american-express-delta-skymiles-platinum` | `amex-delta-platinum-delta-stays-credit` | Portfolio/reminder only; shared account cap retained. |
| `american-express-hilton-honors` | `amex-hilton-aspire-clear-plus-credit` | Portfolio/reminder only; CLEAR+ is not a canonical merchant. |
| `chase-sapphire-reserve-for-business` | `sapphire-reserve-business-travel-credit` | Broad travel predicate is issuer-supported; account opening date is required to resolve the anniversary window. |
| `chase-sapphire-reserve-for-business` | `sapphire-reserve-business-select-hotels-credit` | Chase Travel lodging only; effective 2026-01-01 through 2026-12-31. |
| `chase-sapphire-reserve-for-business` | `sapphire-reserve-business-google-workspace-credit` | Portfolio/reminder only; no canonical merchant ID. |
| `chase-sapphire-reserve-for-business` | `sapphire-reserve-business-ziprecruiter-credit` | Portfolio/reminder only; no canonical merchant ID. |
| `chase-sapphire-reserve-for-business` | `sapphire-reserve-business-lyft-credit` | Canonical Lyft merchant predicate; partner enrollment and shared account cap retained. |
| `chase-sapphire-reserve-for-business` | `sapphire-reserve-business-gift-card-credit` | Portfolio/reminder only; the issuer storefront is not a supported checkout channel. |
| `capital-one-venture-business` | `capital-one-venture-business-travel-credit` | Portfolio/reminder only; account opening date is required and Business Travel is not a supported channel enum. |
| `capital-one-venture-business` | `capital-one-venture-business-advertising-software-credit` | Portfolio/reminder only; issuer categories are retained as usage terms because PickMe has no authoritative MCCs. |

No free-form merchant slug, unsupported channel, or inferred MCC is emitted. A missing checkout
predicate means the credit remains useful for portfolio valuation and reminders but cannot boost a
point-of-sale recommendation.

## Quarantined high-confidence credits

| Card / credit | Reason |
|---|---|
| `chase-aeroplan-card / chase-aeroplan-trusted-traveler-credit` | The issuer's four-year benefit does not establish the anchor required by PickMe's `lastRedemptionAt` rolling schedule. |
| `chase-sapphire-reserve-for-business / sapphire-reserve-business-the-edit-credit` | The $500 annual total has a $250 per-transaction cap, which the current contract cannot encode. |
| `chase-sapphire-reserve-for-business / sapphire-reserve-business-trusted-traveler-credit` | First-eligible-charge and shared-alternative semantics cannot be represented by a generic rolling credit. |
| `chase-sapphire-reserve-for-business / sapphire-reserve-business-shops-at-chase-credit` | Eligibility depends on $120,000 annual spend and value remains available into the following calendar year. |
| `chase-sapphire-reserve-for-business / sapphire-reserve-business-southwest-chase-travel-credit` | Same spend-unlock and cross-year availability mismatch. |
| `capital-one-venture-business / capital-one-venture-business-trusted-traveler-credit` | The four-year issuer text does not safely establish PickMe's rolling-window anchor. |

## Import controls

The importer requires the base, CA remaining, and US remaining packs before mutation. Market packs
override card-level coverage metadata; conflicting duplicate credit claims are errors. The 19 US
high-confidence IDs are an explicit reviewed set: 13 allowlisted and six quarantined. Any future
high-confidence row added to this dated pack fails closed until a new promotion review updates that
set. Credit rows still require high confidence, fixed money, canonical card identity, billing
currency agreement, and schema-safe normalization.

Draft-card publication remains a separate D3 decision. Before any of these cards becomes published,
its complete card contract—not just recurring credits—must pass issuer verification and the normal
cross-language release gate.
