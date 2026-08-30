# Engine — Swift semantic authority

`contracts/` owns published JSON bytes. This Swift package owns the canonical
behavior that interprets them; C1 permits only fixture-gated twins of the scoring
core. Contract shape or behavior changes land in Swift and shared fixtures before
Kotlin or TypeScript follows.

## Check

```bash
swift test
```

Edit canonical data under `../contracts/`, then use the root sync scripts; do not
hand-edit bundled resource copies. Every published card must retain D3's
issuer-confirmed sourcing bar. Read the
[`card-contract-authoring` skill](../.claude/skills/card-contract-authoring/SKILL.md)
before changing a contract, schema, fixture, or release stamp.

Anything not named here and not caught by `swift test` is yours to decide. Work
directly on `main`; do not create branches or pull requests.
