# Android — Kotlin twin

The Kotlin engine implements PickMe's Swift-defined card semantics; it does not
invent Android-only rules. Main and test JSON resources are synchronized copies
of `../contracts/`, and the shared fixtures define cross-language conformance.

## Check

```bash
./gradlew :core:engine:test
```

Change canonical data and fixtures under `../contracts/`, implement behavior in
Swift first, then sync with `../scripts/sync-contracts-into-android.sh`. Read the
[`card-contract-authoring` skill](../.claude/skills/card-contract-authoring/SKILL.md)
for the complete order.

Before changing the Kotlin twin for final reward/protection/route decisions, read
[`purchase-decision-architecture-design.md`](../docs/superpowers/specs/2026-09-04-purchase-decision-architecture-design.md).
The Kotlin implementation follows the Swift policy version; do not invent a
platform-specific utility model or silently change the meaning of a verdict.

Anything not named here and not caught by the command above is yours to decide.
Work directly on `main`; do not create branches or pull requests.
