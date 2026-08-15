# Research Assignments — Canadian Card Copilot

**Date:** 2026-08-15
**Owner:** Zubair
**Purpose:** Everything needed before the seed catalogue and engine v1 can be built with real data. Fill in place; Claude converts §1 into the JSON seed catalogue and §3 into engine defaults.

---

## 1. Card rules collection (→ seed catalogue)

For **each card**, capture the fields below from the **issuer's official pages** (cardmember agreement / benefits page / rates-and-fees disclosure — not blogs). Record the URL and the date you checked; rules change and the catalogue schema tracks `lastVerifiedAt` per rule.

### Fields per card

| Field | What to capture |
|---|---|
| Official card name & network | Exact variant (e.g., "World Elite" vs "World") |
| Annual fee | For context; not scored in v1 |
| FX fee | % on foreign-currency transactions (engine input) |
| Base earn rate | Rate on "everything else" |
| Accelerated categories | Each category **as the issuer words it**, its rate, and exclusions verbatim (exclusions are where predictions die) |
| Caps | Per category: cap amount, whether it's a spend cap or points cap, period (monthly/annual), and the post-cap rate |
| Point program & redemption options | Program name; redemption paths and their cent-per-point values |
| Per-transaction reward visibility | Does the issuer app or statement show points/cashback **per transaction**? (yes/no + where) — this determines reconcile feasibility per card |
| Source URLs + date checked | One per claim if they differ |
| Known upcoming changes | Any announced devaluations/changes with effective dates |

### Worked example — Amex Cobalt ⚠ ALL VALUES UNVERIFIED — confirm/correct every line

- **Network:** Amex · **Annual fee:** $155.88 ($12.99/mo) · **FX fee:** 2.5%
- **Earn:** 5x "eats & drinks" (restaurants, groceries, food delivery — confirm exact wording + exclusions); 3x streaming subscriptions (confirm eligible list); 2x gas, transit, travel; 1x other
- **Cap:** 5x capped at $2,500/month spend (→ $30k/yr), then 1x (confirm mechanism and reset day)
- **Program:** Membership Rewards (confirm: Cobalt earns MR or MR-Select? affects transfer partners)
- **Per-transaction visibility:** Amex app shows points per transaction (confirm)
- **Source:** _url + date_

### Cards to complete (with known gotchas to check — gotchas are questions, not facts)

1. **Amex Platinum** — dining/travel multipliers; Canadian Platinum differs from US
2. **Amex Cobalt** — verify the worked example above
3. **Marriott Bonvoy Amex** — Marriott-spend rate vs everywhere-else rate
4. **MBNA Rewards World Elite MC** — which categories get the top rate; annual cap per category and whether it's spend or points
5. **Scotiabank Momentum Visa Infinite** — grocery/recurring-bill definitions; whether Costco/Walmart qualify as grocery; combined vs per-category annual cap
6. **Tangerine Money-Back World MC** — how many chosen categories (2 vs 3 with savings account); base rate on everything else
7. **Rogers Red World Elite MC** — base rate; USD-purchase treatment (does the elevated USD rate net out the FX fee?); any Rogers-bill multiplier
8. **Triangle World Elite MC** — CT-store rate; grocery rate, its annual cap, and exclusions (Costco/Walmart?); CT gas benefit
9. **Wealthsimple Visa Infinite Privilege** — newer card: confirm everything from scratch (earn structure, fee, FX, caps)
10. **Crypto.com Royal Indigo Visa** — tier-dependent rate; paid in CRO (volatile — note how to value); any caps/staking requirements

---

## 2. Competitive & data-sourcing research (taken over from the failed agents)

For each, note the answer + source URL. "What a good answer looks like" included so you know when to stop digging.

1. **MaxRewards Canada** — Does it support Canadian cards/issuers as of now? Did "Best Card Nearby" (Live Activity, claimed v4.5.0, July 2026) ship, and does it work in Canada? *Good answer: yes/no + changelog or store-listing link.*
2. **CardPointers Canada depth** — How complete is its Canadian card catalogue (spot-check your own 10 cards), and are its recommendations merchant-level or only category-level in Canada? *Good answer: count of your 10 cards it knows + one sentence on merchant-level support.*
3. **Canadian-native competitors 2025–26** — Has creditcardGenius, Ratehub, Milesopedia, or any startup launched a "which card to USE at checkout" product (not card comparison)? *Good answer: names + links, or confident "none found."*
4. **MCC lookup for Canadian merchants** — Do the Visa Supplier Locator / Mastercard merchant lookup tools / any Amex tool return category data for Canadian merchants? Try 5 real merchants you visit. *Good answer: works/doesn't per tool, with one example each.*
5. **MapKit POI granularity** — Current `MKPointOfInterestCategory` list: can it distinguish grocery store vs convenience store vs gas-station kiosk? Any new categories in iOS 18/19? *Good answer: link to the category list + verdict on those three distinctions. This directly tests whether the 85% bar is realistic without the brand seed table.*
6. **FinanceKit expansion (WWDC 2025/2026)** — Did Apple extend transaction access beyond Apple Card/Cash/Savings, or to Canada? *Good answer: WWDC session/doc link or "still Apple-products-only, US-only." As of Jan 2026 knowledge: locked.*
7. **How rules stay current** — Any public info on how MaxRewards/CardPointers maintain card rules (manual curation vs partnerships)? *Good answer: even anecdotal (interviews, job postings) is fine — this sizes the maintenance grind.*
8. **Statement CSV formats** — For your issuers (Amex, MBNA, Scotia, Tangerine, Rogers Bank, CTFS, Wealthsimple, Crypto.com): does the app/site export transaction CSV/OFX, and does any export include points earned per transaction? *Good answer: per issuer yes/no. Feeds the v1.5 CSV-import reconcile idea.*

---

## 3. Point valuations (→ engine defaults)

For each non-cash program, set **your** cent-per-point valuation and note the basis (redemption path you'd realistically use):

- Membership Rewards (Amex): ___ ¢/pt — basis: ___
- Marriott Bonvoy: ___ ¢/pt — basis: ___
- MBNA Rewards: ___ ¢/pt — basis: ___
- CT Money: 1:1 cash at Canadian Tire (confirm)
- CRO cashback (Crypto.com): ___ — note volatility handling
- Cash-back cards (Momentum, Tangerine, Rogers, Wealthsimple): 1:1 unless redemption restrictions say otherwise (check Rogers redemption rules)

---

## 4. Two one-tap decisions while you're at it

- **Default card** (baseline for the value-recovered counter — "the card you'd habitually tap"): ___
- Any card you'd **exclude from daily carry** (engine can skip it): ___
