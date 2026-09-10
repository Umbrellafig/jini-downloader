#!/bin/bash
set -euo pipefail
# Run only on the disposable GitHub-hosted macOS release runner. Never enable xtrace.
for NAME in CERTIFICATE_BASE64 CERTIFICATE_PASSWORD DEVELOPER_ID_APPLICATION APPLE_ID APPLE_TEAM_ID APPLE_APP_PASSWORD RUNNER_TEMP; do
  if [[ -z "${!NAME:-}" ]]; then
    echo "Missing required release setting: $NAME. Unsigned publication is disabled." >&2
    exit 1
  fi
done
KEYCHAIN="$RUNNER_TEMP/jini-signing.keychain-db"
CERTIFICATE="$RUNNER_TEMP/jini-certificate.p12"
KEYCHAIN_PASSWORD=$(openssl rand -hex 32)
echo "::add-mask::$KEYCHAIN_PASSWORD"
umask 077
trap 'rm -f "$CERTIFICATE"' EXIT
printf '%s' "$CERTIFICATE_BASE64" | /usr/bin/base64 --decode > "$CERTIFICATE"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$CERTIFICATE" -P "$CERTIFICATE_PASSWORD" -k "$KEYCHAIN" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
security list-keychains -d user -s "$KEYCHAIN" "$HOME/Library/Keychains/login.keychain-db"
xcrun notarytool store-credentials jini-release --keychain "$KEYCHAIN" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD"
