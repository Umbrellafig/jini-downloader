#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
SIGNER="$PWD/.build/Sparkle-2.9.6/bin/generate_appcast"
[[ -x "$SIGNER" ]] || bash scripts/fetch-sparkle.sh
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/jini-appcast.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
cp dist/JiniDownloader-macOS-arm64.zip "$STAGING/"
cp docs/RELEASE_NOTES.md "$STAGING/JiniDownloader-macOS-arm64.md"
ARGS=(--embed-release-notes --download-url-prefix "https://github.com/Umbrellafig/jini-downloader/releases/download/v$VERSION/" --maximum-deltas 0)
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SIGNER" --ed-key-file - "${ARGS[@]}" "$STAGING"
else
  "$SIGNER" --account io.github.umbrellafig.jini-downloader "${ARGS[@]}" "$STAGING"
fi
cp "$STAGING/appcast.xml" dist/appcast.xml
