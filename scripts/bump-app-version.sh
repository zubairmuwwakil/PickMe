#!/usr/bin/env bash
#
# scripts/bump-app-version.sh
# Synchronizes the public marketing version across iOS and Android.
#
# Updates:
#   - App/Configuration/Versioning.xcconfig  (APP_MARKETING_VERSION)
#   - android/app/build.gradle.kts           (versionName, versionCode)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IOS_CONFIG="$ROOT/App/Configuration/Versioning.xcconfig"
ANDROID_CONFIG="$ROOT/android/app/build.gradle.kts"

show_help() {
  cat <<EOF
Usage:
  ./scripts/bump-app-version.sh <version> [options]

Arguments:
  <version>            The new marketing version (e.g., "2.1", "2.1.0")

Options:
  --dry-run            Print the planned updates without modifying any files
  --bump-ios-build     Also increment iOS APP_BUILD_NUMBER in Versioning.xcconfig
  --no-code-bump       Keep Android versionCode as-is instead of auto-incrementing
  --build-number <N>   Set a specific build number for Android versionCode (and iOS if --bump-ios-build is set)
  -h, --help           Show this help message

Examples:
  ./scripts/bump-app-version.sh 2.1.0
  ./scripts/bump-app-version.sh 2.1.0 --dry-run
  ./scripts/bump-app-version.sh 2.1.0 --bump-ios-build
EOF
}

if [ $# -eq 0 ]; then
  show_help
  exit 1
fi

NEW_VERSION=""
DRY_RUN=false
BUMP_IOS_BUILD=false
AUTO_BUMP_ANDROID_CODE=true
EXPLICIT_BUILD_NUMBER=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --bump-ios-build)
      BUMP_IOS_BUILD=true
      shift
      ;;
    --no-code-bump)
      AUTO_BUMP_ANDROID_CODE=false
      shift
      ;;
    --build-number)
      if [ -z "${2:-}" ]; then
        echo "Error: --build-number requires an integer argument." >&2
        exit 1
      fi
      EXPLICIT_BUILD_NUMBER="$2"
      shift 2
      ;;
    -*)
      echo "Error: Unknown option $1" >&2
      show_help
      exit 1
      ;;
    *)
      if [ -z "$NEW_VERSION" ]; then
        NEW_VERSION="$1"
      else
        echo "Error: Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$NEW_VERSION" ]; then
  echo "Error: Missing required <version> argument." >&2
  show_help
  exit 1
fi

# Validate version format (e.g. 2.1, 2.1.0, 2.1.0.1)
if ! [[ "$NEW_VERSION" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
  echo "Error: Invalid version format '$NEW_VERSION'. Expected format like '2.1' or '2.1.0'." >&2
  exit 1
fi

if [ ! -f "$IOS_CONFIG" ]; then
  echo "Error: iOS config file not found at $IOS_CONFIG" >&2
  exit 1
fi

if [ ! -f "$ANDROID_CONFIG" ]; then
  echo "Error: Android config file not found at $ANDROID_CONFIG" >&2
  exit 1
fi

# Extract current iOS settings
CURRENT_IOS_VERSION="$(sed -n 's/^[[:space:]]*APP_MARKETING_VERSION[[:space:]]*=[[:space:]]*\([^[:space:]]*\).*/\1/p' "$IOS_CONFIG")"
CURRENT_IOS_BUILD="$(sed -n 's/^[[:space:]]*APP_BUILD_NUMBER[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$IOS_CONFIG")"

# Extract current Android settings
CURRENT_ANDROID_VERSION="$(sed -n 's/^[[:space:]]*versionName[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$ANDROID_CONFIG")"
CURRENT_ANDROID_CODE="$(sed -n 's/^[[:space:]]*versionCode[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$ANDROID_CONFIG")"

# Determine target Android versionCode
if [ -n "$EXPLICIT_BUILD_NUMBER" ]; then
  NEW_ANDROID_CODE="$EXPLICIT_BUILD_NUMBER"
elif [ "$AUTO_BUMP_ANDROID_CODE" = true ]; then
  NEW_ANDROID_CODE=$((CURRENT_ANDROID_CODE + 1))
else
  NEW_ANDROID_CODE="$CURRENT_ANDROID_CODE"
fi

# Determine target iOS APP_BUILD_NUMBER
if [ -n "$EXPLICIT_BUILD_NUMBER" ]; then
  NEW_IOS_BUILD="$EXPLICIT_BUILD_NUMBER"
elif [ "$BUMP_IOS_BUILD" = true ]; then
  NEW_IOS_BUILD=$((CURRENT_IOS_BUILD + 1))
else
  NEW_IOS_BUILD="$CURRENT_IOS_BUILD"
fi

echo "=== Version Bump Plan ==="
echo "iOS (App/Configuration/Versioning.xcconfig):"
echo "  Marketing Version : ${CURRENT_IOS_VERSION} -> ${NEW_VERSION}"
if [ "$NEW_IOS_BUILD" != "$CURRENT_IOS_BUILD" ]; then
  echo "  Build Number      : ${CURRENT_IOS_BUILD} -> ${NEW_IOS_BUILD}"
else
  echo "  Build Number      : ${CURRENT_IOS_BUILD} (unchanged, auto-incremented by Xcode archive scheme)"
fi

echo ""
echo "Android (android/app/build.gradle.kts):"
echo "  versionName       : ${CURRENT_ANDROID_VERSION} -> ${NEW_VERSION}"
if [ "$NEW_ANDROID_CODE" != "$CURRENT_ANDROID_CODE" ]; then
  echo "  versionCode       : ${CURRENT_ANDROID_CODE} -> ${NEW_ANDROID_CODE}"
else
  echo "  versionCode       : ${CURRENT_ANDROID_CODE} (unchanged)"
fi

if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "Dry-run enabled: No files modified."
  exit 0
fi

# Apply iOS updates
python3 -c "
import re

ios_path = '$IOS_CONFIG'
with open(ios_path, 'r', encoding='utf-8') as f:
    content = f.read()

content = re.sub(
    r'(APP_MARKETING_VERSION\s*=\s*).*',
    r'\g<1>$NEW_VERSION',
    content
)

if '$NEW_IOS_BUILD' != '$CURRENT_IOS_BUILD':
    content = re.sub(
        r'(APP_BUILD_NUMBER\s*=\s*).*',
        r'\g<1>$NEW_IOS_BUILD',
        content
    )

with open(ios_path, 'w', encoding='utf-8') as f:
    f.write(content)
"

# Apply Android updates
python3 -c "
import re

android_path = '$ANDROID_CONFIG'
with open(android_path, 'r', encoding='utf-8') as f:
    content = f.read()

content = re.sub(
    r'(versionName\s*=\s*\")[^\"]*(\")',
    r'\g<1>$NEW_VERSION\g<2>',
    content
)

if '$NEW_ANDROID_CODE' != '$CURRENT_ANDROID_CODE':
    content = re.sub(
        r'(versionCode\s*=\s*)\d+',
        r'\g<1>$NEW_ANDROID_CODE',
        content
    )

with open(android_path, 'w', encoding='utf-8') as f:
    f.write(content)
"

echo ""
echo "✓ Successfully synced marketing version to ${NEW_VERSION} across iOS and Android!"
