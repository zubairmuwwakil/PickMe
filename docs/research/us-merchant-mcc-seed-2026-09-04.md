# United States merchant MCC seed — first additive tranche

**Checked:** 2026-09-04
**Scope:** 50 US merchants added as `merchants-501-550.json`; the existing 500 Canadian IDs are unchanged.

## Method and evidence boundary

This is a deliberately narrow first tranche: grocery, dining, fuel, pharmacy,
wholesale, department store, electronics, sporting goods, and lodging are the
categories where the supported US cards most often expose a different reward
outcome. Each added merchant has a merchant-specific `sourceUrl`, `sourceMcc`,
and `sourceChecked` field in the canonical shard. The graph validator rejects a
US row without those fields or whose cited MCC differs from its profile primary.

The citations are public location reports from MCC-Codes.com, not payment-network
truth. They remain low-confidence editorial priors; no report becomes direct
observed MCC evidence. No raw pages or copied directory dataset are retained.
This follows the repository's source policy: retain a minimal URL/provenance
record and write PickMe's own facts, while allowing owner evidence to override.

## Sources

- [US MCC 5411 location reports](https://mcc-codes.com/USA/5411) — 16 grocery
  merchants, including the US-specific Walmart and Whole Foods identities.
- [US MCC 5812 location reports](https://mcc-codes.com/USA/5812) — six
  full-service dining merchants.
- [US MCC 5814 location reports](https://mcc-codes.com/USA/5814) — six quick-service
  dining merchants.
- [US MCC 5541 location reports](https://mcc-codes.com/USA/5541) — seven fuel
  merchants, including Costco Gas rather than a warehouse inference.
- [US MCC 5912 location reports](https://mcc-codes.com/USA/5912) — four pharmacy
  merchants.
- [US MCC 5300 location reports](https://mcc-codes.com/USA/5300),
  [5311](https://mcc-codes.com/USA/5311), [5732](https://mcc-codes.com/USA/5732),
  [5941](https://mcc-codes.com/USA/5941), and [7011](https://mcc-codes.com/USA/7011)
  — the remaining wholesale, department store, electronics, sporting-goods, and
  lodging entries.

## Identity decision

Country is a required seed field. An existing Canadian ID was never renamed or
reused. Where the same display brand is seeded in both countries, the US row has
a new `-us` ID and resolution receives the *physical merchant country* from
MapKit. An unknown location country fails closed for a duplicated name; older
Canada-only callers retain an explicit Canada compatibility scope. This avoids
merging learned US and Canadian evidence simply because a chain has the same
display name.
