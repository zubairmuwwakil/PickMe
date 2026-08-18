# Project rules (ratified — do not relitigate in-session)

Decision record: ../MoneyTalks/docs/decisions/2026-08-16-one-money-app.md · newest rulings: ../MoneyTalks/docs/decisions/LOG.md

@ECOSYSTEM.md

- **This engine is the canonical owner of all card-decision semantics** (checkout pick, keep/cancel, benefits, valuation) for the ecosystem. The unifier's card engine is frozen and will be deleted; do not mirror features there.
- **PickMe is one product of four, not the brand of the whole thing** (E1 supersedes D1). The unifier gets its own consumer name; PickMe keeps its identity as the iOS card copilot. Don't write copy that treats PickMe as the umbrella product.
- `Engine/.../Resources/card-catalogue.json` + `engine-fixtures.json` are a shared cross-language contract — treat fixture changes as API changes.
- Deep analytics and visualization belong on the web hub, not here (A5). This app stays a single-responsibility control centre.
- Test/CI health (verified 2026-08-17): `Engine` 164 tests and `Store` 69 tests green; CI gate at `.github/workflows/ci.yml`. Keep it green.
