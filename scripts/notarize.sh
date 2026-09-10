#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${NOTARY_PROFILE:?Set a notarytool Keychain profile}"
APP_PATH="$PWD/dist/JiniDownloader.app"
codesign --verify --deep --strict "$APP_PATH"
SIGNATURE=$(codesign -dv --verbose=4 "$APP_PATH" 2>&1)
if ! [[ "$SIGNATURE" == *"Authority=Developer ID Application:"* && "$SIGNATURE" == *"runtime"* ]]; then
  echo 'Public releases require a Developer ID Application signature and hardened runtime.' >&2
  exit 1
fi
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/jini-notary.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$STAGING/submission.zip"
NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then
  NOTARY_ARGS+=(--keychain "$NOTARY_KEYCHAIN")
fi
xcrun notarytool submit "$STAGING/submission.zip" "${NOTARY_ARGS[@]}" --wait --timeout 30m --output-format json > "$STAGING/result.json"
if ! /usr/bin/plutil -extract status raw -o - "$STAGING/result.json" | /usr/bin/grep -qx Accepted; then
  cat "$STAGING/result.json" >&2
  echo 'Notarization was not accepted. No public package was produced.' >&2
  exit 1
fi
# ZIP files cannot carry a ticket. Staple the app before making the final ZIP.
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"
