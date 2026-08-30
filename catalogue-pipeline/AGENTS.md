# Catalogue pipeline — research and provenance

This Python pipeline may discover and prepare card facts; it never promotes a
card on aggregator evidence alone. D3 requires issuer-confirmed sourcing before
a card becomes `published`, and blocked or uncleared raw material stays out of
the public repository and app bundles.

## Check

```bash
../scripts/check-raw-source-policy.sh
```

Read [`RAW_SOURCE_POLICY.md`](RAW_SOURCE_POLICY.md) before fetching, retaining,
or redistributing source material. Draft classifications are routing evidence,
not verification. Canonical released output belongs in `../contracts/` and then
follows the
[`card-contract-authoring` skill](../.claude/skills/card-contract-authoring/SKILL.md).

Anything not named here and not caught by the command above is yours to decide.
Work directly on `main`; do not create branches or pull requests.
