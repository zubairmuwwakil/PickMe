#!/usr/bin/env bash
# Prevents uncleared third-party source material from entering this public repository.
# The allowlist is intentionally closed: a new raw source needs a licence review first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="$ROOT/catalogue-pipeline/RAW_SOURCE_POLICY.md"
MANIFEST="$ROOT/catalogue-pipeline/raw/MANIFEST.json"
MIT_NOTICE="$ROOT/catalogue-pipeline/licences/cc-offers-MIT.txt"
SWIFT_NOTICES="$ROOT/Engine/Sources/CardCopilotEngine/Resources/THIRD_PARTY_NOTICES.md"
ANDROID_NOTICES="$ROOT/android/core/engine/src/main/resources/com/cardcopilot/engine/THIRD_PARTY_NOTICES.md"

allowed_raw_path() {
  case "$1" in
    catalogue-pipeline/raw/MANIFEST.json)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

unexpected=()
while IFS= read -r tracked; do
  # A worktree deletion is still reported by git ls-files until it is staged.
  [ -e "$ROOT/$tracked" ] || continue
  if ! allowed_raw_path "$tracked"; then
    unexpected+=("$tracked")
  fi
done < <(git -C "$ROOT" ls-files 'catalogue-pipeline/raw/**')

if [ "${#unexpected[@]}" -ne 0 ]; then
  echo "check-raw-source-policy: blocked or unreviewed raw material is tracked:" >&2
  printf '  %s\n' "${unexpected[@]}" >&2
  echo "Review catalogue-pipeline/RAW_SOURCE_POLICY.md before changing the allowlist." >&2
  exit 1
fi

node - "$MANIFEST" <<'NODE'
const manifest = require(process.argv[2]);
if (manifest.manifestVersion !== 1 || !Array.isArray(manifest.snapshots) || manifest.snapshots.length === 0) {
  throw new Error('MANIFEST.json must be a non-empty v1 snapshot manifest');
}
const ids = new Set();
const hashes = new Set();
for (const snapshot of manifest.snapshots) {
  const required = ['snapshotId', 'sourceId', 'sourceUrl', 'fetchedAt', 'filename', 'sha256', 'licence', 'release'];
  if (required.some((key) => snapshot[key] == null) || !/^[a-f0-9]{64}$/.test(snapshot.sha256)) {
    throw new Error(`Invalid snapshot manifest entry: ${JSON.stringify(snapshot.snapshotId)}`);
  }
  if (ids.has(snapshot.snapshotId) || hashes.has(snapshot.sha256)) {
    throw new Error(`Duplicate snapshot id or sha256: ${snapshot.snapshotId}`);
  }
  if (!snapshot.release.tag.startsWith('raw-snapshots@') || !snapshot.release.asset.endsWith('.tar.gz')) {
    throw new Error(`Snapshot ${snapshot.snapshotId} must use a raw-snapshots@ tar.gz release asset`);
  }
  ids.add(snapshot.snapshotId);
  hashes.add(snapshot.sha256);
}
NODE

grep -Fq 'Copyright (c) 2026 Sunny Golovine' "$POLICY" || {
  echo "check-raw-source-policy: cc-offers MIT copyright notice is missing" >&2
  exit 1
}
grep -Fq 'The above copyright notice and this permission notice shall be included' "$MIT_NOTICE" || {
  echo "check-raw-source-policy: cc-offers MIT permission notice is incomplete" >&2
  exit 1
}
for notices in "$SWIFT_NOTICES" "$ANDROID_NOTICES"; do
  grep -Fq 'Copyright (c) 2026 Sunny Golovine' "$notices" || {
    echo "check-raw-source-policy: bundled cc-offers notice is missing from $notices" >&2
    exit 1
  }
done

if grep -Fq 'catalogue-pipeline/raw' "$ROOT/Engine/Package.swift" \
  || grep -Fq 'catalogue-pipeline/raw' "$ROOT/App/CardCopilot.xcodeproj/project.pbxproj"; then
  echo "check-raw-source-policy: raw pipeline material is referenced by an app resource graph" >&2
  exit 1
fi

if grep -Eq 'raw/us/opencard|clearfin-extracted|extract_clearfin' \
  "$ROOT/catalogue-pipeline/scripts/dedupe_and_report.py"; then
  echo "check-raw-source-policy: dedupe pipeline references a blocked source path" >&2
  exit 1
fi

if grep -Eq '"source": "(openCard|clearFin)"|"sourceOfCurrentValue": "clearFin' \
  "$ROOT/catalogue-pipeline/dedup-report.json" \
  "$ROOT/catalogue-pipeline/card-data-gaps.json" \
  "$ROOT/catalogue-pipeline/card-research-queue.json"; then
  echo "check-raw-source-policy: generated discovery reports still embed a blocked source" >&2
  exit 1
fi

echo "check-raw-source-policy: tracked raw sources match the reviewed allowlist"
