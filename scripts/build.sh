#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/fetch-sparkle.sh
SPARKLE="$PWD/.build/Sparkle-2.9.6"
APP_PATH="$PWD/dist/JiniDownloader.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
SDK_ARGS=()
if [[ -n "${SDKROOT:-}" ]]; then SDK_ARGS=(-sdk "$SDKROOT"); fi
swiftc -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks "${SDK_ARGS[@]}" -parse-as-library -O -target arm64-apple-macosx13.0 -module-cache-path "${TMPDIR:-/tmp}/jini-swift-cache" Sources/Core.swift Sources/Engine.swift Sources/EngineInstaller.swift Sources/Model.swift Sources/AppUpdater.swift Sources/main.swift -o "$APP_PATH/Contents/MacOS/JiniDownloader"
mkdir -p "$APP_PATH/Contents/Frameworks"
ditto "$SPARKLE/Sparkle.framework" "$APP_PATH/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE/LICENSE" "$APP_PATH/Contents/Resources/Sparkle-LICENSE.txt"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp Resources/engines.json "$APP_PATH/Contents/Resources/engines.json"
if [[ -f LICENSE ]]; then cp LICENSE "$APP_PATH/Contents/Resources/LICENSE.txt"; fi
if [[ -f docs/ENGINES.md ]]; then cp docs/ENGINES.md "$APP_PATH/Contents/Resources/ENGINES.md"; fi
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  if [[ "$DEVELOPER_ID_APPLICATION" != "Developer ID Application: "* ]]; then
    echo 'DEVELOPER_ID_APPLICATION must be a Developer ID Application identity.' >&2
    exit 1
  fi
  # Preserve Sparkle helper entitlements while signing nested code inside-out.
  FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework/Versions/B"
  for CODE in "$FRAMEWORK/XPCServices/Downloader.xpc" "$FRAMEWORK/XPCServices/Installer.xpc" "$FRAMEWORK/Autoupdate" "$FRAMEWORK/Updater.app" "$APP_PATH/Contents/Frameworks/Sparkle.framework"; do
    codesign --force --options runtime --timestamp --preserve-metadata=entitlements --sign "$DEVELOPER_ID_APPLICATION" "$CODE"
  done
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"
else
  codesign --force --sign - "$APP_PATH"
fi
codesign --verify --deep --strict "$APP_PATH"
