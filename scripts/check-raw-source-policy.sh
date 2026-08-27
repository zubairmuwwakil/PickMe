#!/usr/bin/env bash
# Prevents uncleared third-party source material from entering this public repository.
# The allowlist is intentionally closed: a new raw source needs a licence review first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LICENCES="$ROOT/catalogue-pipeline/raw/LICENCES.md"
SOURCES="$ROOT/catalogue-pipeline/raw/SOURCES.json"
SWIFT_NOTICES="$ROOT/Engine/Sources/CardCopilotEngine/Resources/THIRD_PARTY_NOTICES.md"
ANDROID_NOTICES="$ROOT/android/core/engine/src/main/resources/com/cardcopilot/engine/THIRD_PARTY_NOTICES.md"

allowed_raw_path() {
  case "$1" in
    catalogue-pipeline/raw/LICENCES.md | \
    catalogue-pipeline/raw/SOURCES.json | \
    catalogue-pipeline/raw/us/cc-offers/cc-offers-export-2026-08-27.json | \
    catalogue-pipeline/raw/ca/clearfin/clearfin_slugs.txt)
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
  echo "Review catalogue-pipeline/raw/LICENCES.md before changing the allowlist." >&2
  exit 1
fi

python3 -m json.tool "$SOURCES" >/dev/null

grep -Fq 'Copyright (c) 2026 Sunny Golovine' "$LICENCES" || {
  echo "check-raw-source-policy: cc-offers MIT copyright notice is missing" >&2
  exit 1
}
grep -Fq 'The above copyright notice and this permission notice shall be included' "$LICENCES" || {
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
