# Purchase Decision Architecture — rewards + protection + routes

**Status:** Ratified V1 architecture, implemented incrementally on 2026-09-04.

**Policy version:** `conservative-multi-attribute-v1`

## Executive decision

PickMe must let verified card benefits influence the **final purchase decision**, but must not mix
benefit limits directly into `RecommendationEngine`'s reward/credit dollar score.

The architecture is therefore layered:

```text
merchant + purchase facts
        |
        +--------------------------+
        |                          |
        v                          v
RecommendationEngine        BenefitsAdvisor
(reward economics)          (certificate facts)
        |                          |
        +-------------+------------+
                      v
              PurchaseDecisionAdvisor
              (final multi-attribute verdict)
                      |
           +----------+-----------+
           |                      |
           v                      v
      direct checkout       PurchaseRouteAdvisor
                            (alternate funding path)
```

The economic winner remains measurable in CAD. Protection remains a separate, explainable decision
attribute until PickMe has evidence strong enough to defend a conversion into expected monetary or
user-specific utility.

This document intentionally leaves the policy replaceable. A future agent may change it when a
higher-ROI, more scalable, or more defensible model exists, provided the migration rules below are
followed.

## Why this exists

A card can earn less but materially change the owner's protection because card benefits commonly
have payment-method eligibility conditions. An alternate route can also change the payment path
itself: buying a merchant gift card at another store may mean the destination item is no longer
charged to the credit card that would otherwise provide purchase protection or warranty coverage.

Examples from official Canadian issuer material:

- American Express Canada says Buyer's Assurance can require the **entire purchase price** of an
  eligible new item to be charged to the Card, while Purchase Protection applies to eligible items
  charged to the Card: <https://www.americanexpress.com/ca/en/security/shopping-protection/>.
- American Express Cobalt publishes the same entire-purchase-price condition for Buyer's Assurance:
  <https://www.americanexpress.com/ca/en/benefits/cobalt-card/>.
- Scotiabank's Purchase Security and Extended Warranty certificate defines an insured item as one
  for which the **full purchase price is charged to an Account**, and states the same condition for
  Purchase Security:
  <https://www.scotiabank.com/ca/common/pdf/credit_card/purchase_security_and_extended_warranty_protection.pdf>.
- Scotiabank's current Passport Visa Infinite Privilege insurance page likewise states that the
  full cost must be charged to the card for the described shopping/mobile-device coverages:
  <https://www.scotiabank.com/ca/en/personal/credit-cards/visa/passport-infinite-privilege-card/welcome-kit/insurance.html>.

These are examples, not universal rules. PickMe continues to use each card's own certificate-backed
benefit contract and verification state.

## Why benefits do not go inside the reward score

A coverage limit is not the same thing as expected economic value.

For example, a `$1,000` purchase-protection limit does **not** imply that the benefit is worth
`$1,000`, `$10`, or any other fixed amount for a given checkout. Converting it to CAD defensibly
would require, at minimum:

1. eligibility probability for this exact purchase and payment path;
2. probability and distribution of covered loss during the coverage window;
3. claim approval / deductible / coordination effects;
4. the owner's risk preference and outside insurance;
5. enough evidence to keep those estimates calibrated over time.

PickMe has certificate facts today, but it does not have a defensible probability-of-loss model or
owner utility function. Inventing those values would create false precision and make explanations
less trustworthy.

The broader decision-analysis pattern is multi-attribute decision making: alternatives can have
conflicting quantitative and qualitative attributes, and scalar utility requires explicit
normalization/preferences rather than silently treating unlike quantities as money. A conceptual
reference is the MAUT overview in *Encyclopedia of Multi-Attribute Decision Making* (2026), DOI
<https://doi.org/10.1016/B978-0-443-33275-3.00069-5>. PickMe does **not** claim to implement full
MAUT in V1; the reference explains why keeping attributes explicit is preferable to an arbitrary
scalarization.

## Invariants

### D1 — Reward economics stay pure

`RecommendationEngine` remains the authority for reward/credit economics. Benefits must not mutate
`decisionValueCad`, reward multipliers, point valuations, caps, or issuer credits.

### D2 — Benefit facts remain certificate facts

Benefits stay in `BenefitsCatalogue` with their existing provenance/verification ladder. Decision
policy must not promote a `stub` benefit into trusted coverage.

### D3 — Merchant category is not purchase type

MCC/category describes the merchant transaction, not necessarily the item. A large purchase at a
pharmacy may be a phone, cosmetics, groceries, medicine, or something else. PickMe must not infer a
benefit context such as `electronics` solely from merchant category.

### D4 — Unknown is a first-class result

If purchase context is needed, return `purchaseContextNeeded`. Do not force a winner.

### D5 — A trade-off is not a negative dollar amount

If the reward leader and protection evidence disagree, return a trade-off verdict. Do not subtract
an invented insurance value from rewards.

### D6 — Policy is versioned separately from issuer facts

Current policy version: `conservative-multi-attribute-v1`.

A future policy change should get a new version. This makes historical recommendations and future
learning interpretable without pretending the issuer contract changed.

## V1 direct-purchase policy

`PurchaseDecisionAdvisor` receives:

- the reward recommendation;
- `PurchaseContext`;
- wallet card ids;
- the benefits catalogue;
- optional owner-declared `BenefitContext`.

It returns one of:

- `rewardLeader` — no material trusted protection evidence is currently relevant;
- `rewardProtectionAligned` — declared purchase context has a unique/only protection leader and it
  agrees with the reward winner;
- `rewardProtectionTradeoff` — reward and protection point at different cards;
- `protectionTradeoffUnresolved` — declared context has a genuine Pareto trade-off and no single
  protection winner;
- `purchaseContextNeeded` — the purchase is material, trusted shopping protection exists in the
  wallet, but PickMe does not know what item is being purchased.

The current materiality threshold reuses `BenefitsCatalogue.triggers.bigTicketThresholdCad` rather
than introducing a second magic number.

When context is missing, V1 is intentionally conservative: a material purchase with trusted
shopping protection asks what the owner is buying instead of inferring the item from the merchant.

## Protection comparison once context is known

The existing `BenefitsAdvisor.comparison` remains the source of protection comparison semantics.
It evaluates the declared purchase context and may identify a unique Pareto-maximal card across the
coverage facts shown to the user.

If exactly one relevant-coverage card exists, V1 treats it as the only protection candidate even
when there are too few numeric fields for Pareto dominance to name it.

If multiple cards remain Pareto-maximal, the final decision is explicitly unresolved rather than
silently applying an undocumented preference weight.

## Checkout UX

For a material purchase, the recommendation screen can still show the reward winner immediately,
but it must not imply that rewards are necessarily the whole decision.

The current integration in `BenefitsDisclosureSection` shows:

> Rewards are only part of this decision

and offers purchase-context entry points into the existing protection lens:

- Electronics
- Phone
- Appliance / furniture

The protection lens continues to show certificate-backed facts and provenance rather than promising
claim eligibility.

This is an incremental UX. A future version may replace the buttons with a richer purchase-type
selector shared by checkout, receipts, and post-purchase reconciliation.

## Alternate purchase routes

`PurchaseRouteAdvisor` sits above `RecommendationEngine` and now carries a separate protection axis.

Routes declare a funding-path fact:

- `preservesDestinationCardCharge`; or
- `replacesDestinationCardCharge`.

The route's reward economics are still calculated normally:

```text
route reward/credit value - fixed fees - estimated friction
```

Protection then produces a separate assessment/verdict:

- `rewardAdvantage`; or
- `rewardProtectionTradeoff`.

A gift-card route is currently marked `replacesDestinationCardCharge`. This does not assert that
all protection is lost; it tells the protection layer that the destination item is no longer being
charged in the same way and that benefit eligibility must be evaluated before calling the route
unambiguously better.

## What V1 deliberately does not do

V1 does **not**:

- assign a cash value to insurance;
- train on claim outcomes that PickMe does not possess;
- infer an item from MCC alone;
- make a coverage/claim promise;
- merge benefit certificate facts into reward contracts;
- hide unresolved trade-offs behind one opaque score;
- assume the highest coverage limit is always the user's preferred choice.

## Future replacement paths

This section is intentionally open. A future agent should prefer a replacement when it has better
expected product value **and** stronger evidence.

### Candidate A — user preference / utility weights

Allow the owner to express preferences such as:

- maximize rewards;
- protect electronics strongly;
- prefer warranty over short-term purchase protection;
- minimize extra stops/friction.

A preference model could turn some currently unresolved trade-offs into personalized decisions.
Weights must be visible/editable and should not masquerade as issuer facts.

### Candidate B — expected-utility / expected-loss model

If PickMe later obtains legally/privacy-appropriate, sufficiently large, calibrated data on covered
loss frequency and claim outcomes, it could estimate expected protection value. This is the first
point at which a CAD-like expected value may become defensible.

Do not ship this because a model *can* produce a number. Require calibration, back-testing,
uncertainty intervals, and an explicit user risk model.

### Candidate C — Pareto / outranking policy

A richer non-compensatory model could keep rewards, fees, friction, reliability, and protection as
separate criteria and eliminate dominated choices without requiring dollar conversion. This is a
natural extension of the current conservative design.

### Candidate D — learned contextual policy

With enough consented interaction data, PickMe could learn which recommendation owners choose in
specific contexts. A contextual bandit/ranking model may eventually improve personalization.

Guardrails:

- never learn issuer facts from preference clicks;
- keep deterministic issuer/card eligibility underneath the learned ranker;
- preserve an explainable fallback;
- separate exploration from high-stakes protection claims;
- version the learned policy and log its input provenance.

## Criteria for changing this architecture

A future agent may replace V1 without preserving its exact algorithm when the proposed design can
answer these questions better:

1. **Correctness:** Does it reduce known false recommendations or unresolved decisions?
2. **Evidence:** Are new inputs observed/verified rather than invented?
3. **Calibration:** If it outputs probabilities or dollars, can those values be tested?
4. **Explainability:** Can the owner understand why the final choice changed?
5. **Separation of truth:** Are issuer facts still separate from user preferences and learned data?
6. **Privacy:** Does learning avoid unnecessary purchase/account/device identity sharing?
7. **Scalability:** Can new benefit kinds, route types, and markets plug in without merchant/card
   hard-codes?
8. **Backward safety:** Can the old deterministic policy remain a fallback during rollout?
9. **ROI:** Does the added complexity materially improve decisions often enough to justify it?

If a new design wins on these dimensions, change the architecture. This document is a rationale and
migration baseline, not a prohibition on improvement.

## Migration protocol for a future policy

When changing final-decision semantics:

1. add a new policy version rather than mutating the meaning of the old version silently;
2. add Swift tests first, then the Kotlin twin;
3. keep reward contract bytes unchanged unless issuer reward facts actually changed;
4. add representative fixtures for cases where the new policy differs;
5. document why the new evidence/model is more defensible;
6. if telemetry exists, compare old/new decisions before making the new policy default;
7. preserve a deterministic fallback until the new policy is proven stable.

## Testing contract

Current tests cover:

- small purchases remain reward-only;
- material purchases request item context instead of inferring purchase type from merchant category;
- declared electronics context produces a protection decision;
- alternate-funding protection trade-offs are represented separately from reward advantage;
- Swift and Kotlin implement the same decision policy shape.

Cross-language gate:

```bash
(cd Engine && swift test) && (cd android && ./gradlew :core:engine:test)
```

## Canonical files

Direct final decision:

- `Engine/Sources/CardCopilotEngine/Engine/PurchaseDecisionAdvisor.swift`
- `Engine/Tests/CardCopilotEngineTests/PurchaseDecisionAdvisorTests.swift`
- `android/core/engine/src/main/kotlin/com/cardcopilot/engine/engine/PurchaseDecisionAdvisor.kt`
- `android/core/engine/src/test/kotlin/com/cardcopilot/engine/PurchaseDecisionAdvisorTest.kt`

Protection facts/comparison:

- `Engine/Sources/CardCopilotEngine/Engine/BenefitsAdvisor.swift`
- `Engine/Sources/CardCopilotEngine/Models/BenefitsModels.swift`
- `contracts/benefits-catalogue.json`

Route decision:

- `Engine/Sources/CardCopilotEngine/Engine/ProtectionDecisionAdvisor.swift`
- `Engine/Sources/CardCopilotEngine/Engine/PurchaseRouteAdvisor.swift`
- Kotlin twins under `android/core/engine/...`.

Checkout integration:

- `App/CardCopilot/Views/BenefitsDisclosureSection.swift`
- `App/CardCopilot/Views/RecommendationView.swift`

## Open implementation work

The semantic architecture is intentionally ahead of some UX plumbing. Highest-ROI follow-ups are:

1. pass `BenefitsCatalogue` into every Purchase Route evaluation call and render
   `rewardProtectionTradeoff` distinctly from a clean reward advantage;
2. persist a lightweight purchase-type selection through checkout so the final-decision verdict can
   update in-place rather than only opening the protection lens;
3. record the decision policy version with recommendation diagnostics/telemetry once that storage has
   a clear privacy/product purpose;
4. add route types (portals, issuer offers, intermediaries) using the same separate reward/protection/
   reliability dimensions rather than special-casing them in `RecommendationEngine`.
