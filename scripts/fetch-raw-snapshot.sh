#!/usr/bin/env bash
# Retrieve a release-hosted raw snapshot, then verify the extracted bytes by SHA-256.
#
#   scripts/fetch-raw-snapshot.sh cc-offers-us-2026-08-27
#   scripts/fetch-raw-snapshot.sh d075e2296d0f70bccf061b01eee56811a246c3f460d2f63a7f522d8aed739d06
#   scripts/fetch-raw-snapshot.sh cc-offers-us-2026-08-27 --output-dir /tmp/cc-offers
#
# Raw bytes intentionally never live in git. The release asset is a small archive so the
# upstream licence notice travels with the substantial data copy. The manifest's sha256 is
# for the extracted snapshot, not the transport archive.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/catalogue-pipeline/raw/MANIFEST.json"

usage() {
  echo "usage: $0 <snapshot-id|sha256> [--output-dir DIR]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
query="$1"
shift
output_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-dir)
      [ "$#" -ge 2 ] || usage
      output_dir="$2"
      shift 2
      ;;
    *) usage ;;
  esac
done

command -v gh >/dev/null 2>&1 || { echo "fetch-raw-snapshot: gh CLI not found" >&2; exit 1; }

record="$(node - "$MANIFEST" "$query" <<'NODE'
const [manifestPath, query] = process.argv.slice(2);
const manifest = require(manifestPath);
const normalized = query.replace(/^sha256:/, '');
const matches = manifest.snapshots.filter((snapshot) =>
  snapshot.snapshotId === query || snapshot.sha256 === normalized,
);
if (matches.length !== 1) {
  process.stderr.write(`fetch-raw-snapshot: expected one manifest match for ${query}, found ${matches.length}\n`);
  process.exit(1);
}
const snapshot = matches[0];
process.stdout.write([
  snapshot.snapshotId,
  snapshot.release.repository,
  snapshot.release.tag,
  snapshot.release.asset,
  snapshot.release.snapshotPath,
  snapshot.release.licencePath,
  snapshot.sha256,
].join('\t'));
NODE
)"
IFS=$'\t' read -r snapshot_id repository release asset snapshot_path licence_path expected_sha <<< "$record"

if [ -z "$output_dir" ]; then
  output_dir="$ROOT/catalogue-pipeline/.raw-cache/$snapshot_id"
fi
mkdir -p "$output_dir"
destination="$output_dir/$snapshot_path"

if [ -e "$destination" ]; then
  actual_sha="$(shasum -a 256 "$destination" | awk '{print $1}')"
  if [ "$actual_sha" = "$expected_sha" ]; then
    echo "fetch-raw-snapshot: already verified $destination (sha256:$actual_sha)"
    exit 0
  fi
  echo "fetch-raw-snapshot: refusing to overwrite $destination (sha256:$actual_sha, expected $expected_sha)" >&2
  exit 1
fi

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/pickme-raw-fetch.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT
archive="$temporary_dir/$asset"

gh release download "$release" --repo "$repository" --pattern "$asset" --dir "$temporary_dir"
[ -f "$archive" ] || { echo "fetch-raw-snapshot: release did not provide $asset" >&2; exit 1; }

# Do not extract a release archive until its complete member list is the two expected files.
expected_members="$(printf '%s\n%s\n' "$licence_path" "$snapshot_path" | LC_ALL=C sort)"
actual_members="$(tar -tzf "$archive" | LC_ALL=C sort)"
if [ "$actual_members" != "$expected_members" ]; then
  echo "fetch-raw-snapshot: release archive has unexpected members" >&2
  exit 1
fi

tar -xzf "$archive" -C "$output_dir" "$snapshot_path" "$licence_path"
actual_sha="$(shasum -a 256 "$destination" | awk '{print $1}')"
if [ "$actual_sha" != "$expected_sha" ]; then
  rm -f "$destination" "$output_dir/$licence_path"
  echo "fetch-raw-snapshot: SHA-256 mismatch for $snapshot_id" >&2
  echo "  expected: $expected_sha" >&2
  echo "  actual:   $actual_sha" >&2
  exit 1
fi

echo "fetch-raw-snapshot: verified $destination (sha256:$actual_sha)"
