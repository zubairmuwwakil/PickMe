#!/usr/bin/env bash
# Copies the canonical contracts/ files into the checked-in Engine/ copies that SPM resource
# bundling requires (a Swift package cannot declare resources outside its own package root).
#
# Run this after editing anything under contracts/, then run `swift test` in Engine/ —
# ContractsSyncTests fails on any byte-level drift between contracts/ and these copies.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cp "$root/contracts/card-catalogue.json" \
   "$root/Engine/Sources/CardCopilotEngine/Resources/card-catalogue.json"
cp "$root/contracts/candidate-catalogue.json" \
   "$root/Engine/Sources/CardCopilotEngine/Resources/candidate-catalogue.json"
cp "$root/contracts/application-requirements.json" \
   "$root/Engine/Sources/CardCopilotEngine/Resources/application-requirements.json"
cp "$root/contracts/benefits-catalogue.json" \
   "$root/Engine/Sources/CardCopilotEngine/Resources/benefits-catalogue.json"
cp "$root/contracts/programs.json" \
   "$root/Engine/Sources/CardCopilotEngine/Resources/programs.json"
cp "$root/contracts/owner-conditions.json" \
   "$root/Engine/Sources/CardCopilotEngine/Resources/owner-conditions.json"
cp "$root/contracts/purchase-categories.json" \
   "$root/Engine/Sources/CardCopilotEngine/Resources/purchase-categories.json"
cp "$root/contracts/owner-state.json" \
   "$root/Engine/Sources/CardCopilotEngine/Resources/owner-state.json"
cp "$root/contracts/RELEASE.json" \
   "$root/Engine/Sources/CardCopilotEngine/Resources/RELEASE.json"
cp "$root/contracts/engine-fixtures.json" \
   "$root/Engine/Tests/CardCopilotEngineTests/Fixtures/engine-fixtures.json"
cp "$root/contracts/application-requirements-fixtures.json" \
   "$root/Engine/Tests/CardCopilotEngineTests/Fixtures/application-requirements-fixtures.json"

echo "Synced contracts/ into Engine/."
