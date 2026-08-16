# Project rules (ratified — do not relitigate in-session)

Decision record: ../MoneyTalks/docs/decisions/2026-08-16-one-money-app.md

- **This engine is the canonical owner of all card-decision semantics** (checkout pick, keep/cancel, benefits, valuation) for the unified One Money App. MoneyTalks' card engine is frozen and will be deleted; do not mirror features there.
- `Engine/.../Resources/card-catalogue.json` + `engine-fixtures.json` are becoming a shared cross-language contract — treat fixture changes as API changes.
- Known debt to clear before new card work merges: `BenefitsLoaderTests` is red at HEAD (asserts all-stub; catalogue now has `issuerPage` entries) and there is no CI. Fix test + add a fixture gate first.
