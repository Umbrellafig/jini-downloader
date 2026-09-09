#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh
ditto -c -k --sequesterRsrc --keepParent dist/JiniDownloader.app dist/JiniDownloader-macOS-arm64.zip
(cd dist && shasum -a 256 JiniDownloader-macOS-arm64.zip > SHA256SUMS.txt)
unzip -tq dist/JiniDownloader-macOS-arm64.zip
