#!/usr/bin/env bash
# Publishes the stamped contract set as an immutable GitHub Release.
#
#   scripts/publish-catalogue.sh            # publish contracts/RELEASE.json's release
#   scripts/publish-catalogue.sh --dry-run  # show what would happen, touch nothing
#
# WHY OUT OF THE REPO
#
# Consumers currently vendor these files by copying them between working copies. That is how the
# catalogue reached FOUR copies across two repos, how ids drifted three times in five days, and
# how a manifest came to record a commit alongside bytes that appear in no commit. A release
# fetched by name from one place is checkable by any consumer, including ones with no checkout of
# this repo — an Android build, a web deploy, or a consumer nobody has written yet.
#
# IMMUTABILITY IS THE WHOLE POINT
#
# A published release id must never describe two different sets of bytes. This refuses to
# overwrite an existing release whose digest differs; bump catalogueVersion instead. That is the
# same rule release-catalogue.sh --check enforces locally, at the other end of the pipe.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS="$ROOT/contracts"
REPO="${CATALOGUE_REPO:-zubairmuwwakil/PickMe}"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

command -v gh >/dev/null 2>&1 || { echo "publish-catalogue: gh CLI not found" >&2; exit 1; }

# Never publish a stamp that does not describe the files next to it.
"$ROOT/scripts/release-catalogue.sh" --check >/dev/null || {
  echo "publish-catalogue: RELEASE.json is not current — run scripts/release-catalogue.sh first" >&2
  exit 1
}

release="$(node -e 'process.stdout.write(require(process.argv[1]).release)' "$CONTRACTS/RELEASE.json")"
digest="$(node -e 'process.stdout.write(require(process.argv[1]).digest)' "$CONTRACTS/RELEASE.json")"
mapfile -t files < <(node -e 'Object.keys(require(process.argv[1]).files).forEach(f=>console.log(f))' "$CONTRACTS/RELEASE.json" 2>/dev/null || node -e 'Object.keys(require(process.argv[1]).files).forEach(f=>console.log(f))' "$CONTRACTS/RELEASE.json")

echo "publish-catalogue: $release ($digest) -> $REPO"

if gh release view "$release" --repo "$REPO" >/dev/null 2>&1; then
  published_digest="$(gh release view "$release" --repo "$REPO" --json body -q .body 2>/dev/null | grep -o 'sha256:[0-9a-f]\{64\}' | head -1 || true)"
  if [ "$published_digest" = "$digest" ]; then
    echo "publish-catalogue: $release already published with this exact digest — nothing to do"
    exit 0
  fi
  echo "publish-catalogue: $release is ALREADY PUBLISHED with a different digest." >&2
  echo "publish-catalogue:   published: ${published_digest:-<none recorded>}" >&2
  echo "publish-catalogue:   local:     $digest" >&2
  echo "publish-catalogue: a published release id must never describe two different sets of" >&2
  echo "publish-catalogue: bytes. Bump catalogueVersion in card-catalogue.json and re-stamp." >&2
  exit 1
fi

notes="$(printf 'Card contract release \`%s\`.\n\nDigest over the published file set:\n\n    %s\n\nVerify a vendored copy without this repo, a network call, or git:\n\n    sha256 of sorted "name<TAB>sha256" lines == the digest above\n\nMoneyTalks does exactly this in `src/lib/contracts/contracts.test.ts`.\n' "$release" "$digest")"

if [ "$DRY" -eq 1 ]; then
  echo "publish-catalogue: DRY RUN — would create release '$release' with ${#files[@]} assets:"
  printf '  %s\n' "${files[@]}"
  exit 0
fi

assets=()
for f in "${files[@]}"; do assets+=("$CONTRACTS/$f#$(basename "$f")"); done
assets+=("$CONTRACTS/RELEASE.json#RELEASE.json")

gh release create "$release" --repo "$REPO" --title "$release" --notes "$notes" "${assets[@]}"
echo "publish-catalogue: published $release"
