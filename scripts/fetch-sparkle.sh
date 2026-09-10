#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=2.9.6
SHA=52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192
ARCHIVE="$PWD/.build/Sparkle-$VERSION.tar.xz"
DEST="$PWD/.build/Sparkle-$VERSION"
mkdir -p .build
if [[ ! -f "$ARCHIVE" ]]; then
  curl --fail --location --proto '=https' --tlsv1.2 --retry 2 "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" -o "$ARCHIVE.partial"
  mv "$ARCHIVE.partial" "$ARCHIVE"
fi
printf '%s  %s\n' "$SHA" "$ARCHIVE" | shasum -a 256 -c -
# Re-extract verified content, preserving the framework's symlinks.
mkdir -p "$DEST"
tar -xf "$ARCHIVE" -C "$DEST"
