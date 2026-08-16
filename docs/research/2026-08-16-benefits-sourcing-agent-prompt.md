# Benefits Sourcing — Agent Handoff Prompt

**Date:** 2026-08-16 · **Owner:** Zubair · **Status:** not yet run
**Purpose:** Copy the prompt in the fenced block below and hand it to an agent (a fresh Claude Code session opened on this repo is the natural fit — it needs file read/write, web search, and bash). It replaces the stub data in `benefits-catalogue.json` with real sourced data, or honestly reports where it couldn't.

**Fallback plan:** if the agent can't reliably find/match official certificates for some cards, its final report tells you exactly which ones — finish those manually with `docs/research/benefits-extraction-template.md`, same as before.

---

## The prompt

```
You are sourcing real credit-card benefits data (purchase protection, extended
warranty, travel insurance) for 10 Canadian credit cards, to replace draft/stub
data in a card-recommendation app's repo. You have web search, web fetch, and
file read/write access to this repository.

## Mission

Edit `Engine/Sources/CardCopilotEngine/Resources/benefits-catalogue.json` in
place. It currently holds 10 cards, each with `"verificationStatus": "stub"` —
placeholder numbers I (a previous agent) drafted from memory/guesswork, not
from real documents. Your job: replace each card's entries with data read from
that card's actual, official **Certificate of Insurance** (sometimes titled
"Guide to Benefits," "Certificate of Insurance and Summary of Coverage," or
similar) — the legal document, not a marketing summary page — published on the
issuer's own official domain.

Before touching anything, read these two files in full:
1. `docs/research/benefits-extraction-template.md` — the field-by-field guide:
   what each coverage field means, its unit, and where it typically appears in
   a certificate. Follow it exactly.
2. `Engine/Sources/CardCopilotEngine/Models/BenefitsModels.swift` — the Swift
   types the JSON must decode into. `BenefitCoverage` lists every valid field;
   do not invent field names not defined there.

## Hard rules — read before starting

1. **Official sources only.** Use only PDFs/pages hosted on the issuer's own
   domain (e.g., americanexpress.com, scotiabank.com, mbna.ca, tangerine.ca,
   rogersbank.com, canadiantire.ca/triangle, wealthsimple.com, crypto.com).
   Never use blogs, forums, Reddit, comparison sites (creditcardGenius,
   Ratehub, Prince of Travel, etc.), or any third-party aggregator, even if
   they quote the certificate — go to the primary source yourself.
2. **Match the exact product.** Card names below are exact. Issuers sell
   multiple similar-sounding products (e.g., several Amex cards, several
   World Elite Mastercards) — confirm the certificate you found is titled for
   *this exact card*, not a sibling product, a US version, or a discontinued
   predecessor. If you're not sure it's an exact match, treat it as not found
   rather than guessing.
3. **No fabricated numbers.** If a field isn't stated in the certificate,
   leave it `null` and say so in `notes`. Never estimate, round from a
   marketing blurb, or carry over a number from a similar card.
4. **Quote, don't paraphrase.** `conditions` and `exclusions` must be near-
   verbatim from the certificate's own wording (trim for length if needed,
   but don't rewrite the meaning) — these are the clauses that decide whether
   coverage actually applies.
5. **Verification status — read carefully:**
   - If you read the actual Certificate of Insurance PDF from the issuer's
     own domain and are confident of the product match → set
     `"verificationStatus": "issuerPage"` (NOT `"certificateVerified"`).
     `"certificateVerified"` is reserved for Zubair confirming against his
     own cardholder documents, because certificate terms can vary by the
     date a card was opened — what you find published today may not exactly
     match his actual terms. Your best sourcing still leaves that one rung
     of doubt, and the status field should say so honestly.
   - If you could only find a marketing/benefits summary page (not the actual
     certificate), you may still fill in what it states, but leave
     `"verificationStatus": "stub"` and note in `notes` that this is from a
     summary page, not the certificate.
   - If you found nothing usable for a card, leave that card completely
     untouched (still `"stub"`, same placeholder values) and list it in your
     final report as not sourced.
6. **Don't touch anything else.** Only edit `benefits-catalogue.json`. Don't
   modify other files, don't run `git commit`, don't change the schema.

## The 10 cards

| cardId | Official product name | Issuer |
|---|---|---|
| `amex-platinum` | The Platinum Card from American Express | American Express Canada |
| `amex-cobalt` | American Express Cobalt Card | American Express Canada |
| `amex-bonvoy` | Marriott Bonvoy American Express Card | American Express Canada |
| `mbna-rewards-we` | MBNA Rewards World Elite Mastercard | MBNA |
| `scotia-momentum-vi-plus` | Scotia Momentum Visa Infinite + Card | Scotiabank |
| `tangerine-moneyback-world` | Tangerine Money-Back World Mastercard | Tangerine |
| `rogers-red-we` | Rogers Red World Elite Mastercard | Rogers Bank |
| `triangle-we` | Triangle World Elite Mastercard | Canadian Tire Financial Services |
| `wealthsimple-vip` | Wealthsimple Visa Infinite Privilege Credit Card | Wealthsimple |
| `cryptocom-royal-indigo` | Crypto.com Prepaid Visa Card (Royal Indigo) | Digital Commerce Bank (Crypto.com program) |

Known gotchas — questions to actually check, not assumed answers:
- **Amex Platinum / Cobalt / Bonvoy** all insure through the same underwriter
  in Canada; their certificates are often one shared PDF covering multiple
  Amex products with a per-card benefits table inside — find the table, don't
  assume all three have identical numbers.
- **Wealthsimple VIP** is a newer product — its insurance certificate may be
  thin, hard to find, or issued through a different partner/underwriter than
  you'd expect from a "Visa Infinite Privilege" tier. Confirm before assuming
  parity with other VI Privilege cards from other issuers.
- **Crypto.com Prepaid Visa (Royal Indigo)** is a prepaid card, not a
  traditional credit card — it may have materially fewer or no purchase/travel
  insurance benefits. A confirmed "no coverage" (once you've actually located
  and checked their terms) is a valid, useful outcome — don't force a match
  that isn't there. Distinguish "confirmed no coverage" from "couldn't find
  documentation" in your report.
- **Triangle World Elite** — Canadian Tire's insurance program may be
  branded under Triangle Rewards / Roynat or a separate insurer name distinct
  from "Canadian Tire" — search accordingly if the obvious name doesn't work.

## Per-card workflow

For each card, in the order listed above:
1. Web search for `"<official product name>" certificate of insurance` and
   `"<official product name>" guide to benefits`, restricted mentally to the
   issuer's own domain (check the URL before trusting a result).
2. Fetch and read the PDF/page. Confirm it names your exact card product.
3. For each benefit family that applies (shopping / travel disruption /
   rental CDW / travel medical — see the extraction template for the full
   kind list), fill or replace that card's entry in the JSON: `coverage`
   fields per the template's field guide, `conditions`/`exclusions` verbatim,
   `certificateQuote` optional but nice for anything ambiguous.
4. Fill `certificate.underwriter`, `certificate.sourceUrl` (the exact URL you
   read), `certificate.certificateDate` (the date printed on the document,
   `YYYY-MM` is fine, `null` if not stated), `certificate.lastVerifiedAt`
   (today's date), and `certificate.verificationStatus` per rule 5 above.
5. Move to the next card. Don't batch-guess from patterns across cards —
   source each one independently even when issuers seem similar.

## When you're done

Run this to confirm the file still decodes correctly and the vocabulary is
valid (this does NOT check your data's accuracy — only that the JSON is
well-formed and uses known field names):

    cd Engine && swift test --filter BenefitsModelsTests

Note: `swift test --filter BenefitsLoaderTests` includes a test called
`testEveryShippedEntryIsStub` that will now start FAILING for any card you
upgraded past `"stub"` — that failure is expected and correct, it's the
signal that real data has landed. Do not try to "fix" it by reverting
statuses back to stub. Leave it failing; Zubair will delete that test once
every card reaches `certificateVerified`.

Finish with a report in this exact shape:

    ## Sourcing report

    ### Fully sourced (issuerPage)
    - <cardId>: <one line — what you found, source URL>

    ### Partially sourced / summary page only (stub, notes added)
    - <cardId>: <what's missing or uncertain>

    ### Not found — needs manual sourcing
    - <cardId>: <what you tried, why it didn't work>

Do not commit anything. Leave the changes staged/unstaged for Zubair to
review and commit himself.
```

---

## After the agent runs

1. Read its sourcing report — anything in "Not found" is where you pick up manually with the extraction template.
2. `git diff Engine/Sources/CardCopilotEngine/Resources/benefits-catalogue.json` to review before committing anything.
3. `cd Engine && swift test` — full suite, sanity check nothing else broke.
4. Spot-check 1–2 of the "fully sourced" cards against the source URL yourself before trusting them at `issuerPage` level — the agent can still misread a table or miss a footnote exclusion.
