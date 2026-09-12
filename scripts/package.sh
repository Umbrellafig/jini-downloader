#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Default packaging is for local testing. Public releases must use --release.
MODE="${1:---local}"
case "$MODE" in
  --local) ;;
  --release)
    : "${DEVELOPER_ID_APPLICATION:?Set a Developer ID Application signing identity}"
    : "${NOTARY_PROFILE:?Set a notarytool Keychain profile}"
    ;;
  *) echo 'Usage: scripts/package.sh [--local|--release]' >&2; exit 1 ;;
esac
bash scripts/build.sh
if [[ "$MODE" == --release ]]; then
  bash scripts/notarize.sh
fi
ditto -c -k --sequesterRsrc --keepParent dist/JiniDownloader.app dist/JiniDownloader-macOS-arm64.zip
bash scripts/dmg.sh "$MODE"
(cd dist && shasum -a 256 JiniDownloader-macOS-arm64.zip JiniDownloader-macOS-arm64.dmg > SHA256SUMS.txt)
unzip -tq dist/JiniDownloader-macOS-arm64.zip
