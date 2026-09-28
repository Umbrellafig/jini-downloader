#!/bin/bash
# Version scheme MAJOR.MINOR.PATCH.BUILD: every shipped change bumps at least BUILD.
# Usage: scripts/bump-version.sh [build|patch|minor|major]  (default: build)
set -euo pipefail
cd "$(dirname "$0")/.."
PLIST=Resources/Info.plist
PART=${1:-build}
IFS=. read -r MAJOR MINOR PATCH BUILD <<< "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$PLIST")"
MAJOR=${MAJOR:-0}; MINOR=${MINOR:-0}; PATCH=${PATCH:-0}; BUILD=${BUILD:-0}
case "$PART" in
  build) VERSION="$MAJOR.$MINOR.$PATCH.$((BUILD + 1))" ;;
  patch) VERSION="$MAJOR.$MINOR.$((PATCH + 1))" ;;
  minor) VERSION="$MAJOR.$((MINOR + 1)).0" ;;
  major) VERSION="$((MAJOR + 1)).0.0" ;;
  *) echo "usage: $0 [build|patch|minor|major]" >&2; exit 1 ;;
esac
# Sparkle compares CFBundleVersion, so it must increase on every release.
NUMBER=$(( $(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$PLIST") + 1 ))
# Edit the values in place; PlistBuddy would reorder every key.
sed -i '' -e "/<key>CFBundleShortVersionString<\/key>/{n;s|<string>.*</string>|<string>$VERSION</string>|;}" \
  -e "/<key>CFBundleVersion<\/key>/{n;s|<string>.*</string>|<string>$NUMBER</string>|;}" "$PLIST"
echo "$VERSION ($NUMBER)"
