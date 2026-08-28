#!/usr/bin/env bash
# Stamps the contract set as an immutable, content-addressed release.
#
#   scripts/release-catalogue.sh           # write contracts/RELEASE.json
#   scripts/release-catalogue.sh --check   # verify it is current; non-zero if stale
#
# WHY THIS EXISTS
#
# Consumers used to vendor these files and prove provenance with "PickMe commit
# X" — a claim that needs PickMe present to check, and that can be false while
# looking fine. On 2026-08-24 a consumer manifest was found recording commit
# 670d1fe alongside bytes that appear in NO PickMe commit; its local check and
# its cross-repo check both stayed green while the two repos disagreed about 13
# whole cards.
#
# A content digest cannot lie about the bytes it describes. "Do we have release
# 1.5.0?" is answerable from the files alone — no second checkout, no network,
# no git — and answered identically by every consumer: web, iOS, Android, or a
# future one nobody has written yet. That last point is the reason to do it
# now: there are already FOUR copies of this catalogue in two repos.
#
# The release id carries catalogueVersion, so content that moves without the
# version moving is an error rather than a silent overwrite of a published id.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS="$ROOT/contracts"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# The published set. Keep in sync with MoneyTalks' FILES list in
# scripts/sync-contracts.sh — contracts.test.ts asserts they agree.
FILES=(
  "card-catalogue.json"
  "benefits-catalogue.json"
  "engine-fixtures.json"
  "owner-state.json"
  "programs.json"
  "candidate-catalogue.json"
  "schema/card-catalogue.schema.json"
  "schema/benefits-catalogue.schema.json"
  "schema/engine-fixtures.schema.json"
  # programs.json shipped in the digest from the start; its schema did not, so a
  # change to the schema alone moved no digest and no consumer could detect it.
  # Added for 2.7, the first release whose whole point is a schema change
  # (merchantCredit, noRewards). merchant-pack.schema.json stays OUT on purpose:
  # the pack carries its own packVersion and changes on a different cadence — see
  # the note in MoneyTalks' src/lib/contracts/contracts.test.ts.
  "schema/programs.schema.json"
  # Added for 2.8. The registry decides which owner conditions a consumer can ASK
  # about, so a consumer pinning this release must get the same set of questions
  # the engine gates on — that is exactly what the digest is for.
  "owner-conditions.json"
  "schema/owner-conditions.schema.json"
)

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

catalogue_version="$(node -e 'process.stdout.write(require(process.argv[1]).catalogueVersion)' "$CONTRACTS/card-catalogue.json")"
release="card-contracts@${catalogue_version}"

# Digest over "name<TAB>sha256" lines, sorted by name. Sorted so the digest does
# not depend on the FILES order, and over names as well as bytes so renaming a
# file changes the release.
manifest_lines=""
for f in "${FILES[@]}"; do
  [ -f "$CONTRACTS/$f" ] || { echo "release-catalogue: missing $f" >&2; exit 1; }
  manifest_lines+="$f	$(sha256_of "$CONTRACTS/$f")
"
done
digest="$(printf '%s' "$manifest_lines" | LC_ALL=C sort | { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; } | awk '{print $1}')"

emit() {
  echo "{"
  printf '  "release": "%s",\n' "$release"
  printf '  "catalogueVersion": "%s",\n' "$catalogue_version"
  printf '  "digest": "sha256:%s",\n' "$digest"
  echo '  "files": {'
  last=$(( ${#FILES[@]} - 1 ))
  for i in "${!FILES[@]}"; do
    sep=","; [ "$i" -eq "$last" ] && sep=""
    printf '    "%s": "%s"%s\n' "${FILES[$i]}" "$(sha256_of "$CONTRACTS/${FILES[$i]}")" "$sep"
  done
  echo "  }"
  echo "}"
}

if [ "$CHECK" -eq 1 ]; then
  [ -f "$CONTRACTS/RELEASE.json" ] || { echo "release-catalogue: RELEASE.json missing — run scripts/release-catalogue.sh" >&2; exit 1; }
  recorded_digest="$(node -e 'process.stdout.write(require(process.argv[1]).digest)' "$CONTRACTS/RELEASE.json")"
  recorded_release="$(node -e 'process.stdout.write(require(process.argv[1]).release)' "$CONTRACTS/RELEASE.json")"
  if [ "$recorded_digest" = "sha256:$digest" ]; then
    echo "release-catalogue: current — $recorded_release ($recorded_digest)"
    exit 0
  fi
  if [ "$recorded_release" = "$release" ]; then
    echo "release-catalogue: contract files changed but catalogueVersion is still $catalogue_version." >&2
    echo "release-catalogue: $release is already published with a different digest. Bump" >&2
    echo "release-catalogue: catalogueVersion in card-catalogue.json — a published release id" >&2
    echo "release-catalogue: must never describe two different sets of bytes." >&2
    exit 1
  fi
  echo "release-catalogue: RELEASE.json is stale ($recorded_release -> $release). Re-run without --check." >&2
  exit 1
fi

emit > "$CONTRACTS/RELEASE.json.tmp"
mv "$CONTRACTS/RELEASE.json.tmp" "$CONTRACTS/RELEASE.json"
echo "release-catalogue: wrote $release (sha256:${digest:0:16}…) over ${#FILES[@]} files"
