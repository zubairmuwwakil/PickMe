# PickMe repo map — where work goes

This file answers one question: **where should a new artifact live?** Follow the
nearest `AGENTS.md` for how to work in that area.

## Canonical data and synchronized copies

| Artifact | Authoritative home | Copies / rule |
|---|---|---|
| Published card contracts and schemas | `contracts/` | Edit here; never author from a bundle/build copy |
| Swift package resources | `Engine/Sources/CardCopilotEngine/Resources/` | Synchronized by `scripts/sync-contracts-into-engine.sh` |
| Shared Swift fixtures | `Engine/Tests/CardCopilotEngineTests/Fixtures/` | Synchronized from `contracts/engine-fixtures.json` |
| Kotlin engine resources | `android/core/engine/src/{main,test}/resources/com/cardcopilot/engine/` | Synchronized by `scripts/sync-contracts-into-android.sh` |
| Merchant MCC graph | `contracts/merchant-mcc-graph/` | Store runtime copies live under `Store/Sources/CardCopilotStore/Resources/merchant-mcc-*`; sync with `scripts/sync-merchant-mcc-graph-into-store.sh`, never author the copies |
| Build products | `build/`, `.build/`, `android/**/build/` | Generated and ignored; never compare or edit as source |

## Source trees

| Work | Home |
|---|---|
| iOS/watch/widgets/share UI and app integration (Swift/SwiftUI) | `App/` |
| Canonical card-decision behavior (pure Swift) | `Engine/` |
| Local persistence, capture, sync, and composition (Swift/SwiftData) | `Store/` |
| Kotlin twin, Android store, and Android app | `android/` |
| Python catalogue research, provenance, draft promotion, and raw-source controls | `catalogue-pipeline/` |

## Documentation and release artifacts

| New artifact | Home |
|---|---|
| Ratified design/spec | `docs/superpowers/specs/YYYY-MM-DD-<slug>-design.md` |
| Executable implementation plan | `docs/superpowers/plans/YYYY-MM-DD-<slug>.md` |
| Product/architecture policy loaded on demand | `docs/policies/<topic>.md` |
| Issuer/card research | `docs/research/` |
| Privacy, deletion, and App Review material | `docs/compliance/` |
| Social publishing assets | `docs/linkedin/` |
| App Store screenshots and listing assets | `AppStore/` |

`docs/plans/` contains historical pre-Superpowers documents. Keep links working,
but put all new designs and implementation plans under `docs/superpowers/`.

## Automation

Existing automation remains under `scripts/`:

- `sync-contracts-into-{engine,android}.sh` copies canonical card-contract bytes.
- `sync-merchant-mcc-graph-into-store.sh` packages canonical MCC-graph seed bytes for offline Store runtime use.
- `release-catalogue.sh` stamps an immutable content-addressed release;
  `publish-catalogue.sh` performs the separate external publication.
- `validate-catalogue-schema.py`, `check-id-permanence.sh`,
  `check-raw-source-policy.sh`, and `validate-catalogue-schema.py` verify
  release/catalogue invariants.
- `generate_*` scripts produce App Store or catalogue artifacts; outputs belong in
  the mapped artifact directory, not beside the script.

Do not add a second home for the same artifact type. If none of these locations
fits, update this map in the same small commit that introduces the new location.
