#!/usr/bin/env bash
# Installs local git hooks in PickMe to prevent un-stamped or stale contract pushes.
# Runs locally without using any GitHub Actions quota.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$ROOT/.git/hooks"

if [ ! -d "$HOOKS_DIR" ]; then
  echo "Error: .git directory not found at $ROOT/.git" >&2
  exit 1
fi

cat << 'EOF' > "$HOOKS_DIR/pre-push"
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
if [ -f "$ROOT/scripts/release-catalogue.sh" ]; then
  if ! "$ROOT/scripts/release-catalogue.sh" --check >/dev/null 2>&1; then
    echo "pre-push error: contracts/RELEASE.json is stale or contracts changed without bumping version." >&2
    echo "Run ./scripts/release-and-sync.sh locally before pushing." >&2
    exit 1
  fi
fi
EOF

chmod +x "$HOOKS_DIR/pre-push"
echo "✓ Installed PickMe local pre-push hook at $HOOKS_DIR/pre-push."
