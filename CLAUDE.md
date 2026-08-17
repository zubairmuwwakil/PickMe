# Project rules (ratified — do not relitigate in-session)

Decision record: ../MoneyTalks/docs/decisions/2026-08-16-one-money-app.md

- **This engine is the canonical owner of all card-decision semantics** (checkout pick, keep/cancel, benefits, valuation) for the unified One Money App. MoneyTalks' card engine is frozen and will be deleted; do not mirror features there.
- `Engine/.../Resources/card-catalogue.json` + `engine-fixtures.json` are becoming a shared cross-language contract — treat fixture changes as API changes.
- Test/CI health (verified 2026-08-17): `Engine` 164 tests and `Store` 69 tests green; CI gate lives at `.github/workflows/ci.yml`. The former `BenefitsLoaderTests` staleness and the missing CI are both resolved — treat fixture changes as API changes and keep the gate green.
