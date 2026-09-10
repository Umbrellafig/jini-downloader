#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP_PATH="$PWD/dist/JiniDownloader.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
swiftc -parse-as-library -O -target arm64-apple-macosx13.0 -module-cache-path "${TMPDIR:-/tmp}/jini-swift-cache" Sources/Core.swift Sources/Engine.swift Sources/EngineInstaller.swift Sources/Model.swift Sources/main.swift -o "$APP_PATH/Contents/MacOS/JiniDownloader"
cp Resources/Info.plist "$APP_PATH/Contents/Info.plist"
cp Resources/engines.json "$APP_PATH/Contents/Resources/engines.json"
if [[ -f LICENSE ]]; then cp LICENSE "$APP_PATH/Contents/Resources/LICENSE.txt"; fi
if [[ -f docs/ENGINES.md ]]; then cp docs/ENGINES.md "$APP_PATH/Contents/Resources/ENGINES.md"; fi
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  if [[ "$DEVELOPER_ID_APPLICATION" != "Developer ID Application: "* ]]; then
    echo 'DEVELOPER_ID_APPLICATION must be a Developer ID Application identity.' >&2
    exit 1
  fi
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"
else
  codesign --force --sign - "$APP_PATH"
fi
codesign --verify --deep --strict "$APP_PATH"
