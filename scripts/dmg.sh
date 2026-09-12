#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:---local}"
STAGE=$(mktemp -d "${TMPDIR:-/tmp}/jini-dmg.XXXXXX")
MOUNT="$STAGE/volume"
cleanup() { hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rm -rf "$STAGE"; }
trap cleanup EXIT
mkdir -p "$STAGE/content/.background"
ditto dist/JiniDownloader.app "$STAGE/content/JiniDownloader.app"
ln -s /Applications "$STAGE/content/Applications"
printf '%s\n' '1. JiniDownloader.app을 Applications 폴더로 드래그하세요.' '2. 응용 프로그램 폴더에서 지니 다운로더를 실행하세요.' '3. 설치 디스크는 추출해도 됩니다. 다음부터 앱 안에서 업데이트할 수 있어요.' > "$STAGE/content/설치 안내.txt"
xcrun swift -module-cache-path "$STAGE/swift-cache" scripts/dmg-background.swift "$STAGE/content/.background/install.png"
python3 -m pip install --quiet --target "$STAGE/python" 'ds-store==1.3.1' 'mac-alias==2.2.2'
hdiutil create -quiet -volname '지니 다운로더 설치' -srcfolder "$STAGE/content" -format UDRW -fs HFS+ "$STAGE/writable.dmg"
hdiutil attach -quiet -nobrowse -mountpoint "$MOUNT" "$STAGE/writable.dmg"
PYTHONPATH="$STAGE/python" python3 - "$MOUNT" <<'PY'
import sys
from ds_store import DSStore
from mac_alias import Alias
root=sys.argv[1]
with DSStore.open(root+'/.DS_Store', 'w+') as store:
    store['.']['bwsp']={'ShowToolbar':False,'ShowSidebar':False,'ShowStatusBar':False,'ShowPathbar':False,'WindowBounds':'{{200, 150}, {660, 420}}'}
    store['.']['icvp']={'viewOptionsVersion':1,'backgroundType':2,'backgroundImageAlias':Alias.for_file(root+'/.background/install.png').to_bytes(),'iconSize':100.0,'textSize':14.0,'labelOnBottom':True,'arrangeBy':'none','gridSpacing':100.0,'gridOffsetX':0.0,'gridOffsetY':0.0,'showItemInfo':False,'showIconPreview':False}
    store['.']['vSrn']=('long',1)
    store['.']['vstl']=('type',b'icnv')
    store['JiniDownloader.app']['Iloc']=(170,190)
    store['Applications']['Iloc']=(490,190)
    store['설치 안내.txt']['Iloc']=(330,340)
PY
hdiutil detach -quiet "$MOUNT"
hdiutil convert -quiet "$STAGE/writable.dmg" -format UDZO -o "$STAGE/final.dmg"
if [[ "$MODE" == --release ]]; then
    : "${DEVELOPER_ID_APPLICATION:?}"
    : "${NOTARY_PROFILE:?}"
    codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$STAGE/final.dmg"
    ARGS=(--keychain-profile "$NOTARY_PROFILE")
    if [[ -n "${NOTARY_KEYCHAIN:-}" ]]; then ARGS+=(--keychain "$NOTARY_KEYCHAIN"); fi
    xcrun notarytool submit "$STAGE/final.dmg" "${ARGS[@]}" --wait --timeout 30m --output-format json > "$STAGE/notary.json"
    [[ "$(plutil -extract status raw -o - "$STAGE/notary.json")" == Accepted ]]
    xcrun stapler staple "$STAGE/final.dmg"
    xcrun stapler validate "$STAGE/final.dmg"
fi
mv "$STAGE/final.dmg" dist/JiniDownloader-macOS-arm64.dmg
hdiutil verify dist/JiniDownloader-macOS-arm64.dmg
