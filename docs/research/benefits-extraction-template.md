# Benefits Extraction Template — Certificate Dossier Session

**Who:** Zubair, with each card's actual cardholder documents (certificates of insurance).
**What you edit:** `Engine/Sources/CardCopilotEngine/Resources/benefits-catalogue.json` — directly. It ships pre-filled with stub entries so you correct values instead of typing structure.
**Definition of done:** every card's `verificationStatus` is `certificateVerified`, then delete the loader test `testEveryShippedEntryIsStub` (it exists to keep the stub honest, not to survive your dossier).

## Per-card workflow

1. Find the card's **certificate of insurance** (the PDF in your cardholder agreement package — NOT the marketing page). Record its URL in `certificate.sourceUrl` and its printed date in `certificate.certificateDate` (`YYYY-MM` is fine). Certificates vary by issue date — yours is the ground truth, not the current public one.
2. Record the **underwriter** (named on the certificate's first page).
3. For each benefit the certificate grants, fill the matching entry (or add one; `benefitId` = `<card>-<kind>` kebab-case). Delete stub entries the certificate does not support — **absence after verification means "no coverage" and the app will say so** (spec B8).
4. Copy 1–3 load-bearing **conditions** verbatim into `conditions` (the ones that decide whether coverage applies: "full amount charged", trip-length limits, "decline the agency's CDW"). Same for `exclusions` that would surprise you (vehicle classes, unattended items, age limits).
5. Set `verificationStatus` to `certificateVerified` (or `issuerPage` if you only checked the public page — the UI will keep showing it as unverified-ish orange until certificate level).
6. Run `cd Engine && swift test --filter BenefitsLoaderTests` — it checks card-ID consistency and vocabulary; it will also tell you (via `testEveryShippedEntryIsStub` failing) that it's time to delete that test.

## Field guide by kind (units matter)

| Kind | Coverage fields to extract | Where it hides in the certificate |
|---|---|---|
| `purchaseProtection` | `windowDays` (days from purchase), `maxPerOccurrenceCad`, `maxAnnualCad` | "Purchase Security/Protection" section; window is usually 90–120 days |
| `extendedWarranty` | `extraYears`, `maxOriginalWarrantyYears` (doubles/extends up to N years original) | "Extended Warranty"; note the cap on the ORIGINAL warranty length |
| `mobileDeviceInsurance` | `maxCad`, `deductibleCad` | Standalone section; check whether financing/monthly-plan billing also qualifies — that's a condition |
| `flightDelay` | `delayHours` (threshold), `maxCad` | "Flight/Travel Delay"; the hour threshold is the load-bearing number |
| `baggageDelay` | `delayHours`, `maxCad` | Often shares a section with flight delay; usually essentials-only — quote that condition |
| `baggageLoss` | `maxCad` | "Lost/Stolen Baggage"; per-trip vs per-person matters — note it |
| `tripCancellation` | `maxCad` | Pre-departure causes; "charged before cause arose" is the classic condition |
| `tripInterruption` | `maxCad` | Post-departure; often a different max than cancellation |
| `rentalCdw` | `maxRentalDays`, `maxVehicleValueCad` | "Rental Vehicle Damage/Theft"; the MSRP cap and rental-length cap are the two numbers that void claims |
| `travelMedical` | `maxCad`, `maxTripLengthDays`, `ageLimit` | Emergency medical; trip-length and age limits are the coverage-voiding numbers — extract exactly |

## Rules that keep the feature honest

- Numbers you can't find: leave the field `null` and note it in `notes` — a missing number renders as "see certificate", never as a guess.
- Never paraphrase a condition into the coverage numbers. If the certificate says "up to $500 per insured person per trip", `maxCad: 500` plus the verbatim condition string.
- The engine treats `delayHours` and `deductibleCad` as lower-is-better and everything else as higher-is-better when computing the dominance badge — if a field doesn't fit that reading for some certificate, put the number in `notes`/`conditions` instead of the typed field.
