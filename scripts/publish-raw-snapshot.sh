#!/usr/bin/env bash
# Publish one cleared raw snapshot as an immutable, separately-namespaced release asset.
#
#   scripts/publish-raw-snapshot.sh cc-offers-us-2026-08-27 /path/to/cc-offers-export-2026-08-27.json
#
# The input is deliberately outside the repository. Do not restore a snapshot under
# catalogue-pipeline/raw merely to publish it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/catalogue-pipeline/raw/MANIFEST.json"

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <snapshot-id> <snapshot-file>" >&2
  exit 2
fi

snapshot_id="$1"
input_file="$2"
[ -f "$input_file" ] || { echo "publish-raw-snapshot: input file not found: $input_file" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "publish-raw-snapshot: gh CLI not found" >&2; exit 1; }

record="$(node - "$MANIFEST" "$snapshot_id" <<'NODE'
const [manifestPath, snapshotId] = process.argv.slice(2);
const manifest = require(manifestPath);
const matches = manifest.snapshots.filter((snapshot) => snapshot.snapshotId === snapshotId);
if (matches.length !== 1) {
  process.stderr.write(`publish-raw-snapshot: expected one manifest match for ${snapshotId}, found ${matches.length}\n`);
  process.exit(1);
}
const snapshot = matches[0];
process.stdout.write([
  snapshot.sourceUrl,
  snapshot.filename,
  snapshot.sha256,
  snapshot.licence.spdx,
  snapshot.licence.noticeFile,
  snapshot.release.repository,
  snapshot.release.tag,
  snapshot.release.asset,
  snapshot.release.snapshotPath,
  snapshot.release.licencePath,
].join('\t'));
NODE
)"
IFS=$'\t' read -r source_url filename expected_sha licence notice_file repository release asset snapshot_path licence_path <<< "$record"

[ "$(basename "$input_file")" = "$filename" ] || {
  echo "publish-raw-snapshot: manifest expects filename $filename" >&2
  exit 1
}
[ -f "$ROOT/$notice_file" ] || { echo "publish-raw-snapshot: missing licence notice $notice_file" >&2; exit 1; }
actual_sha="$(shasum -a 256 "$input_file" | awk '{print $1}')"
[ "$actual_sha" = "$expected_sha" ] || {
  echo "publish-raw-snapshot: SHA-256 mismatch for $snapshot_id" >&2
  echo "  expected: $expected_sha" >&2
  echo "  actual:   $actual_sha" >&2
  exit 1
}

if gh release view "$release" --repo "$repository" >/dev/null 2>&1; then
  echo "publish-raw-snapshot: $release already exists; raw releases are immutable" >&2
  exit 1
fi

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/pickme-raw-publish.XXXXXX")"
trap 'rm -rf "$temporary_dir"' EXIT
cp "$input_file" "$temporary_dir/$snapshot_path"
cp "$ROOT/$notice_file" "$temporary_dir/$licence_path"
(cd "$temporary_dir" && tar -czf "$asset" "$snapshot_path" "$licence_path")

notes="Raw snapshot release \`$release\`.

Snapshot: \`$snapshot_id\`
Source: $source_url
Licence: $licence (the archive includes \`$licence_path\`)
Extracted snapshot SHA-256: \`$expected_sha\`

Retrieve and verify it with:

    scripts/fetch-raw-snapshot.sh $expected_sha
"
gh release create "$release" --repo "$repository" --title "$release" --notes "$notes" "$temporary_dir/$asset#$asset"
echo "publish-raw-snapshot: published $release/$asset (sha256:$expected_sha)"
