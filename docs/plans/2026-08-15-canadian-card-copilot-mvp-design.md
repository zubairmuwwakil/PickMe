# Canadian Card Copilot — Personal MVP Design

**Date:** 2026-08-15
**Status:** Validated in brainstorming session (Zubair + Claude). Supersedes scope sections of the 2026-08-14 product brief; strategy sections of that brief remain the reference.
**Source brief:** `/Users/zub/Downloads/2026-08-14-canadian-card-copilot-product-brief.md`

---

## 1. Positioning (revised from brief)

**One-liner:** Tell a Canadian multi-card holder, at the moment of payment, which card in their wallet earns the most on this specific purchase — as a dollar figure with a confidence level, backed by evidence of how that merchant actually codes.

**Target user (revised):** The *knowledge-gap* holder — a Canadian with 2+ cards who doesn't know their earn rates, not the rewards optimizer of the brief's §5. The thesis is sharpened accordingly: the product **makes the invisible loss visible in dollars, then makes the fix effortless**. "Closing a knowledge gap" alone is not a product; unfelt losses don't change behavior.

**Wedge (verified 2026-08-15, sources in the research dossier):** creditcardGenius / Ratehub own "which card should I **get**." Nobody in Canada owns "which card should I **use**": MaxRewards shipped Best Card Nearby (v4.5.0, 2026-07-14) but still has no Canadian card support (the request remains open); CardPointers claims Canada support but its Canadian coverage is unquantified publicly (10-card in-app audit outstanding); no Canadian-native checkout copilot was found (Chexy is adjacent, bills/rent only). Full dossier: `docs/research/canadian-card-copilot-research-2026-08-15.md`.

## 2. Strategic decisions locked

| # | Decision | Consequence |
|---|----------|-------------|
| 1 | Target user = knowledge-gap casual holder | Onboarding must be "tap your cards, rules pre-filled" — users can't enter rules they don't know |
| 2 | Engine-first MVP (engine risk > demand risk) | Personal MVP proves accuracy on Zubair's 10-card wallet before market validation |
| 3 | Canadian card-rules catalogue on the critical path | Seed data is catalogue-shaped from day one; no hardcoded wallet |
| 4 | Merchant Truth Graph demoted to refinement for year one | Category-level correctness captures most recoverable value for the target user |
| 5 | Retention hook = **value-recovered counter**, not spend tracking | App never sees transactions; counter computed from accepted recommendations vs a user-designated default card |
| 6 | Engine risk = **data risk** (catalogue correctness + category prediction), not arithmetic | MVP is a measurement instrument for two numbers |
| 7 | Default card = **Wealthsimple VIP** (2%, no FX); baseline = the card the owner would otherwise have tapped *at that moment*, not an abstract 1% | Value-recovered counter and switch decisions both measure against it |
| 8 | **Switch threshold**: leave the default only when net advantage ≥ 0.5pp **and** ≥ C$0.25 (acceptance constraints override) | Kills 2.1%-vs-2% noise recommendations that erode trust |
| 9 | Triangle = **drawer card** (recommend only for known use-cases, with a warning); Crypto.com **excluded unless Level Up Pro is active** — card art ≠ reward rate | Owner carry/plan state is a first-class engine input |
| 10 | **Three-layer architecture**: card product rules (effective-dated, sourced) / owner-account state / merchant evidence | No cloning products per user; no global rule ever silently mutated by a personal observation |
| 11 | Valuations locked (dossier §3): MR 1.8¢ (floor 1.0), Bonvoy 0.8¢, MBNA 1.0¢ (floor 0.833), CT ×0.95 usability, CRO ×1.0 auto-sold / ×0.8 held, cash 1:1 | Encoded in `Engine/Sources/CardCopilotEngine/Resources/owner-state.json` |
| 12 | **Tangerine = treat-as-all-selected** (Zubair 2026-08-15): score its 13 eligible categories at a hypothetical 2%; the app later *advises* which 3 to actually select | Harmless at checkout (2% only ever ties the WS default); Tangerine recommendations carry a "hypothetical selection" warning; Tangerine reconciliation mismatches classify as owner-state misses, not catalogue misses |
| 13 | Owner state confirmed 2026-08-15: Rogers service NOT linked (1.5% base) and card opened Aug 2026 (zero cap progress); Level Up Pro NOT active (Crypto card excluded); **Scotia anchor RESOLVED to April 2025** — the + card's limits reset on the account-opening anniversary (verified from issuer terms); the Dec→Nov rule Zubair cited governs the *non-plus* card's award schedule | Seeded in owner-state.json; the ≈$12,500 4%-bucket figure is flagged suspect (if estimated from December it includes spend that already reset) |
| 14 | **Valuation honesty over valuation guessing**: rank by the declared value, but detect when the winner depends on it and disclose the breakeven cents-per-point | Rejected both single-number extremes — 1.8¢ flatters points cards, floor-only ranking punishes them; neither is knowable in advance. The app never trusts an assumption it could learn. |

**Future features (tabled, Zubair 2026-08-15):** Tangerine category advisor (suggest the optimal 3 selections from logged spend, respecting the 90-day change timing); spending-habit card-acquisition suggestions and best-value-per-category aggregation across the full public catalogue — both fall out of running the existing engine over a spend distribution; Phase 4, where the affiliate-neutrality question (brief §13) must be answered first.

## 3. Pass/fail bar (the point of the MVP)

Over **30 real physical checkouts**:

1. **Category prediction accuracy ≥ 85%** — predicted rewards category confirmed correct against posted statements.
2. **Arithmetic correctness = 100%** — posted rewards match catalogue math on every transaction where the category was right.

Ground truth = card statements, confirmed via the weekly reconcile ritual. Every miss is logged and classified (§6).

- **Pass** → build toward the public Canadian catalogue (Phase 2).
- **Fail on #1** → the Merchant Truth Graph is re-promoted; category prediction was the weak link.
- **Fail on #2** → catalogue encoding/maintenance is the weak link; fix before anything else.

Precondition holding true at design time: no active welcome bonuses or minimum-spend requirements in the wallet, so the v1 engine can omit bonus valuation without polluting the experiment.

## 4. Scope

### Base scope

- SwiftUI iPhone app, local-only (SwiftData), no accounts, no network dependency beyond MapKit
- One-time location fix → MapKit nearby POI → ranked merchant confirm list
- **Manual merchant search fallback** (also an Apple requirement when location is declined — guideline 5.1.1)
- 10-card wallet loaded from a **catalogue-shaped JSON seed** (same schema a public catalogue would use); editable point valuations
- Deterministic engine v1 (§5)
- Recommendation screen: winner, $ value, confidence, plain-language why, runner-up + delta
- **Near-zero-friction amount capture** (preset chips / rough slider; skippable with merchant-type estimate) — the value-recovered counter depends on it
- Immutable prediction log (original prediction never mutated by corrections)
- **Weekly reconcile ritual**: batch-confirm unconfirmed predictions against issuer apps/statements in one five-minute session
- Metrics screen: live experiment dashboard — prediction accuracy %, arithmetic match %, misses by class, value-recovered counter
- **Export + rule freshness**: one-tap JSON/CSV export of all data; every recommendation shows "rules verified <date>" (this is the Bill C-36 posture — portability, deletion, explainability — as UI)
- Unit tests for engine rules and edge cases

### Accepted add-ons (all four)

1. **Instant repeats** — home screen lists confirmed merchants by proximity; one tap, sub-second answer, no location fix. Full detection flow runs only at novel merchants. Kills checkout friction; seeds the exception-engine future.
2. **Wallet Report Card** — generated at onboarding: best card per category + "defaulting to your [default card] costs you ~$X per $1,000 of spend." The knowledge-gap aha; doubles as the future demand-test artifact (shareable web version in Phase 2).
3. **Fork view** — when category confidence is low, show both branches ("grocery → Cobalt $7.50 / convenience → Rogers $2.40"). One tap after posting confirms which branch was right → becomes a confirmed observation → merchant graduates to instant repeat. Uncertainty as honest feature + MTG cold-start loop at n=1.
4. **Action Button intent** — one App Intent ("best card here") bound to the Action Button, jumping straight to the merchant list. Sample velocity: faster invocation → 30 checkouts sooner.

### Explicitly cut from v1 (deferred, not deleted)

Goal modes · targeted offers · statement credits · insurance/protection valuation · welcome-bonus valuation (no active bonuses; re-add a crude "needs $N by date D" boost when one exists) · uncertainty *penalty* in scoring (confidence is displayed, not scored) · online purchases (physical checkouts only; online coding is a different flow — Phase 3 share extension) · receipt OCR · Live Activities · bank feeds (destroys the privacy posture) · ML anything (the engine's power is its auditability) · accounts, billing, crowdsourcing — all per the brief's exclusions.

**v1.5 candidate:** redemption logging — record points spent and cash value received on each redemption, compute the owner's *realized* cents-per-point, and let it replace the declared guess. This is the valuation analogue of the merchant confirmation loop: learn the number instead of borrowing an opinion from a rewards blog.

**v1.5 candidate:** statement CSV import — auto-match imported rows to predictions by date/amount to automate most of the weekly reconcile. No API or entitlement needed, privacy-clean. (Apple Wallet transaction access was investigated and is closed: FinanceKit covers only Apple Card/Cash/Savings, US-only, as of Jan 2026 — re-check WWDC 2025/26.)

## 5. Engine v1 — ✅ BUILT (branch `engine-v1`, 34 tests green, 2026-08-15)

Implemented as a standalone SPM package in `Engine/`: `SeedLoader` → `RuleMatcher` → `CapMath` → `Scorer` → `RecommendationEngine` → `RecommendationExplainer`. Zero dependencies, no UI/MapKit/SwiftData coupling. Run `cd Engine && swift test`; `--filter DemoWalkthroughTests` prints a readable day-of-checkouts walkthrough. The 12-case fixture spec is mutation-checked (perturbing the MR valuation breaks 6 assertions).


```text
expected net value (CAD)
= expected reward units × owner valuation        (cap-prorated: in-cap + post-cap split)
+ conditional redemption bonus likely to be used (Rogers 1.5× service factor — off by default)
− foreign-transaction fee
− reward-currency risk/spread haircut            (CRO ×0.8 held / ×1.0 auto-sold; CT ×0.95)
```

**Valuation-sensitivity layer.** Every card is also scored at its guaranteed cash floor (`floorNetValueCad`). When floor-ranking would pick a different card, the recommendation is flagged `valuationSensitive` and carries a `breakevenCentsPerPoint` — the declared value below which the advice flips — which the explainer surfaces as *"Assumes your points are worth 1.80¢ each. Below about 1.67¢, MBNA wins instead."* The breakeven is computed analytically and cross-validated against bisection over the real engine (`BreakevenCrossValidationTests`), because a disclosed number that disagrees with the engine's own behaviour is worse than no disclosure. The asymmetry is deliberate: the layer fires only when a points card wins *because of* an optimistic assumption, not when the conservative card already wins.

Then two gates before recommending:
1. **Acceptance gate** — cards whose network the merchant doesn't take are excluded (Costco → Mastercard only); if the default card is gated out, the counterfactual becomes the best accepted habitual card.
2. **Switch-threshold gate** — leave the default only when advantage ≥ 0.5pp **and** ≥ C$0.25 (decision #8); suppressed better cards still appear in the explanation ("marginally better, not worth the wallet dig").

- Pure function over explicit inputs; no hidden state; unit-testable. Executable spec: `Engine/Tests/CardCopilotEngineTests/Fixtures/engine-fixtures.json` (12 cases: cap proration, cap-flip, acceptance gating, plan-state exclusion, threshold suppression, drawer warning, FX net-negative).
- **Generalized cap accumulators** (dossier §5.4): each cap = id + measure (spend CAD / spend USD-equivalent) + limit + period (calendar month / calendar year / account year with owner anchor) + reset timezone (Crypto resets 00:00 UTC) + post-cap earn + proration. One mechanism covers Cobalt monthly, MBNA's five independent $50k years, Scotia's two $25k account-years, Rogers' $61k, Triangle's $12k grocery, and Crypto's UTC month — no special-case code.
- **Effective-dated rules** with `sourceType` (issuerConfirmed / ownerObserved / inferred): announced changes (Crypto FX 2026-09-01) are future records beside current ones, never overwrites.
- Rules with unresolved owner conditions (Tangerine selections unset, Crypto plan unknown) are **not scored** — the engine never guesses owner state.
- Confidence comes from the prediction source ladder (§6), displayed alongside the result and driving the fork view; it does not modify the score.
- Cap tracking exists for **measurement hygiene** (a blown Cobalt cap would otherwise create false "arithmetic misses") *and* because the cap-flip is the single highest-value recommendation a human can't make from memory.
- Valuations are owner state (decision #11), user-editable per program, with floors stored separately.

## 6. Category prediction & observation model

**Prediction source ladder (v1, descending confidence — dossier §5.6):**
1. Owner-confirmed reward result for the exact merchant location/terminal/card/channel
2. Repeated reconciled result for the same location/terminal
3. Issuer-specific known merchant override
4. Network MCC observed on the owner's own posted transaction
5. Brand/location seed prior + MapKit POI category
6. MapKit POI category alone
7. Unknown → default card

**Verified (dossier §2.5):** MapKit alone cannot clear the 85% bar — it has no convenience-store category and can't distinguish pump vs. kiosk vs. car wash at a gas station. And there is **no public Canadian MCC lookup** (§2.4): Visa/Mastercard/Amex tools cannot resolve a Canadian terminal's MCC. Consequences: the brand seed is **trimmed to high-confidence priors only** (CT-family banners, Costco network/coding, owner-known recurring merchants — dossier §6.3) rather than a speculative 50-chain table; Walmart, gas kiosks, and mixed venues stay probabilistic and route to the fork view; and the owner's reconciled outcomes are the *only* source that can promote a merchant to "verified" — a terminal-level override, never a brand-wide one. Merchant evidence carries expiry/decay because processors change.

**Miss taxonomy (picker in the reconcile flow):**
- Wrong category predicted
- Cap exceeded (engine knew, or didn't)
- Catalogue rule wrong/stale
- Processor weirdness (Square/PayPal/hotel terminal coding)
- Network not accepted (paid with runner-up)

**Immutability rule:** corrections create observations; they never rewrite predictions. Accuracy is measured against what the app actually said at the time.

## 7. Data model (v1 subset of the brief's entities)

`Card` · `RewardProgram` · `RewardRule` (with `effectiveFrom`/`effectiveTo`/`lastVerifiedAt`/source) · `SpendingCap` · `PointValuation` · `Merchant` (brand / location / MapKit id / parent venue) · `MerchantCategoryPrediction` · `MerchantObservation` (source, channel, network, date, confidence) · `Recommendation` + `RecommendationCandidate` (immutable snapshot of inputs, scores, and winner)

Deferred entities: `UserGoal`, `Offer`.

Internal boundaries as per brief §10: `MerchantProvider`, `CardRepository`, `MerchantKnowledgeRepository`, `RecommendationEngine`, `RecommendationExplainer`, `ObservationRecorder`.

## 8. Screens (v1)

1. **Home** — instant repeats (confirmed merchants by proximity) + "somewhere new" detection button + value-recovered counter
2. **Merchant confirm** — ranked nearby list / manual search
3. **Recommendation** — winner, $, confidence, why, runner-up; fork view variant when confidence is low; amount capture chips
4. **Weekly reconcile** — unconfirmed predictions, batch confirm/correct with miss-class picker
5. **Experiment dashboard** — the two metrics, miss breakdown, progress to 30
6. **Wallet Report Card** — generated at onboarding, revisitable
7. **Wallet & settings** — card picker (from seed catalogue), valuations, default-card designation, export

## 9. Constraints & open items

**Regulatory/platform (verified 2026-08-15):** recommendation-only = no FCAC/securities/RPAA licensing in Canada (RPAA fires only if the app ever initiates/intercepts payments). Apple 5.1.1(ix): **incorporate and submit under an organization account before public release**; review notes must state no trading/investing/money management. Quebec Law 25: location off-by-default with express consent; Bill 96 likely means French UI if serving Quebec. Build to PIPEDA; design for deletion/portability/explainability (Bill C-36 pending).

**Open items** *(research phase closed 2026-08-15 — dossier at `docs/research/canadian-card-copilot-research-2026-08-15.md`; seed catalogue at `Engine/Sources/CardCopilotEngine/Resources/card-catalogue.json`)*:
- [x] Card rules, caps, fees, effective dates — verified and seeded (10 cards)
- [x] Point valuations — locked (decision #11) and seeded in owner-state.json
- [x] Default card — Wealthsimple VIP; Triangle = drawer; Crypto conditional on Level Up Pro
- [x] FinanceKit — confirmed closed for Canada through WWDC 2026 (§2.6); reconciliation path is manual + CSV/QFX adapters (v1.5)
- [x] Brand seed — trimmed to high-confidence priors per dossier §6.3 (no speculative 50-chain table)
- [ ] **Onboarding owner-state inputs (Zubair):** Tangerine selected categories + third-category status; Rogers eligible service linked? + account anniversary month; Crypto Level Up Pro active? + CRO auto-sell vs hold; Scotia account-year anchor month; current-year cap progress estimates for Cobalt/Scotia/Rogers/Triangle/MBNA
- [ ] **Owner validation checklist (dossier §7):** one redacted per-transaction reward sample per issuer — required before trusting reconciliation for MBNA, Scotia, Tangerine, CTFS (visibility `unknown`)
- [ ] CardPointers 10-card in-app audit (the only way to get a defensible n/10 coverage count)
- [ ] Per-transaction reward visibility is strong for Amex/Rogers/Wealthsimple/Crypto and unknown for the rest — 30-checkout experiment should weight recommendations toward verifiable cards where ties allow

## 10. How MVP pieces become the public product

| MVP piece | Phase 2+ descendant |
|---|---|
| Catalogue-shaped JSON seed | Curated Canadian card catalogue with remote versioned updates |
| Brand seed table + personal observations | Merchant Truth Graph with anonymous crowdsourced observations |
| Wallet Report Card | Shareable "audit my wallet" web flow — the demand test |
| Fork view confirmations | Community verification loop with corroboration counts |
| Instant repeats | Exception engine: passive defaults, interrupt only when the default is wrong |
| Value-recovered counter | North-star metric: verified incremental value per active user |
