# Merchant MCC Graph — evidence, not hard-coded truth

**Date:** 2026-09-04  
**Status:** implemented foundation  
**Scope:** PickMe; free/no bank linking

## Goal

PickMe needs a useful MCC before payment without pretending a national brand has one permanent code. The graph therefore predicts an MCC from evidence and gets more confident as location-specific evidence accumulates.

## Non-negotiable provenance rule

A literal MCC and a reward/category confirmation are different facts.

- `directOwnerMcc`: a user explicitly supplies an MCC they can see from an issuer/transaction detail.
- `externalLocationReport`: public/community evidence tied to a merchant/location.
- `researchedSeed`: editorial bootstrap evidence.
- `categoryOutcome`: user confirms only how the purchase rewarded/categorized; this may improve category prediction but MUST NOT fabricate a 4-digit MCC.

The existing `merchant-pack.json` remains an editorial prior. Pre-index projection already keeps its MCC out of the observed-MCC slot.

## Graph identity

Evidence is evaluated across:

1. canonical merchant key,
2. Apple `placeID` when available,
3. coordinates as a fallback location signal,
4. purchase channel (`inStore`, `online`, `app`),
5. network when known.

An exact place match is stronger than a brand-only report. Conflicting evidence is kept as competing candidates rather than overwritten.

## Prediction

`MerchantMCCGraph.predict` combines the seed and evidence with source, location, channel, network and recency weights. Output is a ranked MCC distribution plus confidence.

A seed can make PickMe useful on day one but is never considered observed truth. At least two agreeing direct observations at the same target, plus sufficient aggregate confidence, are required for `isTrusted`.

## Learning loop

```text
researched seed
    ↓
first useful prediction
    ↓
location/category feedback and optional MCC evidence
    ↓
weighted merchant/location MCC distribution
    ↓
repeated direct evidence becomes trusted
    ↓
future checkout uses stronger local evidence
```

## Privacy / crowdsourcing

There is no bank connection and no requirement to upload transaction amount, card number, account data or full purchase history. A future opt-in aggregate service should accept only the minimum merchant-location/channel/MCC evidence required to strengthen the graph.

The current repository has the local resolver and existing category-learning consent gate, but **does not yet have a community uploader/backend or a user-facing MCC capture flow**. Those are separate follow-ons and must not be implied by the local graph implementation.

## Seed policy

The Canada seed is curated from the existing merchant pack and individually researched public reports. Proprietary sites are not bulk copied. Every seed should retain source, verification date and confidence, and conflicting location reports should lower brand-wide confidence rather than being discarded.

## High-ROI next steps

1. Feed observed MCCs from reconciliation into graph evidence when an actual MCC is supplied.
2. Add a lightweight optional “MCC shown by your card issuer” entry path; do not ask ordinary users to guess a code.
3. Add de-identified community aggregation behind explicit opt-in.
4. Prioritize merchants where category ambiguity changes the winning card: grocery/department stores, gas/convenience, pharmacy, dining/QSR, wholesale and mixed-format retailers.
5. Track prediction calibration: confidence bucket vs later confirmation rate, not just raw accuracy.
