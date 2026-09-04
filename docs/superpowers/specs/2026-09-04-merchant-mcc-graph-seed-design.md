# Merchant MCC graph seed and learning model

**Date:** 2026-09-04  
**Status:** seed implementation  
**Scope:** PickMe Canada merchant classification; no bank/credit-card linking; zero-cost data path.

## Decision

PickMe will own a learning merchant-MCC graph. The uploaded Canada 500 merchant list becomes the initial identity seed, but every MCC attached to that list is an **editorial prior**, not payment-network ground truth.

`contracts/merchant-pack.json` remains responsible for descriptor/brand recognition and spend-category fallback. The new MCC graph is responsible for MCC evidence and uncertainty. Do not collapse those two concepts.

## Seed inputs

1. **Merchant scope:** exactly the 500 merchants from `pickme_canada_500_merchant_seed(1).xlsx`.
2. **MCC taxonomy:** Adyen DABstep's `merchant_category_codes.csv` (CC-BY-4.0):
   https://huggingface.co/datasets/adyen/DABstep/blob/main/data/context/merchant_category_codes.csv
3. **Low-confidence location examples:** MCC-Codes.com Canada:
   https://www.mcc-codes.com/Canada
   The directory explicitly disclaims completeness/accuracy and says merchant data can change, so its rows are retained only as location-scoped evidence with low confidence:
   https://mcc-codes.com/Canada/disclaimer

No proprietary database is bulk-copied. The seed uses only the merchants in PickMe's supplied list.

## Why the graph stores distributions

A brand is not guaranteed to have one MCC. MCC can vary by terminal/location, acquirer, payment network, channel, and merchant-of-record. Public community data already demonstrates conflicts: individual Costco, Shoppers Drug Mart, and McDonald's locations appear under different MCCs.

Therefore the graph stores:

- a **brand prior profile**: candidate MCCs + weights + low confidence;
- **location/network/channel observations** as separate evidence;
- a computed posterior at recommendation time.

Never rewrite a brand to `merchant -> one MCC` merely because one observation exists.

## Runtime data model

The production database should normalize these concepts:

```text
Merchant
  id
  canonical_name
  aliases / merchant-pack link

MerchantLocation
  id
  merchant_id
  mapkit_place_id?
  latitude?
  longitude?
  address_hash?
  country

MccEvidence
  id
  merchant_id
  merchant_location_id?
  mcc
  network?
  channel?
  evidence_type
  evidence_weight
  observed_at
  source_fingerprint

MccPosterior
  merchant_id
  merchant_location_id?
  network?
  channel?
  mcc_distribution
  confidence
  evidence_count
  recomputed_at
```

`MccPosterior` is derived/cacheable state. `MccEvidence` is the audit trail.

## Evidence ladder

Use evidence strength, not source order alone:

| Evidence type | Suggested starting weight | Notes |
|---|---:|---|
| `network_observed` | 1.00 | Actual payment-network/processor MCC if PickMe ever receives one |
| `user_entered_exact_mcc` | 0.80 | User explicitly supplies the 4-digit MCC from issuer detail |
| `reward_outcome_inference` | 0.55 | User reports the multiplier/category actually earned; narrows MCC/category but may not identify one exact code |
| repeated independent location confirmations | +0.20 each | Cap so one crowd cluster cannot overpower contradictory strong evidence |
| `community_directory_location` | 0.35 | Public directory datapoint; location scoped; never brand truth |
| editorial seed prior | 0.20 | Bootstraps recommendations only |

The seed contract caps editorial profile confidence at 0.60 and community-directory evidence at 0.40.

## Learning rule

For each `(merchant, location?, network?, channel?)`, maintain weighted counts for candidate MCCs.

```text
score(mcc) = prior_weight(mcc) + sum(evidence_weight for matching evidence)
posterior(mcc) = score(mcc) / sum(score(all candidate MCCs))
```

Use a small prior floor so new MCCs can enter the distribution. Do not delete contradictory evidence; lower confidence when disagreement is material.

A later implementation can replace this simple weighted-count model with a Dirichlet/Bayesian update without changing the contract.

## Promotion thresholds

Suggested first thresholds:

- **prior only:** `confidence < 0.60` — recommendation may use the MCC but UI/debugging must call it predicted;
- **location learned:** at least 2 independent non-editorial confirmations agreeing and posterior >= 0.80;
- **strong learned:** at least 3 confirmations across >=2 users/sources and posterior >= 0.90;
- **conflicted:** top two MCCs within 0.20 posterior — keep both and score card recommendations across both branches.

These are initial product thresholds, not immutable constants.

## Free crowdsourcing path

Because PickMe will not link financial accounts, do not ask users to type an MCC on every purchase.

Use low-friction feedback:

1. Capture Apple Wallet transaction descriptor + amount + card + location as today.
2. Resolve merchant/location with the existing merchant recognizer + MapKit.
3. If the recommendation result is uncertain, ask one useful question such as:
   - “Did this earn your grocery/dining bonus?”
   - “What multiplier did this purchase earn?”
4. Convert that answer into `reward_outcome_inference`.
5. Offer an advanced optional “I know the MCC” action for users who can see a 4-digit MCC in issuer details.
6. Store only the derived merchant evidence needed for the graph; do not make user transaction history part of the public graph.

## Recommendation integration

Keep issuer/card reward rules separate:

```text
merchant identity
    -> MCC posterior
    -> each card's issuer MCC/category rules
    -> expected reward for each candidate MCC
    -> confidence-aware best-card decision
```

If every likely MCC produces the same winning card, recommend it confidently even when the MCC itself is uncertain. If different MCC branches produce different winners, ask for confirmation or show uncertainty.

This preserves the existing engine principle that ambiguity is harmless when every branch agrees.

## High-ROI safeguards implemented with the seed

- all 500 merchant ids are unique;
- all merchant rows reference a known profile/category;
- profile weights must sum to 1;
- editorial confidence cannot masquerade as verified evidence;
- community-directory evidence must include a location and source URL;
- observations cannot reference merchants outside the supplied 500;
- conflicts remain evidence instead of being averaged away.

Run:

```bash
python3 scripts/validate-merchant-mcc-graph.py
```

## Known existing-data issue

The current `merchant-pack.json` entry for Air Canada uses MCC `3000`, while the MCC taxonomy identifies `3000` as United Airlines and `3009` as Air Canada. The new seed uses `3009`. The merchant-pack value should be corrected in a focused follow-up after its synchronized contract copies/tests are updated together.
