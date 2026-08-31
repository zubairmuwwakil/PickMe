#!/usr/bin/env bash
# Local-first contract release, resource stamping, and sibling ecosystem synchronizer.
#
# Usage:
#   scripts/release-and-sync.sh               # Validate, stamp, sync Engine/Android, and sync MoneyTalks
#
# ZERO CLOUD MINUTES:
# Runs 100% locally on your machine without consuming GitHub Actions quota.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MONEYTALKS_ROOT="$(cd "$ROOT/../MoneyTalks" 2>/dev/null && pwd || true)"

echo "=== 1. Validating Contract Schemas ==="
if command -v python3 >/dev/null 2>&1; then
  python3 "$ROOT/scripts/validate-catalogue-schema.py"
fi

echo "=== 2. Stamping RELEASE.json ==="
# Check if version bump is required before stamping
if ! "$ROOT/scripts/release-catalogue.sh" --check >/dev/null 2>&1; then
  echo "Stamping updated contract release in contracts/RELEASE.json..."
  "$ROOT/scripts/release-catalogue.sh"
else
  echo "contracts/RELEASE.json is already current."
fi

echo "=== 3. Syncing into PickMe Swift Engine & Android resources ==="
"$ROOT/scripts/sync-contracts-into-engine.sh"
"$ROOT/scripts/sync-contracts-into-android.sh"

echo "=== 4. Syncing into Sibling MoneyTalks (In Unity) ==="
if [ -n "$MONEYTALKS_ROOT" ] && [ -d "$MONEYTALKS_ROOT" ]; then
  if [ -f "$MONEYTALKS_ROOT/scripts/sync/sync-contracts.sh" ]; then
    echo "Found MoneyTalks at $MONEYTALKS_ROOT. Syncing contracts..."
    (cd "$MONEYTALKS_ROOT" && ./scripts/sync/sync-contracts.sh --allow-dirty)
    echo "✓ Synced contracts into MoneyTalks/contracts/."
  fi
else
  echo "Notice: Sibling MoneyTalks directory not found at ../MoneyTalks. Skipping downstream sync."
fi

echo ""
echo "✓ Contract release & ecosystem sync complete!"
