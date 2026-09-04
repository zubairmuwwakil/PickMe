#!/usr/bin/env bash
# Keep Store's SPM-bundled MCC graph resources byte-identical to the canonical contracts/ graph.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/contracts/merchant-mcc-graph"
dst="$root/Store/Sources/CardCopilotStore/Resources"
mkdir -p "$dst"

cp "$src/manifest.json" "$dst/merchant-mcc-manifest.json"
cp "$src/profiles.json" "$dst/merchant-mcc-profiles.json"
cp "$src/observations.json" "$dst/merchant-mcc-observations.json"
for shard in "$src"/merchants-*.json; do
  cp "$shard" "$dst/merchant-mcc-$(basename "$shard")"
done

echo "Synced contracts/merchant-mcc-graph into Store resources."
