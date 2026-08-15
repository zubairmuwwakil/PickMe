# Canadian Card Copilot — research dossier

**Owner:** Zubair  
**Research date / `lastVerifiedAt`:** 2026-08-15  
**Market:** Canada  
**Purpose:** Source-of-truth research for seed catalogue v1, engine defaults, reconciliation feasibility, and competitive/data-source decisions.

## Executive decisions

1. **Default card:** Wealthsimple Visa Infinite Privilege. Use it whenever another accepted card does not produce meaningfully more than 2% net value. This is the cleanest baseline for the “value recovered” counter.
2. **Daily-carry exclusion:** Triangle World Elite Mastercard may stay in the account catalogue but remain out of the physical wallet. Recommend it only for a known-use case (Canadian Tire-family stores, qualifying grocery, or the CT/Petro-Canada gas benefit). Rogers Red World Elite remains the Mastercard/Costco backup.
3. **Conditional exclusion:** Suppress Crypto.com Royal Indigo whenever no qualifying Level Up Pro subscription/CRO lockup is active. The physical card colour does not establish the reward rate.
4. **Catalogue design:** Store current and announced future rules as different effective-dated records. Do not overwrite today’s rule with a September 2026 or January 2027 rule.
5. **Confidence design:** Every rule needs `sourceType = issuerConfirmed | ownerObserved | inferred`. Merchant-category predictions should expose their confidence; Walmart, gas-station kiosks, payment facilitators, and mixed-use merchants cannot safely be handled by a brand-wide rule.

### Corrections that materially change v1

- Cobalt is now **$15.99/month ($191.88/year)**, not $12.99/month. Its ordinary 2× bucket is gas and transit—not generic travel. Eligible hotel/car-rental bookings through Amex Travel can separately earn one additional point.
- MBNA Rewards World Elite has **five independent $50,000 calendar-year spend caps**, one for each 5× category. It is not one shared cap.
- Scotia Momentum Visa Infinite + has a **$25,000 4% bucket cap and a separate $25,000 2% bucket cap** per account year.
- Triangle’s grocery cap is **$12,000 per calendar year**, and Walmart/Walmart Superstore/Costco are expressly excluded from the 3% grocery rate.
- Crypto.com Royal Indigo is a **prepaid Visa** whose current earning depends on Level Up plan state. The current Pro rate is 3% in CRO, but with a monthly eligible-spend/reward cap and broad MCC exclusions. It should not be modelled as a permanent card-art benefit.
- “3% on USD” at Rogers does offset the 2.5% FX fee in a narrow arithmetic sense, but only to roughly **+0.5% net reward** before exchange-rate spread. Wealthsimple’s 2% with no FX fee remains the stronger default.

## Research conventions

- All URLs were checked on **2026-08-15**.
- Issuer pages and issuer terms control card rules. Competitive/app and developer research uses first-party product pages, store listings, changelogs, or developer documentation where available.
- The exclusion lists below are **faithful structured summaries**, not a substitute for the linked agreement’s operative wording. Exact MCC numbers are retained where the issuer publishes them.
- “No public confirmation” means no issuer page reviewed explicitly showed the feature. It is not proof that a logged-in account lacks it; the owner-validation checklist at the end closes those gaps.
- Rates are rewards on net eligible purchases unless otherwise stated. Refunds/credits reverse rewards; cash advances, fees, interest, balance transfers, and cash-like transactions are generally excluded.

---

# 1. Card rules collection → seed catalogue

## 1. American Express Platinum Card

| Field | Verified rule |
|---|---|
| Official name / network | **The Platinum Card® from American Express** · American Express |
| Annual fee | **$799** primary card |
| FX fee | **2.5%** foreign-currency conversion commission |
| Base earn | **1 Membership Rewards point per $1** in Card purchases |
| Accelerated categories | **2 points per $1 on eligible dining purchases in Canada**: qualifying restaurants, quick-service restaurants, coffee shops, drinking establishments, and qualifying food delivery whose primary business matches the category. Grocery stores do not become dining. **2 points per $1 on eligible travel purchases**: qualifying air, water, rail, and road passenger transport, lodging, and tour operators. Local/commuter transportation is not in this travel bucket. |
| Category exclusions / coding | Amex relies on the merchant code submitted by the merchant or processor. Third-party processors, payment services, mobile readers, online resellers, or a merchant coded outside the eligible industry can earn only the base rate. Fees and cash-equivalent transactions do not earn. |
| Caps | No published spend cap on the ordinary 2× dining or travel buckets. |
| Program / redemption | Full **American Express Membership Rewards**. Flexible Travel and statement-credit redemptions can produce **1.0¢/point**; eligible partner transfers include Aeroplan and other airline/hotel programs and can produce higher variable value. Pay with Points at some retail partners is lower-value. |
| Per-transaction reward visibility | **Yes — owner-observed** in the Amex app/account activity after posting. The reviewed public Canadian pages explain reward management but do not make a crisp per-transaction-display promise. Store this as `ownerObserved`, not `issuerConfirmed`. |
| Upcoming changes | **2027-01-01:** announced changes to complimentary Priority Pass/Plaza Premium visit treatment. This affects benefits, not the purchase earn engine; retain as a future benefit rule rather than changing current checkout scoring. |

**Official sources:** [card product and fee](https://www.americanexpress.com/en-ca/charge-cards/the-platinum-card/), [Membership Rewards earn rules](https://www.americanexpress.com/en-ca/benefits/membership-rewards/the-platinum-card/), [card benefits](https://www.americanexpress.com/en-ca/benefits/the-platinum-card/), [travel and lounge benefits](https://www.americanexpress.com/en-ca/benefits/travel/the-platinum-card/), [foreign-currency explanation](https://www.americanexpress.com/en-ca/customer-service/payments-and-billings/faq.exchange-rates.html). Checked 2026-08-15.

**Seed note:** Keep `dining.country = CA`. Do not reuse the US Platinum earn model.

## 2. American Express Cobalt Card

| Field | Verified rule |
|---|---|
| Official name / network | **American Express® Cobalt Card** · American Express |
| Annual fee | **$15.99/month = $191.88/year** |
| FX fee | **2.5%** |
| Base earn | **1 Membership Rewards point per $1** |
| 5× category | **Eligible eats and drinks in Canada**: qualifying restaurants, quick-service restaurants, coffee shops, drinking establishments, standalone grocery stores, and qualifying food/grocery delivery services whose primary business is eligible. |
| 3× category | **Eligible streaming subscriptions in Canada** from participating services on Amex’s current streaming list. A bundle or charge routed through a third-party digital platform, cable/telco/internet provider, or another intermediary may not qualify. |
| 2× categories | **Eligible standalone gas-station purchases in Canada** and **eligible local commuter transportation in Canada**, including qualifying subway, streetcar, taxi, limousine, and rideshare purchases. This is not a generic travel category. |
| Amex Travel add-on | An eligible prepaid hotel or car-rental purchase through Amex Travel can receive **one additional point per $1**, producing two total points when the underlying purchase otherwise earns one. Model this as a channel-specific bonus, not a broad 2× travel rule. |
| Coding exclusions | Merchant/processor coding controls. Third-party payment services, aggregators, mobile readers, online resellers, and mixed merchants can fall to 1×. |
| Caps | The 5× eats/drinks bucket has a **combined $2,500 net-purchase spend cap per calendar month**. After the cap, eligible purchases earn **1×**. Reset is the first day of each calendar month; posted net purchases drive the cap, and later returns/credits do not create new 5× room in that month. No published cap on the standard 3× or 2× buckets. |
| Program / redemption | Full **Membership Rewards**, not a restricted “MR Select” balance. Use the same redemption/transfer paths as other transferable Canadian MR cards. |
| Per-transaction reward visibility | **Yes — owner-observed** in Amex app/account activity. |
| Upcoming changes | None found on the reviewed official earn/fee pages. |

**Official sources:** [card product, fee, and headline earn](https://www.americanexpress.com/en-ca/credit-cards/cobalt-card/), [detailed benefit and category terms](https://www.americanexpress.com/ca/en/benefits/cobalt-card/), [foreign-currency explanation](https://www.americanexpress.com/en-ca/customer-service/payments-and-billings/faq.exchange-rates.html). Checked 2026-08-15.

**Worked-example verdict:** Network and FX were correct; annual fee was stale; 5×/3×/2× needed the coding and Canada restrictions above; generic travel should be removed; the 5× cap is a monthly **spend** cap; the card earns full Membership Rewards.

## 3. Marriott Bonvoy American Express Card

| Field | Verified rule |
|---|---|
| Official name / network | **Marriott Bonvoy® American Express® Card** · American Express |
| Annual fee | **$120** |
| FX fee | **2.5%** |
| Base earn | **2 Marriott Bonvoy points per $1** |
| Accelerated category | **5 Marriott Bonvoy points per $1** on eligible purchases charged directly by participating Marriott Bonvoy properties, eligible standalone Marriott retail locations, and qualifying Marriott-owned/managed branded online stores or gift-card channels. |
| Exclusions / coding | A hotel-adjacent merchant, third-party booking agency, processor, event operator, restaurant, or concession can code separately and earn 2×. Merchant coding controls. Cash-like items, fees, interest, balance transfers, Amex cheques, travellers cheques, and foreign-currency purchases as a cash-equivalent product do not earn. |
| Caps | No published spend cap on the standard 5× Marriott or 2× base earn. |
| Program / redemption | **Marriott Bonvoy**. Primary use is variable-price hotel award nights; points can also transfer to airline programs, usually at a weaker ratio than direct flexible-bank points. There is no fixed Canadian cent-per-point guarantee. |
| Per-transaction reward visibility | **Yes — owner-observed** in Amex activity. The Marriott transfer into the Bonvoy account can lag the Amex transaction display. |
| Upcoming changes | None found on reviewed official card pages. |

**Official sources:** [card, fee, and earn](https://www.americanexpress.com/en-ca/credit-cards/marriott-bonvoy-card/), [Amex detailed Marriott earn explanation](https://www.americanexpress.com/en-ca/services/ways-to-pay/recurring-bills/), [Marriott hotel redemptions](https://www.marriott.com/loyalty/redeem/hotels.mi), [points-to-miles options](https://www.marriott.com/loyalty/redeem/travel/points-to-miles.mi). Checked 2026-08-15.

## 4. MBNA Rewards World Elite Mastercard

| Field | Verified rule |
|---|---|
| Official name / network | **MBNA Rewards World Elite® Mastercard®** · Mastercard World Elite |
| Annual fee | **$120** primary; **$50** additional card |
| FX fee | **2.5%** |
| Base earn | **1 MBNA Rewards point per $1** |
| Accelerated categories | **5 points per $1** in each of: restaurant purchases; grocery purchases; digital media purchases; membership purchases; and household utility purchases. |
| Issuer-published MCCs | Restaurants: **5812, 5814**. Grocery: **5411, 5462, 5499**. Digital media: **5968, 5815, 5816**. Memberships: **7997, 8699**. Household utilities: **4814, 4899, 4900**. |
| Coding / overlap rules | MBNA determines category eligibility from network coding. If one transaction appears to match multiple categories, it earns one accelerated rate, not stacked category multipliers. Cash-like transactions, fees, interest, adjustments, refunds, and rebates are excluded/reversing. |
| Caps | **Five separate spend caps:** up to **$50,000 of net purchases per category per calendar year** (January 1–December 31). After a category’s cap, further spend in that category earns **1×**. This is not a points cap and not one shared $50,000 cap. |
| Other points | Birthday bonus equals 10% of points earned in the preceding 12 months, to a maximum **15,000 points** under the program terms. Keep separate from transaction recommendation value unless the engine intentionally models marginal contribution to that bonus. |
| Program / redemption | **MBNA Rewards**. Travel: **100 points = $1 (1.0¢/point)**. Cash/charitable redemption: **120 points = $1 (0.833¢/point)**, with the published minimum. Gift cards/merchandise are variable. |
| Per-transaction reward visibility | **Not publicly confirmed.** Public account pages expose balance/history and statements, but the reviewed issuer material does not promise points earned beside each transaction. Treat reconciliation as `unknown` until an owner screenshot/export confirms it. |
| Upcoming changes | None found in reviewed official reward terms. |

**Official sources:** [product, fee, and headline earn](https://www.mbna.ca/en/credit-cards/rewards/mbna-rewards-world-elite-mastercard), [MBNA Rewards program terms PDF](https://www.mbna.ca/content/dam/mbna/document/pdf/credit-cards/mbna-rewards-0322-en.pdf), [MBNA account agreement PDF](https://www.mbna.ca/content/dam/mbna/document/pdf/credit-cards/mbna-acct-agreement-0322-en.pdf). Checked 2026-08-15.

## 5. Scotiabank Momentum Visa Infinite + Card

| Field | Verified rule |
|---|---|
| Official name / network | **Scotia Momentum® Visa Infinite + Card** · Visa Infinite + |
| Annual fee | **$120** primary; **$50** supplementary |
| FX fee | **2.5%** |
| Base earn | **1% cash back** |
| 4% category | **Grocery store purchases** identified under Visa MCC **5411**, plus **recurring payments** carrying the network recurring-payment indicator. Typical recurring charges may include qualifying telecom, insurance, membership, and subscription payments, but a merchant’s frequency alone does not make it recurring: the submitted transaction flag controls. |
| 2% categories | **Gas stations (5541/5542), EV charging (5552), daily transit/rideshare** under the published transit MCC set (**4111, 4112, 4121, 4131, 4789**), and selected food-delivery purchases. |
| Brand gotchas | **Costco is not a grocery-store purchase for this rule.** Walmart is not safely hard-coded either way: only a specific location/terminal submitted as MCC 5411 qualifies. Store a learned terminal/location rule, never a nationwide Walmart override. |
| Caps | **Separate spend caps:** first **$25,000** in the 4% bucket per account year, then 1%; and first **$25,000** in the 2% bucket per account year, then 1%. The account year resets every 12 months in the statement period tied to the account-opening month—not January 1 unless those happen to coincide. |
| Redemption | Cash back may be redeemed in increments subject to a **$25 minimum**, through supported Scotia channels, as a statement credit or to an eligible Scotia deposit account. Value is 1:1 CAD. |
| Per-transaction reward visibility | **No public issuer confirmation found.** The terms describe accumulated cash back and redemption, not a transaction-by-transaction reward field. Mark `unknown/likely statement-level` until owner validation. |
| Upcoming changes | The cited earn terms are effective **2026-02-01**; no later announced earn change found. |

**Official sources:** [product, fee, and rates](https://www.scotiabank.com/ca/en/personal/credit-cards/visa/momentum-infinite-card.html), [detailed Momentum terms effective 2026-02-01](https://www.scotiabank.com/ca/en/personal/credit-cards/visa/momentum-infinite-card/welcome-kit/terms-conditions-momentum-infinite.html). Checked 2026-08-15.

## 6. Tangerine Money-Back World Mastercard

| Field | Verified rule |
|---|---|
| Official name / network | **Tangerine Money-Back World Mastercard®** · Mastercard World |
| Annual fee | **$0** |
| FX fee | **2.5%** |
| Base earn | **0.5% cash back** on other eligible purchases |
| Accelerated categories | **2% unlimited cash back** in **two selected Money-Back Categories**; a **third selected category** is available when Money-Back Rewards are deposited into a Tangerine Savings Account. Rewards are paid monthly. |
| Category changes | Selected categories may be changed subject to Tangerine’s published **90-day** change timing. The engine needs user-state fields for the currently active selections and their next-effective date. |
| Current published categories / MCC logic | Drug Store (including 5912/5122); Eating Places (5812/5813/5814); Entertainment; Furniture; Gas (5541/5542); Grocery (5411/5462); Home Improvement; Hotel/Motel; Public Transportation/Parking; Recurring Bill Payments; Fitness/Sports; E-Games; and Foreign Currency. Use the issuer MCC page for the full current code set. |
| Overlap / coding | A transaction earns one 2% category rate, not multiple. Tangerine’s rules determine precedence when a recurring payment also belongs to another selected category. Merchant/network coding controls. |
| Caps | No published spend cap on the selected 2% categories. |
| Foreign-currency gotcha | Selecting Foreign Currency yields 2% cash back but the card still charges 2.5% FX, so the simple net is roughly **−0.5%** versus the network-converted CAD amount. It is not a no-FX substitute. |
| Redemption | Automatic monthly cash back to the card account or, when chosen, to an eligible Tangerine Savings Account; 1:1 CAD. The Savings destination is also what unlocks the third category. |
| Per-transaction reward visibility | **Not publicly confirmed.** Treat the account’s displayed transaction category as useful evidence if present, but do not assume an export contains per-transaction dollars earned. |
| Upcoming changes | No announced change found after the issuer’s current category/MCC page dated 2025-10-28. |

**Official sources:** [World card product](https://www.tangerine.ca/en/personal/spend/credit-cards/world-credit-card), [card comparison and two/three-category mechanics](https://www.tangerine.ca/en/personal/spend/credit-cards/money-back-credit-card), [Money-Back category and MCC definitions](https://www.tangerine.ca/en/personal/spend/credit-cards/merchant-category-codes). Checked 2026-08-15.

## 7. Rogers Red World Elite Mastercard

| Field | Verified rule |
|---|---|
| Official name / network | **Rogers Red World Elite® Mastercard®** · Mastercard World Elite |
| Annual fee | **$0** |
| FX fee | **2.5%** |
| Base earn without eligible service | **1.5% cash back** on eligible purchases |
| Base earn with eligible service | **2% cash back** when the cardholder has an eligible linked Rogers, Fido, Shaw, or Comwave service under the current terms. |
| USD purchases | **3% cash back** on eligible purchases made in U.S. dollars, calculated after conversion to Canadian dollars. The 2.5% FX fee still applies. Approximate reward after the FX fee is therefore **+0.5%**, before any network conversion spread. |
| Annual cap | The enhanced earn structure applies to the first **$61,000 of eligible net purchases per account year**. After the limit, eligible purchases earn **1.5%** until the account/product anniversary reset. |
| Rogers-bill treatment | The card does not need a separate higher Rogers-bill earn multiplier to reach the advertised value. Instead, when cash back is redeemed against an eligible Rogers/Fido/Shaw/Comwave/Sportsnet+ transaction identified in the app, the redemption receives a **1.5× value boost**. Thus 2% earned can become 3% effective value on that redemption. Model this as a redemption factor, not an earn category. |
| Redemption | Minimum **$10**; redeem through the app/online against eligible purchases within the published recent-purchase window (90 days) or use the annual statement-credit process. Rewards remain 1:1 CAD except for the eligible 1.5× service redemption. |
| Per-transaction reward visibility | **Yes — issuer-confirmed.** App: Rewards → Earned Rewards History; web: Accumulation Details after transactions post. |
| Upcoming changes | No announced earn change found in reviewed current terms. |

**Official sources:** [card details](https://www.rogersbank.com/en/rogers_red_worldelite_mastercard_details), [current annual-value terms and $61,000 limit](https://www.rogersbank.com/en/Rogers-Red-Annual-Value), [rewards earning/history/redemption](https://www.rogersbank.com/en/rewards). Checked 2026-08-15.

**Engine comparison:** For a USD purchase, Wealthsimple produces about **2% net** with no FX; Rogers produces about **0.5% net** after its fee. Rogers still matters where Mastercard acceptance is required and Wealthsimple/Visa is not accepted.

## 8. Triangle World Elite Mastercard

| Field | Verified rule |
|---|---|
| Official name / network | **Triangle® World Elite® Mastercard®** · Mastercard World Elite |
| Annual fee | **$0** |
| FX fee | **2.5%** |
| Base earn | **1% in Canadian Tire Money (CT Money)** on other eligible purchases |
| Canadian Tire-family rate | **4% in CT Money** on qualifying purchases at participating Canadian Tire-family banners, calculated on the qualifying **pre-tax** purchase amount. Current page lists Canadian Tire, Sport Chek, Mark’s/L’Équipeur, Party City, Atmosphere, Pro Hockey Life, Sports Rousseau, Hockey Experts/L’Entrepôt du Hockey, and participating Sports Experts, subject to exclusions such as gift cards and certain products. |
| Grocery | **3% in CT Money** at merchants coded grocery store (MCC 5411), on the first **$12,000 of eligible grocery spend per calendar year**. Walmart, Walmart Superstore, and Costco are expressly excluded even if a transaction might otherwise appear grocery-like. After the cap: **1%**. |
| Gas benefit | At participating Gas+/Essence+ and Petro-Canada locations, the current benefit is **7¢ per litre** on qualifying premium fuel and **5¢ per litre** on other qualifying fuel, subject to whole-litre and location/program terms. Treat as cents-per-litre, not a spend percentage. |
| Redemption | CT Money is a closed-loop dollar balance: **CT$1 = C$1** when redeemed at participating Canadian Tire-family stores. It is not cash and should not be represented as 1¢ per point. |
| Per-transaction reward visibility | **Partial / owner validation required.** The Triangle app exposes transactions and CT Money balance/activity, but reviewed public material does not clearly promise exact CT Money earned beside every card transaction. |
| Upcoming changes | No later announced earn change found; the product page’s current information is stated effective 2025-03-26. |

**Official source:** [Triangle World Elite product, rates, caps, exclusions, FX, and fuel benefit](https://triangle.canadiantire.ca/en/credit-cards/triangle-world-elite-mastercard.html). Checked 2026-08-15.

## 9. Wealthsimple Visa Infinite Privilege Credit Card

| Field | Verified rule |
|---|---|
| Official name / network | **Wealthsimple Visa Infinite Privilege Credit Card** · Visa Infinite Privilege |
| Fee | **$20/month ($240/year)** when not waived. Waived with at least **$100,000 in qualifying individual Wealthsimple assets** or a qualifying **$4,000/month direct deposit**, under current terms. Quebec billing is presented annually. |
| FX fee | **0%** foreign-transaction fee |
| Earn | **2% cash back on unlimited eligible purchases**. No accelerated merchant categories and no published spend cap. |
| Exclusions | No rewards on cash-like transactions, refunds, fees, or adjustments. The issuer’s cash-like examples include wires, money orders, account funding, gaming chips, stored-value/prepaid products, and certain tradable valuables. “Foreign currency purchase” in the cash-like list refers to buying currency/cash equivalents, not an ordinary foreign-currency retail transaction. |
| Redemption | Manual redemption to most eligible Wealthsimple accounts, with no published minimum or frequency limit; RESP, RRIF, and spousal RRIF destinations are excluded. Cash back is not directly applied to the credit-card balance. Value is 1:1 CAD. |
| Per-transaction reward visibility | **Yes — issuer-confirmed.** Posted activity detail shows cash back for the transaction. |
| Upcoming changes | No announced earn/FX change found. The reward help article reviewed was updated 2026-08-13. |

**Official sources:** [card product, rate, fee/waiver, and no-FX](https://www.wealthsimple.com/en-ca/credit-card), [application and product details](https://help.wealthsimple.com/hc/en-ca/articles/31614256039835-Apply-for-a-Wealthsimple-credit-card), [cash-back earning, exclusions, and redemption](https://help.wealthsimple.com/hc/en-ca/articles/37750003281563-Earn-cash-back-with-your-credit-card). Checked 2026-08-15.

**Owner-specific role:** This is the default card for foreign currency, random retail/online spend, travel, and situations where an Amex card is not accepted, unless another accepted card clears the engine’s “meaningfully better” threshold.

## 10. Crypto.com Royal Indigo Visa

| Field | Verified rule |
|---|---|
| Official product / network | **Crypto.com Prepaid Visa Card — Royal Indigo card art** · Visa prepaid, issued in Canada by Digital Commerce Bank. It is not a revolving credit card. |
| Annual fee / qualification | No conventional credit-card annual fee should be used for ranking. Current **Level Up Pro** economics are instead **C$39.99/month**, **C$399.90/year**, or a qualifying **C$6,500 12-month CRO lockup/stake**, depending on chosen path and current availability. |
| Current FX | **0% foreign-currency fee** under current Canadian terms. |
| Current earn when Pro is active | **3% back in CRO** on eligible purchases. Rewards are credited in CRO after the eligible transaction. Royal Indigo card art alone does not prove Pro is active. Basic/no active qualifying plan means no card rewards/benefits under current Level Up rules. |
| Cap | Official help terms specify **US$2,500-equivalent eligible purchase spend per calendar month** for Pro, resetting at **00:00 UTC on day 1**; post-cap rate is **0%**. The Canada marketing page labels the monthly reward cap as **$75**. Since 3% × US$2,500 = US$75 while the Canadian page visually uses Canadian pricing elsewhere, store the spend cap and source currency explicitly and flag the marketing-page currency ambiguity for issuer review. |
| Major MCC exclusions | Issuer help currently excludes rewards for, among others: wire transfer **4829**; utilities **4900**; software **5734**; gift/novelty/souvenir **5947**; financial/account funding/crypto/money-order categories **6012/6051**; securities **6211**; insurance **6300**; rent/real estate **6513**; payment transactions **6532**; stored value **6540**; programming/web/data **7372**; professional services **8999**; fines **9222**; taxes **9311**; and other government services **9399**. Restricted markets and channel-specific restrictions also apply. |
| Subscription rebates | Under current help terms, Pro rebates for selected services are time-limited and depend on qualification path; monthly subscribers do not receive the same rebate treatment as annual subscribers/eligible CRO lockups. Keep rebates outside checkout earn scoring. |
| Redemption / valuation | Not points. The reward is a percentage of spend paid as a quantity of CRO at the issuer’s conversion time. Record both `rewardCadAtIssue` and `croQuantity`. Use **1.00× face value** only when promptly converted to CAD; use a risk haircut when CRO is held. |
| Per-transaction reward visibility | **Yes — issuer-confirmed.** Eligible purchase reward appears as a separate CRO credit shortly after the transaction. Reconciliation may need a join between Card transaction CSV and Crypto Wallet/Token transaction CSV. |
| Announced 2026-09-01 changes | In Canada, current help pages announce **0% FX only on the first C$1,400 of foreign-currency spend per calendar month, then 2.0%**. The Pro Priority Pass allocation is also scheduled to fall from four visits to two; lounge treatment is not a purchase-engine rule. Store both as future records. |

**Official sources:** [current Canadian card/Level Up page](https://crypto.com/ca/cards), [reward rates, plan qualification, cap/reset, and rebates](https://help.crypto.com/en/articles/2742447-crypto-com-prepaid-card-rewards-benefits), [reward exclusions and MCCs](https://help.crypto.com/en/articles/4597450-restriction-of-cro-rewards-program-and-restricted-markets-for-crypto-com-prepaid-card), [Canadian fees and limits, including announced FX change](https://help.crypto.com/en/articles/5966447-crypto-com-prepaid-visa-card-fees-and-limits-canada), [Priority Pass treatment and announced change](https://help.crypto.com/en/articles/7733288-priority-pass-airport-lounge-access). Checked 2026-08-15.

**Critical seed rule:** `cardArt = Royal Indigo` and `rewardPlan = Pro` are independent fields. Every recommendation must first evaluate `levelUpPlan.activeAt(transactionTime)`.

## 1A. Compact seed-catalogue handoff

| Card | Base | Best ordinary earn | Cap model | FX now | Per-transaction reward |
|---|---:|---:|---|---:|---|
| Amex Platinum | 1 MR/$ | 2 MR/$ dining-CA, eligible travel | none published | 2.5% | Yes, owner-observed |
| Amex Cobalt | 1 MR/$ | 5 MR/$ eats/drinks-CA | $2,500 monthly spend, then 1× | 2.5% | Yes, owner-observed |
| Marriott Bonvoy Amex | 2 Bonvoy/$ | 5 Bonvoy/$ eligible Marriott-direct | none published | 2.5% | Yes, owner-observed |
| MBNA Rewards WE | 1 MBNA/$ | 5 MBNA/$ in five categories | five separate $50k calendar-year spend caps, then 1× | 2.5% | Unknown |
| Scotia Momentum VI+ | 1% | 4% grocery/recurring; 2% gas/EV/transit/selected delivery | separate $25k account-year spend caps, then 1% | 2.5% | Unknown |
| Tangerine World | 0.5% | 2% in 2 or 3 selected categories | unlimited | 2.5% | Unknown |
| Rogers Red WE | 1.5% or 2% | 3% USD; 1.5× eligible service redemption | $61k account-year spend, then 1.5% | 2.5% | Yes, issuer-confirmed |
| Triangle WE | 1% CT Money | 4% CT-family; 3% grocery | grocery $12k calendar-year spend, then 1% | 2.5% | Partial/unknown |
| Wealthsimple VIP | 2% | 2% everywhere eligible | unlimited | 0% | Yes, issuer-confirmed |
| Crypto.com Royal Indigo / Pro | 0% if inactive | 3% CRO if active Pro | US$2,500-equiv monthly eligible spend, then 0% | 0% now | Yes, issuer-confirmed |

---

# 2. Competitive and data-sourcing research

## 2.1 MaxRewards Canada

**Answer:** Canadian issuer/card support is **not currently production-ready**. The company’s Canadian App Store listing exists, but its public request to add Canadian credit cards remains open. **Best Card Nearby did ship** in MaxRewards v4.5.0 on **2026-07-14**, including a location-powered Live Activity. The feature therefore exists, but without Canadian cards/bank support it is not a usable Canadian answer for this ten-card wallet.

Sources: [Canadian App Store listing](https://apps.apple.com/ca/app/maxrewards-credit-card-rewards/id1435710443), [open Canadian-card support request](https://feedback.maxrewards.com/feature-requests/p/add-support-for-canadian-credit-cards), [v4.5.0 changelog — Best Card Nearby](https://feedback.maxrewards.com/changelog/maxrewards-v450). Checked 2026-08-15.

## 2.2 CardPointers Canadian depth

**Answer:** CardPointers publicly claims support across Canada and other markets, and its current App Store material describes merchant/location-aware “nearby stores” recommendations via AutoPilot/Live Activities. It also permits manual card creation. However, its public web catalogue does not expose a filterable Canadian list that allows an honest remote **10-card spot-check**.

- **Publicly verifiable exact count from this ten-card set:** **not determinable**; do not invent “10/10.”
- **Catalogue conclusion:** Canada is an explicitly supported country, but exact coverage—especially Wealthsimple VIP’s current variant and the plan-dependent Crypto.com product—requires a short in-app test.
- **Recommendation granularity:** The product supports merchant/location-level prompts globally (“nearby stores”), not only static categories. The accuracy/depth of Canadian merchant mapping is not publicly quantified, so Canadian merchant-level performance remains unverified.

Sources: [CardPointers product site](https://cardpointers.com/), [Canadian App Store listing](https://apps.apple.com/ca/app/cardpointers-for-credit-cards/id1472875808), [founder confirmation of Canada support](https://www.reddit.com/r/CardPointers/comments/ivap7f/support_for_canada/), [nearby-offer help](https://help.cardpointers.com/article/57-filtering-and-sorting-offers). Checked 2026-08-15.

**Required closure test:** Search all ten exact Canadian card names in the installed app and record exact-match / stale variant / manual-only. This is the only remaining way to produce the requested defensible `n/10` count.

## 2.3 Canadian-native competitors, 2025–26

**Answer:** **None found among creditcardGenius, Ratehub, Milesopedia, or another visible Canadian-native product that provides a broad “which owned card should I use at this checkout?” experience.** The named firms currently focus on card acquisition/comparison, editorial strategy, calculators, or category advice rather than real-time wallet routing. Chexy is a useful adjacent product for routing selected recurring bills/rent, but it is not a universal checkout copilot.

Representative sources: [creditcardGenius card comparison](https://creditcardgenius.ca/credit-cards), [Ratehub rewards-card comparison](https://www.ratehub.ca/credit-cards/rewards), [Milesopedia category-choice strategy](https://milesopedia.com/en/guide/strategy/choose-best-credit-card-outside-categories/). Checked 2026-08-15.

This is a market-search conclusion, not proof that no private beta exists.

## 2.4 MCC lookup for Canadian merchants

**Answer:** The public network tools do **not** provide a dependable merchant-name/location → submitted MCC lookup for Canadian consumer use.

| Tool | Canadian merchant-name MCC result | Example / verdict |
|---|---|---|
| Visa Supplier Locator | **Does not work as the former public MCC lookup.** The old locator is no longer a usable public endpoint; Visa publishes MCC standards, not a live Canadian merchant directory. | Costco, Walmart, Canadian Tire, Starbucks, and Esso cannot be resolved to the actual terminal MCC through an official public Visa lookup. |
| Mastercard merchant lookup | **No public Canadian consumer merchant-name → MCC directory found.** Mastercard exposes standards/services, not the needed terminal-category query. | Same five examples cannot be resolved to a current terminal MCC from an official public Mastercard lookup. |
| Amex Maps / merchant directory | **Finds acceptance and broad merchant category information, not the transaction MCC submitted for rewards.** | A merchant such as Starbucks may appear as accepting Amex, but the tool does not supply a reconciliable network MCC for that terminal. |

Sources: [Visa Merchant Data Standards Manual](https://usa.visa.com/dam/VCOM/download/merchants/visa-merchant-data-standards-manual.pdf), [Amex Maps Canada](https://www.americanexpress.com/en-ca/maps), [Amex Canada online merchant directory](https://www.americanexpress.com/ca/en/services/online-merchant-directory/). Checked 2026-08-15.

**Product implication:** A static brand table can be a prior, not ground truth. The highest-value data source is the owner’s posted transaction/reward outcome keyed by merchant, location/terminal, card, and channel. Let reconciliation promote a terminal-level override after sufficient evidence.

## 2.5 MapKit POI granularity

**Answer:** MapKit currently exposes distinct POI categories for **`foodMarket`**, **`gasStation`**, and generic **`store`**, but no first-class **convenience-store** category in the published `MKPointOfInterestCategory` list. A gas station POI also does not identify whether a card transaction occurred at the fuel pump, attached convenience-store register, car wash, or a third-party concession.

- Grocery vs convenience store: **not reliably distinguishable** from MapKit category alone.
- Gas station vs gas-station kiosk: **not distinguishable** at payment-terminal level.
- iOS 18 / 2025–26 additions: no published commerce-relevant category change found that closes these gaps.

Sources: [`MKPointOfInterestCategory`](https://developer.apple.com/documentation/mapkit/mkpointofinterestcategory), [`foodMarket`](https://developer.apple.com/documentation/mapkit/mkpointofinterestcategory/foodmarket), [`gasStation`](https://developer.apple.com/documentation/mapkit/mkpointofinterestcategory/gasstation), [`store`](https://developer.apple.com/documentation/mapkit/mkpointofinterestcategory/store). Checked 2026-08-15.

**85% verdict:** MapKit alone is insufficient for an 85% correct-card bar. That bar is plausible only with brand/location priors, terminal/channel overrides learned from rewards, and a confidence-aware fallback to the default card.

## 2.6 FinanceKit expansion

**Answer:** FinanceKit is **still not a general transaction-access rail for Canadian bank and card accounts**. WWDC 2024 covered Apple Card, Apple Cash, and Savings with Apple. WWDC 2025 expanded Connected Cards to the **United Kingdom** and added platform capabilities such as background delivery. The reviewed WWDC 2026 Wallet material did not announce Canadian FinanceKit account access.

Sources: [WWDC24 — What’s new in FinanceKit](https://developer.apple.com/videos/play/wwdc2024/2023/), [WWDC25 — What’s new in FinanceKit](https://developer.apple.com/videos/play/wwdc2025/201/), [WWDC26 Wallet session](https://developer.apple.com/videos/play/wwdc2026/209/). Checked 2026-08-15.

**Engine implication:** Do not plan v1 or v1.5 Canadian reconciliation around FinanceKit. CSV/QFX plus owner confirmations are the realistic near-term path.

## 2.7 How rules stay current

**Answer:** Public evidence points to a hybrid of automation, manual curation, and user correction—not a zero-maintenance issuer feed. The CardPointers founder has described the work as “Herculean,” with scripts, official bank sources where available, manual work, blogs, and user corrections. MaxRewards advertises structured data for hundreds of cards but does not publicly document a comprehensive issuer-partnership feed or maintenance methodology; its public correction/feature channels show that human-reported gaps still occur.

Sources: [CardPointers founder interview on data maintenance](https://indiedevmonday.com/issue-5), [MaxRewards product site](https://maxrewards.com/), [MaxRewards public feature requests](https://feedback.maxrewards.com/feature-requests). Checked 2026-08-15.

**Sizing implication:** Budget for continuous curation. Each rule should have an issuer URL, last verification, effective dates, an automated stale-page/change detector, and a human review queue. User reconciliation should create candidate corrections, never silently mutate global rules.

## 2.8 Statement/export formats and reward reconciliation

No reviewed issuer export specification promises a points/cash-back-earned column beside each card transaction. UI visibility and file export are separate capabilities.

| Issuer | Publicly supported export evidence | Reward per transaction in export? | v1.5 reconciliation verdict |
|---|---|---|---|
| American Express Canada | Canadian public support page did not clearly expose the format list; Amex’s official US support documents CSV/QFX/QIF/OFX-style downloads, and the Canadian logged-in site is owner-testable. | **No confirmed reward column.** | **Probable transaction export; owner-test required.** Amex UI already gives useful per-transaction reward evidence. |
| MBNA | Official public account pages show transaction history/statements; a current issuer page reviewed did not clearly promise CSV/OFX. | **No confirmed reward column.** | **Unconfirmed.** Obtain one logged-in export/menu screenshot before building a parser. |
| Scotiabank | Official help supports downloading recent transactions to **QFX** for personal finance software; exact credit-card coverage/range needs account validation. | **No confirmed reward column.** | **Possible QFX ingestion.** Test Momentum account explicitly. |
| Tangerine | Official FAQ supports transaction downloads including **CSV/QFX** and related personal-finance formats. | **No confirmed reward column.** | **Yes for transaction import;** category/reward still needs inference or UI confirmation. |
| Rogers Bank | Official Help Centre supports **CSV and OFX** downloads. | **No confirmed reward column.** | **Good candidate.** Join export transactions with issuer-confirmed Earned Rewards History/Accumulation Details. |
| Canadian Tire Financial Services | Official material clearly supports eStatements/app activity; no issuer-confirmed CSV/OFX path found. A third-party importer documents a CTB CSV format, which is not sufficient issuer proof. | **No confirmed reward column.** | **Owner-test required.** Start with statement parsing only if terms permit and sample is stable. |
| Wealthsimple | Official help supports credit-card statement/activity download in **PDF and CSV** on the web. | **No documented reward column; UI shows exact per-transaction cash back.** | **Strong candidate.** CSV transaction plus activity detail is clean ground truth. |
| Crypto.com | Official help supports **CSV export** of Card history; crypto/token wallet transaction history is exported separately. | Card CSV does not by itself establish a CRO-reward column. | **Strong but two-ledger.** Join Card purchase and Token Wallet CRO reward by time/amount/reference. |

Sources: [Amex official download formats (US account support; Canadian availability still owner-test)](https://www.americanexpress.com/us/customer-service/faq.download-export-transactions-software.html), [MBNA My Accounts](https://www.mbna.ca/en/my-accounts), [Scotia QFX help](https://help.scotiabank.com/article/how-can-i-download-transactions-to-ms-money?origin=nova), [Tangerine export FAQ](https://www.tangerine.ca/en/faq/how-do-i-download-transactions), [Rogers Bank account-management downloads](https://www.rogersbank.com/en/help_centre_answers/managing_your_account), [CTFS eStatements](https://www.ctfs.com/content/ctfs3/en/cards/estatements.html), [third-party CTB format evidence](https://neontra.com/support/import-csv/ctb/), [Wealthsimple credit-card statement/download help](https://help.wealthsimple.com/hc/en-ca/articles/37751448031131-View-and-download-your-credit-card-statement), [Crypto.com transaction-history export](https://help.crypto.com/en/articles/3438579-how-do-i-export-my-transaction-history-app). Checked 2026-08-15.

**High-ROI method:** Implement issuer adapters behind one normalized import contract. Preserve the raw file, normalized transaction, parser version, and reconciliation evidence. Do not build a universal “CSV” parser; columns, signs, dates, pending/posted handling, and duplicate identifiers differ.

---

# 3. Point valuations → engine defaults

These are conservative personal decision values, not guaranteed issuer cash values. The engine should retain a hard floor and a preferred-use value separately.

| Program | Recommended default | Realistic basis | Floor / sensitivity |
|---|---:|---|---|
| American Express Membership Rewards | **1.8¢/point CAD** | Transfer 1:1 to Aeroplan and redeem for flights the owner would otherwise buy, with a conservative realized-value target rather than aspirational premium-cabin screenshots. | Hard cash/travel-credit floor **1.0¢**. Use a user-adjustable range of 1.5–2.0¢. |
| Marriott Bonvoy | **0.8¢/point CAD** | Hotel award nights where cash price and taxes avoided produce reasonable value; use multi-night award advantages when genuinely useful. | Variable and inventory-dependent; sensitivity **0.6–1.0¢**. Do not assume airline-transfer value as the default. |
| MBNA Rewards | **1.0¢/point CAD** | Travel redemption at 100 points = $1. | Cash/charity floor **0.833¢** because 120 points = $1. |
| CT Money | **C$1 per CT$1** | Redeem against purchases the owner would genuinely make at participating Canadian Tire-family stores. | It is currency-like, not “points.” Optional usability haircut **0.95×** if locked value is considered less useful than cash. |
| CRO card rewards | **No cent-per-point value** | At issuance, store the CAD face value of the percentage reward and the CRO quantity separately. If CRO is immediately sold/converted, use **1.00×** face value net of actual spread/fees. | If held, default risk factor **0.80×** until sale; mark to market separately. Never value CRO as a stable point. |
| Cash-back programs | **1.00× CAD** | Momentum, Tangerine, Wealthsimple, and ordinary Rogers redemptions. | Rogers: apply **1.5×** only when an eligible service transaction is available and selected for redemption; enforce $10 minimum and purchase-window rules. |

Recommended machine-readable defaults:

```json
{
  "valuationsCad": {
    "amexMembershipRewards": {"centsPerPoint": 1.8, "floorCentsPerPoint": 1.0, "basis": "Aeroplan transfer; conservative realized flight value"},
    "marriottBonvoy": {"centsPerPoint": 0.8, "low": 0.6, "high": 1.0, "basis": "hotel award nights actually used"},
    "mbnaRewards": {"centsPerPoint": 1.0, "floorCentsPerPoint": 0.833333, "basis": "travel redemption; cash floor"},
    "ctMoney": {"cadPerUnit": 1.0, "optionalUsabilityFactor": 0.95},
    "cro": {"model": "reward-currency", "faceValueFactorIfAutoSold": 1.0, "defaultHeldRiskFactor": 0.8},
    "cashBack": {"cadPerDollar": 1.0},
    "rogersEligibleServiceRedemption": {"redemptionFactor": 1.5}
  }
}
```

Official program references: [American Express Membership Rewards](https://www.americanexpress.com/en-ca/rewards/membership-rewards/), [Marriott hotel redemptions](https://www.marriott.com/loyalty/redeem/hotels.mi), [MBNA Rewards terms PDF](https://www.mbna.ca/content/dam/mbna/document/pdf/credit-cards/mbna-rewards-0322-en.pdf), [Triangle World Elite / CT Money](https://triangle.canadiantire.ca/en/credit-cards/triangle-world-elite-mastercard.html), [Crypto.com card-reward help](https://help.crypto.com/en/articles/2742447-crypto-com-prepaid-card-rewards-benefits), [Rogers redemption rules](https://www.rogersbank.com/en/rewards). Checked 2026-08-15.

---

# 4. Owner defaults and one-minute settings

## Two one-tap decisions

- **Default habitual tap:** Wealthsimple Visa Infinite Privilege.
- **Exclude from physical daily carry:** Triangle World Elite Mastercard. Keep it enabled as a targeted engine option; “drawer card” is not the same as “closed/never recommend.”

## Engine policy for “meaningfully better”

Suggested v1 rule: recommend moving away from Wealthsimple only when the predicted **net** advantage is at least **0.5 percentage points** or **C$0.25 for the purchase**, after FX and valuation haircuts. Always allow an exception for acceptance constraints (for example, Mastercard-only Costco) and a user-forced card.

Why this is high ROI: a technically correct 2.1% recommendation over a reliable 2% card creates noise, undermines trust, and barely moves annual value. The threshold can later be learned per user.

## Owner-state values still needed before live ranking

These are not catalogue facts and should never be hard-coded globally:

1. **Tangerine:** current two/three selected categories and next category-change effective date.
2. **Rogers:** whether an eligible linked Rogers/Fido/Shaw/Comwave service is active; account/product anniversary; current $61,000 cap progress.
3. **Crypto.com:** current Level Up plan, qualification path, activation/expiry dates, and current monthly cap progress.
4. **Scotia:** account-opening statement month and current 4%/2% cap progress.
5. **Wealthsimple:** fee-waiver state. This does not change marginal checkout value in v1, but belongs in portfolio economics.
6. **All capped cards:** returns and manual corrections that affect period-to-date accumulator state.

---

# 5. Engine and catalogue recommendations

## 5.1 Separate issuer facts from owner state

Use three layers:

1. **Card product rules:** official earn, exclusions, caps, redemption paths, FX, effective dates.
2. **Owner/card-account state:** selected Tangerine categories, linked Rogers service, Crypto plan, cap progress, annual reset date, fee waiver, carry/acceptance preferences.
3. **Merchant evidence:** POI prior, brand prior, exact location/terminal result, channel, recurring flag, and actual reconciled reward.

This avoids cloning a new global card product for every user selection or eligibility state.

## 5.2 Effective-dated rule skeleton

```json
{
  "ruleId": "crypto-ca-fx-2026-09",
  "effectiveFrom": "2026-09-01T00:00:00-04:00",
  "effectiveTo": null,
  "announcedAt": "2026-08-15",
  "lastVerifiedAt": "2026-08-15",
  "sourceType": "issuerConfirmed",
  "sources": [{"url": "https://help.crypto.com/en/articles/5966447-crypto-com-prepaid-visa-card-fees-and-limits-canada"}],
  "status": "announced",
  "rule": {
    "fxFee": {
      "rate": 0.0,
      "spendCapCad": 1400,
      "period": "calendarMonth",
      "postCapRate": 0.02
    }
  }
}
```

Do the same for Platinum’s 2027 lounge benefit; even non-scored benefits should not be mixed into the current record.

## 5.3 Category and exclusion predicates

Each earn rule should be able to express:

```json
{
  "predicate": {
    "mccInclude": [5411],
    "mccExclude": [],
    "merchantInclude": [],
    "merchantExclude": ["costco", "walmart", "walmart-supercentre"],
    "country": "CA",
    "currency": null,
    "channel": ["cardPresent", "online"],
    "requiresRecurringIndicator": false,
    "processorExclusions": true
  }
}
```

Do not encode all category logic as natural-language labels. Scotia recurring payments need a network flag; Cobalt needs country restrictions; Crypto has MCC exclusions; Triangle has a merchant-brand exclusion layered on an MCC rule.

## 5.4 Cap accumulator

A cap record needs:

- `accumulatorId` so separate caps remain separate;
- measurement: `spend | points | rewardValue`;
- amount and currency;
- period: calendar month, calendar year, or account year;
- reset time and timezone;
- whether pending or posted transactions count;
- return/credit behavior;
- post-cap rate.

This is necessary to model Cobalt monthly spend, MBNA’s five category accumulators, Scotia’s two account-year accumulators, Rogers’ $61,000 account year, Triangle’s grocery calendar year, and Crypto’s UTC calendar month without special-case code.

## 5.5 Net-value formula

At checkout, score:

```text
expected net value CAD
= expected reward units × owner valuation
+ conditional redemption bonus likely to be used
− foreign-transaction fee
− reward-currency risk/spread haircut
− known funding or redemption friction
```

Then gate on card/network acceptance and compare with the owner’s default accepted card. “Value recovered” should be the recommended card’s expected net value minus the card Zubair would otherwise have tapped **at that moment**, not minus an abstract 1% baseline.

## 5.6 Merchant-confidence ladder

Recommended evidence order:

1. owner-confirmed reward result for exact merchant location/terminal/card/channel;
2. repeated reconciled result for the same merchant location/terminal;
3. issuer-specific known merchant override;
4. network MCC from the owner’s posted transaction;
5. brand/location seed plus MapKit POI category;
6. MapKit POI category only;
7. unknown → default card.

Never promote a Walmart or gas-station-kiosk result to every location. Store expiry/decay for merchant evidence because processors and coding change.

---

# 6. Recommended build sequence

1. **Seed current product rules** for the ten cards, using the effective-dated/source-per-rule model above.
2. **Build the deterministic scorer** with owner state, acceptance, caps, FX, and valuation; use Wealthsimple as the default counterfactual.
3. **Seed only high-confidence merchant overrides**: Canadian Tire-family banners, Costco network/brand handling, and owner-known recurring merchants. Keep mixed Walmart/gas/convenience cases probabilistic.
4. **Add manual “what did it earn?” correction** before CSV import. This generates the most valuable terminal-level evidence with much less parser work.
5. **Add CSV/QFX adapters** first for Wealthsimple, Rogers, Tangerine, and Crypto.com; they have the strongest public evidence. Add Amex after one Canadian sample. Gate MBNA/Scotia/CTFS on owner exports.
6. **Add page-change monitoring and review queue.** A changed hash should open a review task; it must not auto-publish new financial rules.

## Main risks to track

- Merchant coding is set by the merchant/acquirer and can differ by location, terminal, wallet/channel, or payment facilitator.
- Pending transaction names often differ from posted names.
- Return timing can make cap balances diverge from naive spend sums.
- Crypto product state and reward value are time-sensitive and materially riskier than ordinary cash back.
- Per-transaction reward visibility is strong for Amex, Rogers, Wealthsimple, and Crypto.com, but still needs owner evidence for MBNA, Scotia, Tangerine, and CTFS.
- The exact CardPointers 10-card coverage count cannot be established from public pages; a short in-app audit remains outstanding.

---

# 7. Owner validation checklist

The research is sufficient to build the seed catalogue and scorer. Before reconciliation work, collect one redacted sample/screenshot from each logged-in account:

- Amex: one posted 5× Cobalt transaction showing points.
- MBNA: download-menu formats and whether points appear per transaction.
- Scotia: Momentum download formats, one recurring transaction, and cash-back detail display.
- Tangerine: current selected categories and one transaction’s displayed category/reward detail.
- Rogers: Earned Rewards History plus one CSV/OFX row for the same transaction.
- CTFS: download menu and CT Money activity detail.
- Wealthsimple: one CSV row plus matching activity detail.
- Crypto.com: one Card CSV purchase plus matching CRO wallet reward credit.

Redact card numbers, account numbers, addresses, and unrelated transactions. These fixtures should live as private test data and should not be bundled with the public catalogue.

## Bottom line

The engine can be useful without an impossible universal MCC database if it is honest about uncertainty: Wealthsimple provides a strong 2%/no-FX fallback, official rules constrain the candidate rates, and owner reconciliation teaches exact merchant/location behavior. The highest-ROI differentiator is not a larger speculative brand table; it is a tight loop from recommendation → posted reward → corrected terminal-level evidence.
