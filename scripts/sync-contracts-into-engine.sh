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
cp "$root/contracts/benefits-catalogue.json" \
   "$root/Engine/Sources/CardCopilotEngine/Resources/benefits-catalogue.json"
cp "$root/contracts/programs.json" \
   "$root/Engine/Sources/CardCopilotEngine/Resources/programs.json"
cp "$root/contracts/engine-fixtures.json" \
   "$root/Engine/Tests/CardCopilotEngineTests/Fixtures/engine-fixtures.json"

echo "Synced contracts/ into Engine/."
