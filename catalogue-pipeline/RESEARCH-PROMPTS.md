# Research prompts — catalogue 2.4 follow-ups

Three independent research tasks left open by catalogue 2.4. Each is written to be pasted into an
external research assistant (Gemini) as-is. Each asks for **sourced facts with URLs and dates**, and
each explicitly authorises "I could not source this" as an answer — a gap recorded honestly is worth
more here than a plausible number, because these values end up in a contract that four consumers
vendor and that says, with the schema's authority, what a card is worth.

Return format is JSON in every case so the result can be diffed against the pipeline files directly.

---

## Prompt 1 — Valuations for the seven co-brand currencies

> I need reward-currency valuations for a credit-card recommendation engine. Seven US/Canadian
> co-brand loyalty currencies currently have NO valuation, so every card on them is excluded from
> scoring. I need one defensible number per currency, plus its source.
>
> The currencies:
> `aaAdvantage` (American Airlines AAdvantage), `atmosRewards` (Alaska/Hawaiian Atmos Rewards, the
> merged programme that replaced Mileage Plan and HawaiianMiles), `avios` (the shared IAG currency:
> British Airways, Aer Lingus, Iberia), `cathayAsiaMiles` (Cathay's Asia Miles),
> `deltaSkyMiles` (Delta SkyMiles), `disneyRewards` (Disney Rewards Dollars),
> `spiritFreeSpirit` (Spirit Free Spirit).
>
> **The method I need you to follow exactly.** These are not "what do points guys say they're
> worth" estimates. Three distinct numbers, and it matters which is which:
>
> - `centsPerPoint` — the best **POSTED FIXED** conversion the programme publishes. A rate, never a
>   forecast of what a good redemption might return. If the programme prices awards dynamically and
>   posts no fixed conversion, say so and explain what you ranked on instead.
> - `floorCentsPerPoint` — the rate obtainable with **nothing but the card**: an unconditional
>   statement credit or cash-out, no qualifying purchase and no second account. **OMIT this entirely
>   if the programme has no cash redemption at all.** Do not invent a floor; a fabricated one passes
>   an assumption off as a guarantee.
> - `aspirationalCentsPerPoint` — a published third-party benchmark, included **only if it exceeds**
>   your `centsPerPoint`. This is a disclosure ceiling, never used for ranking. Omit if the
>   benchmark is at or below the ranked value.
>
> **The `basis` string is the actual deliverable.** For each currency write 2–5 sentences that name
> the source, give the date checked, and state plainly which parts are issuer fact and which are
> assumption. Where you assume something about redemption behaviour, say "ASSUMPTION:" and say what
> an owner who behaves differently should override. Two real examples of the standard, from the same
> file:
>
> - *"1.0¢ is TD's posted rate — 200 TD Points = $1 booked through Expedia for TD — and the
>   programme's best fixed-value redemption. floorCentsPerPoint 0.25 is the unconditional cash-out:
>   400 points = $1 as a statement credit, the same rate gift cards clear at (Ratehub, checked
>   2026-08-20). Prince of Travel (Q2 2026) and Milesopedia (2026-01-01) both benchmark TD Rewards
>   at 0.5¢, so there is no upside band to disclose."*
> - *"Aeroplan has NO cash-out and posts no fixed conversion — flight rewards are dynamically priced
>   — so floorCentsPerPoint is deliberately absent rather than invented. Ranked at 1.0¢ by transfer
>   parity: Amex MR converts to Aeroplan 1:1 and is ranked at 1.0¢, so valuing Aeroplan above that
>   would make one point worth more after a free transfer than before it."*
>
> **Two currencies need a different model and I need you to flag rather than force them.**
> `disneyRewards` is Disney Rewards **Dollars** — a store-locked, dollar-denominated reward, not a
> point. If that is right, tell me its face value, where it can and cannot be spent, and whether a
> usability discount is warranted for money locked to one merchant; do NOT express it as
> centsPerPoint. Apply the same test to any other currency here that turns out to be dollar-
> denominated rather than a true point.
>
> **Also tell me, per currency, whether transfer parity constrains the number** — if a bank currency
> (Amex MR, Chase UR, Citi ThankYou, Capital One) transfers to it at 1:1 or better, the co-brand
> currency cannot rationally be ranked above that bank currency's own ranked value, and I need to
> know which ones that binds.
>
> Return JSON:
> ```json
> {"aaAdvantage": {"model":"points","centsPerPoint":0.0,"floorCentsPerPoint":0.0,
>                  "aspirationalCentsPerPoint":0.0,"basis":"...",
>                  "sources":[{"url":"...","checked":"YYYY-MM-DD","what":"..."}],
>                  "transferParityConstraint":"...", "confidence":"high|medium|low"}}
> ```
> Omit `floorCentsPerPoint` / `aspirationalCentsPerPoint` where the rules above say to. If you
> cannot source a currency honestly, return `{"refused": "reason"}` for it — that is a valid and
> useful answer, and I would much rather have it than a number.

---

## Prompt 2 — The Costco reward certificates: one currency or two?

> A ruling question about credit-card reward currencies, not a valuation.
>
> Two cards pay what both call a Costco cash reward:
> - **CIBC Costco Mastercard (Canada)** — a Cash Back Gift Certificate in **CAD**, issued once a
>   year in January for the prior calendar year, redeemable at Canadian Costco warehouses.
> - **Citi Costco Anywhere Visa (US)** — an annual Costco Cash Reward certificate in **USD**,
>   redeemable at US Costco.
>
> My catalogue keys reward valuation on a single `programId`. Two currencies sharing one id is
> correct **only when the currency is genuinely the same** — Marriott Bonvoy and Aeroplan share ids
> across the US and Canada for exactly that reason. I need to know whether Costco is such a case,
> and I have deferred adding any id until this is answered.
>
> Answer these specifically, with sources:
> 1. Can a CIBC-issued certificate be redeemed at a US Costco, or a Citi-issued one at a Canadian
>    Costco? Is there any conversion, transfer or reciprocity between them at all?
> 2. Are they administered as one programme by Costco, or independently by each issuer?
> 3. Is either one redeemable for anything **other** than merchandise at a Costco warehouse — cash
>    at the till, a statement credit, online purchases, Costco Travel? This decides whether a cash
>    floor exists or must be omitted.
> 4. Does either expire, and can either be used by an authorised user rather than only the primary
>    cardholder?
> 5. Same question for **Amazon**: the Canadian catalogue has an `amazonRewards` id for the MBNA
>    Amazon.ca card (100 points = $1 in Amazon.ca credit). Is the US Amazon co-brand's reward the
>    same currency or a separate one? My pipeline flagged it as "distinct from the CA amazonRewards
>    entry" and I need that confirmed or refuted.
>
> Then give me a recommendation: **one shared id, two market-scoped ids, or neither** — and say what
> would have to be true for the shared id to be defensible. Note that a store-locked annual
> certificate is arguably not a "points" programme at all but a dollar-denominated reward with a
> usability discount, like Canadian Tire Money; tell me if you agree and why.
>
> Return JSON: `{"sameCurrency": true|false, "recommendation":"...", "reasoning":"...",
> "amazonSameCurrency": true|false, "sources":[{"url":"...","checked":"YYYY-MM-DD"}]}`

---

## Prompt 3 — Eight disputed annual fees (unblocks four more currencies)

> I need the **current annual fee** for eight US credit cards, from the issuer's own page. My
> aggregator snapshots disagree with each other on all eight, so I refused to import them rather
> than pick a number. The disagreement is the clue: it usually means the sources are describing
> different products in the same family, or confusing an intro-year fee with the ongoing one.
>
> | Card | Sources disagree at |
> |---|---|
> | Hilton Honors American Express **Aspire** Card | $0 / $150 / $195 / $550 |
> | Delta SkyMiles **Gold Business** American Express | $150 / $350 / $650 |
> | Delta SkyMiles® **Platinum** American Express Card | $350 / $650 |
> | Alaska Airlines **Atmos™ Ascent** Visa Signature® Card | $95 / $395 |
> | **Atmos™ Rewards Visa Signature® Business** Credit Card | $70 / $95 |
> | Emirates Skywards **Premium** World Elite Mastercard® (Barclays) | $99 / $499 |
> | Frontier Airlines World Mastercard® (Barclays) | $89 / $99 |
> | Choice Privileges Mastercard® (Wells Fargo) | $0 / $95 |
>
> For each, I need:
> 1. The **ongoing** annual fee (not a first-year-waived or intro figure), in USD.
> 2. The **issuer's own URL** it came from — not a comparison site, blog or aggregator.
> 3. The date you checked it.
> 4. **Whether the range above is explained by a card family.** For the Hilton one especially, I
>    suspect $0/$150/$550 are the no-fee Hilton, Surpass and Aspire cards being described under one
>    name — if so, say which fee belongs to which product and confirm the Aspire figure specifically.
> 5. Whether the card is **still open to new applicants**, and if not, when it closed and whether
>    existing cardholders keep it. (I know Barclays stopped new Hawaiian Airlines applications on
>    2025-10-01 while existing cardholders continued, so this is a real pattern in this set.)
>
> Return JSON:
> ```json
> {"american-express-hilton-honors": {"annualFeeUsd": 0, "issuerUrl":"...",
>   "checked":"YYYY-MM-DD", "familyConfusion":"...", "openToNewApplicants": true, "notes":"..."}}
> ```
> Use exactly these keys: `american-express-hilton-honors`,
> `american-express-delta-skymiles-gold-business`, `american-express-delta-skymiles-platinum`,
> `bank-of-america-alaska-airlines-atmos-ascent`, `bank-of-america-atmos-rewards-visa-signature`,
> `barclays-emirates-skywards-premium-world`, `barclays-frontier-airlines-world-mastercard`,
> `wells-fargo-choice-privileges-mastercard`.
>
> If you cannot find a fee on the issuer's own site, return `{"refused":"reason"}` for that card.
> An honest gap is fine; a number from a comparison site is not, because these disagree already and
> that is the entire problem.

---

## Where the answers go

- **Prompt 1** → `contracts/programs.json` `defaults`. Adding a valuation here also permits the
  matching cards to be promoted `draft` → `published` **after** their earn rules clear D3's
  issuer-confirmed bar. The two steps are independent: a valuation does not make a card publishable.
- **Prompt 2** → a ruling line in `MoneyTalks/docs/decisions/LOG.md`, then (if approved) a
  `programId` addition following the 2.4 pattern.
- **Prompt 3** → `catalogue-pipeline/card-research-queue.json` (resolve the fee conflict), then
  re-add `hiltonHonors`, `emiratesSkywards`, `frontierMiles`, `choicePrivileges` to the schema enum
  and their four cards to `card-programs.json`, and re-run `promote_drafts.py`.

Every one of these is a catalogue MINOR bump: `catalogueVersion` → `release-catalogue.sh` →
commit → push → `publish-catalogue.sh` → `sync-contracts.sh` in MoneyTalks.
