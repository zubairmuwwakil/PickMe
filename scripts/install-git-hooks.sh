#!/usr/bin/env bash
# Installs local git hooks in PickMe for 100% automatic hands-free contract releases & ecosystem sync.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="$ROOT/.git/hooks"

if [ ! -d "$HOOKS_DIR" ]; then
  echo "Error: .git directory not found at $ROOT/.git" >&2
  exit 1
fi

# 1. Pre-commit hook: runs release-and-sync automatically whenever contracts are modified
cat << 'EOF' > "$HOOKS_DIR/pre-commit"
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"

# Check if contracts/ has modified or staged files
if git diff --name-only --cached | grep -q '^contracts/' || git diff --name-only | grep -q '^contracts/'; then
  echo "🔄 [pre-commit hook] Detected contract changes. Running automatic release & sync..."
  "$ROOT/scripts/release-and-sync.sh"
  
  # Stage the updated contract stamps and engine bundles
  git add "$ROOT/contracts" "$ROOT/Engine" "$ROOT/android"
  echo "✓ Staged updated contract release and internal bundles automatically."
fi
EOF

# 2. Pre-push hook: ensures no un-stamped release can ever leave the local machine
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

chmod +x "$HOOKS_DIR/pre-commit" "$HOOKS_DIR/pre-push"
echo "✓ Installed PickMe local pre-commit and pre-push hooks at $HOOKS_DIR/."
