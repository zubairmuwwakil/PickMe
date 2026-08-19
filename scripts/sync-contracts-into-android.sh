#!/usr/bin/env bash
# Copies canonical contracts/ and owner-state.json into android/ resources.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
res_main="$root/android/core/engine/src/main/resources/com/cardcopilot/engine"
res_test="$root/android/core/engine/src/test/resources/com/cardcopilot/engine"

mkdir -p "$res_main" "$res_test"

cp "$root/contracts/card-catalogue.json" "$res_main/card-catalogue.json"
cp "$root/contracts/candidate-catalogue.json" "$res_main/candidate-catalogue.json"
cp "$root/contracts/benefits-catalogue.json" "$res_main/benefits-catalogue.json"
cp "$root/Engine/Sources/CardCopilotEngine/Resources/owner-state.json" "$res_main/owner-state.json"

cp "$root/contracts/engine-fixtures.json" "$res_test/engine-fixtures.json"

echo "Synced contracts/ into android/core/engine resources."
