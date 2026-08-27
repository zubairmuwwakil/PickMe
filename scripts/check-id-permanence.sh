#!/usr/bin/env bash
# Fails when a cardId that a published release contained has vanished from the working catalogue.
#
# WHY
#
# Card ids are keyed on by prediction rows, owner state, MoneyTalks, and the Android consumer.
# A withdrawn product is tombstoned (status: withdrawn) and keeps its id forever; it is never
# deleted and never reused. That rule is cheap to state and easy to break during a cleanup, and
# nothing else in the pipeline notices — the catalogue still validates, the tests still pass, and
# the damage only appears on a device holding history for an id nobody defines any more.
#
#   scripts/check-id-permanence.sh              # compare against the latest published release
#   scripts/check-id-permanence.sh <release>    # compare against a specific one
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="${CATALOGUE_REPO:-zubairmuwwakil/PickMe}"

command -v gh >/dev/null 2>&1 || { echo "check-id-permanence: gh CLI not found" >&2; exit 1; }

release="${1:-}"
if [ -z "$release" ]; then
  release="$(gh release list --repo "$REPO" --limit 1 --json tagName -q '.[0].tagName' 2>/dev/null || true)"
fi

if [ -z "$release" ]; then
  echo "check-id-permanence: no published release to compare against — nothing to enforce yet"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! gh release download "$release" --repo "$REPO" --pattern card-catalogue.json --dir "$tmp" 2>/dev/null; then
  echo "check-id-permanence: could not download card-catalogue.json from $release" >&2
  exit 1
fi

published_ids="$(node -e 'require(process.argv[1]).cards.forEach(c=>console.log(c.cardId))' "$tmp/card-catalogue.json" | sort)"
working_ids="$(node -e 'require(process.argv[1]).cards.forEach(c=>console.log(c.cardId))' "$ROOT/contracts/card-catalogue.json" | sort)"

missing="$(comm -23 <(echo "$published_ids") <(echo "$working_ids"))"

if [ -n "$missing" ]; then
  echo "check-id-permanence: these cardIds were in $release and are gone from contracts/card-catalogue.json:" >&2
  echo "$missing" | sed 's/^/  /' >&2
  echo "check-id-permanence:" >&2
  echo "check-id-permanence: card ids are permanent. A discontinued product is tombstoned, not" >&2
  echo "check-id-permanence: deleted — set \"lifecycleStatus\": \"withdrawn\" and \"effectiveTo\", and leave" >&2
  echo "check-id-permanence: the card in place. Prediction rows and other repos key on these ids." >&2
  exit 1
fi

echo "check-id-permanence: every cardId in $release is still present ($(echo "$working_ids" | wc -l | tr -d ' ') cards)"
