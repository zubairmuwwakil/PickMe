# Issuer self-serve export coverage — literal MCC

**Date:** 2026-09-04  
**Status:** research finding; re-check before adding an issuer adapter  
**Scope:** the Canada and US issuers named in the import brief; a self-serve export a cardholder can download, not an aggregation API or paid reporting product.

## Headline

**Confirmed exact-MCC coverage for the current PickMe catalogue is 0 of 145 card
products (0%).** The only confirmed self-serve literal-MCC export is **RBC Visa
Business Reporting**, a commercial-card reporting portal. It is not documented as
available to the four currently catalogued RBC consumer cards, and PickMe does not
currently catalogue an eligible RBC commercial product. Therefore it is a useful
supported *format*, not evidence that a supported cardholder can supply exact MCC
today.

The named issuer families account for 106 of the 145 catalogue products (36 Canada,
70 US, including the four rows catalogued as JPMorgan Chase Bank, N.A. under
Chase). For the other 39 products, this review makes no export-coverage claim.
“Unconfirmed” below deliberately means the public documentation reviewed does not
establish the point; it does **not** mean the issuer definitely lacks the feature.

The practical finding is that ordinary statement export is **not** currently the
strong free exact-MCC acquisition channel. Keep the strict CSV importer, keep the
commercial RBC adapter, and do not imply that a usual consumer CSV/OFX/QFX download
will work. A real anonymised header/sample from an issuer may justify a small,
issuer-specific adapter later.

## Evidence rule

An export qualifies only where issuer documentation or an inspectable issuer sample
establishes a field explicitly named `MCC`, `MCC Code`, or `Merchant Category Code`
whose value is a literal four-digit MCC. A merchant-category label is not enough.

Standard OFX Banking 2.3 defines `SIC` in the credit-card transaction structure,
not MCC. The value may look code-like, but it is a Standard Industrial Code and must
not enter the exact-MCC path. [FDX’s OFX Banking 2.3
specification](https://financialdataexchange.org/common/Uploaded%20files/OFX%20files/OFX%20Banking%20Specification%20v2.3.pdf)
and PickMe’s earlier [provider evaluation](2026-09-04-merchant-mcc-provider-evaluation.md)
are the controlling evidence. A proprietary OFX extension explicitly labelled MCC
would be a different, issuer-specific case.

## Canada

| Issuer | CSV / OFX / QFX availability | Literal MCC? / column | Other documented columns | How obtained / source |
|---|---|---|---|---|
| Amex Canada | **Personal:** export-data flow exists, but public help does not name the file types. **Corporate:** CSV and QIF confirmed. | **Unconfirmed.** Neither public page names an `MCC` field. | Unconfirmed for personal; corporate page confirms statement-detail download but no schema. | Personal: sign in → Statements → Export Statement Data. [Amex personal help](https://www.americanexpress.com/en-ca/customer-service/payments-and-billings/faq.card-statements.html). Corporate cardmember: Online-Only Statements → CSV/QIF. [Amex management tools](https://www.americanexpress.com/en-ca/business/corporate-card/business-management-tools/). |
| RBC | **Consumer:** unconfirmed. **Visa Business Reporting:** CSV/Excel export confirmed. | **Yes, commercial only:** `MCC` / `MCC Desc`. Not confirmed for consumer exports. | Merchant/supplier name, transaction date, posting date, billing/source amount and currency, card account number, category are documented report fields. | RBC business Visa Business Reporting: sign in → search transactions/report → Export. [RBC/Visa Business Reporting guide](https://www.rbcroyalbank.com/business/credit-cards/_assets-custom/pdf/Visa_VBR_HelpGuide_EN.pdf). |
| TD | Unconfirmed. | Unconfirmed. | Unconfirmed. | No public issuer document reviewed establishes a credit-card transaction export schema. |
| Scotiabank | Unconfirmed. | Unconfirmed. | Unconfirmed. | No public issuer document reviewed establishes a credit-card transaction export schema. |
| CIBC | Unconfirmed. | Unconfirmed. | Unconfirmed. | No public issuer document reviewed establishes a credit-card transaction export schema. |
| BMO | Unconfirmed. | Unconfirmed. | Unconfirmed. | No public issuer document reviewed establishes a credit-card transaction export schema. |
| Tangerine | Unconfirmed. | Unconfirmed. | Unconfirmed. | No public issuer document reviewed establishes a credit-card transaction export schema. |
| Neo | **CSV confirmed** for Neo Credit and specified Money accounts; no OFX/QFX documented. | **Unconfirmed.** Neo’s help does not publish a header/schema or name MCC. | Date range, amount range, debit/credit filters; exported field names unconfirmed. | Web only: sign in → Credit or Money → account → Download CSV. [Neo help](https://support.neofinancial.com/hc/en-001/articles/34262065502989-Download-your-transaction-history-as-a-CSV-file). |
| EQ Bank | Unconfirmed. | Unconfirmed. | Unconfirmed. | No public issuer document reviewed establishes a credit-card transaction export schema. |
| Simplii | Unconfirmed. | Unconfirmed. | Unconfirmed. | No public issuer document reviewed establishes a credit-card transaction export schema. |
| Desjardins | **Business AccèsD:** CSV, OFX and TXT confirmed; consumer credit-card applicability remains unconfirmed. | **Unconfirmed.** The guide publishes formats, not an MCC field/schema. | Transaction-detail field names unconfirmed. | AccèsD Affaires → account/card → transaction statement/download; financial data downloadable for the documented period. [Desjardins AccèsD Affaires guide](https://www.desjardins.com/content/dam/pdf/en/business/accounts-treasury/accesd-affaires-guide.pdf). |

## United States

| Issuer | CSV / OFX / QFX availability | Literal MCC? / column | Other documented columns | How obtained / source |
|---|---|---|---|---|
| Chase | Unconfirmed in issuer documentation reviewed. | Unconfirmed. | Unconfirmed. | No public issuer document reviewed establishes a consumer credit-card export schema. |
| Amex US | Unconfirmed in issuer documentation reviewed. | Unconfirmed. | Unconfirmed. | No public issuer document reviewed establishes a consumer credit-card export schema. |
| Citi | Unconfirmed in issuer documentation reviewed. | Unconfirmed. | Unconfirmed. | No public issuer document reviewed establishes a consumer credit-card export schema. |
| Capital One | Unconfirmed in issuer documentation reviewed. | Unconfirmed. | Unconfirmed. | No public issuer document reviewed establishes a consumer credit-card export schema. |
| Discover | A QuickBooks-connected transaction download is documented; a standalone CSV/OFX/QFX file and schema are unconfirmed. | Unconfirmed. | Unconfirmed. | Connect/select Discover Card in QuickBooks → Download Transactions. [Discover connectivity guide](https://www.discover.com/applications/help-center/assets/Discover-Bank-and-Credit-Card-Connectivity.pdf). |
| Bank of America | Download to financial-management software is confirmed; standalone formats and schema are unconfirmed. | Unconfirmed. | Up to 12 months of detailed transaction information is documented; field names are unconfirmed. | Sign in → select credit card; use the transaction download flow. [Bank of America credit-card FAQ](https://www.bankofamerica.com/credit-cards/credit-card-account-information-faq/). |
| Wells Fargo | QuickBooks Web Connect download is confirmed; standalone CSV/OFX/QFX for a consumer card and schema are unconfirmed. | Unconfirmed. | Date range and account information are documented; merchant/date/amount column names are unconfirmed. | Sign in → account → choose a date range → QuickBooks (Web Connect) → Download. [Wells Fargo guide](https://www.wellsfargo.com/biz/online-banking/software/quickbooks/webconnect/). |
| U.S. Bank | Manual QuickBooks transaction export is confirmed for business banking; standalone CSV/OFX/QFX and credit-card schema are unconfirmed. | Unconfirmed. | Account Activity and date-range selection are documented; exported field names are unconfirmed. | Sign in → account → Activity → Download. [U.S. Bank guide](https://www.usbank.com/business-banking/business-online-mobile-banking/quickbooks.html). |

## Consequences for PickMe

1. **Do not add generic OFX/QFX ingestion.** It would mostly invite SIC/category
   data and turn an intentionally strict exact-evidence path into an inference path.
2. **Keep CSV as the one accepted container for now.** It covers the one confirmed
   literal-MCC export (RBC Visa Business Reporting) and is easy to inspect before
   import. The generic CSV adapter must still require the explicit MCC header.
3. **Do not market the feature as normal statement import.** Settings should describe
   it as an optional issuer **MCC CSV** import and link this research. A cardholder
   whose normal CSV lacks MCC should receive a clear skipped-row/unsupported-column
   result, never a fabricated category conversion.
4. **Highest-value next research input is a real export header from a cardholder.**
   Collect only voluntarily supplied, redacted headers/samples; add an issuer adapter
   only when the literal field and date/merchant semantics are verified. Do not retain
   the source file in the app.

## Limits and re-check triggers

This review is intentionally evidence-conservative. Login-gated exports can change
without public documentation, and absence cannot be proven from public help pages.
Re-run this table when an issuer publishes a schema, when a cardholder supplies a
redacted current header, or before accepting any new file format. The hard $0
production constraint and no-SIC-conversion rule remain unchanged.
