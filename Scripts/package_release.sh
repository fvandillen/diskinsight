#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 <version> (for example, 1.0.0)" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$1"
DISKINSIGHT_VERSION="$VERSION" "$ROOT/Scripts/build_app.sh"

cp "$ROOT/LICENSE" "$ROOT/build/DiskInsight.app/Contents/Resources/LICENSE"
codesign --force --deep --sign - --options runtime --timestamp=none "$ROOT/build/DiskInsight.app"
codesign --verify --deep --strict "$ROOT/build/DiskInsight.app"

ARCHIVE="DiskInsight-$VERSION-arm64.zip"
rm -f "$ROOT/build/$ARCHIVE"
ditto -c -k --sequesterRsrc --keepParent "$ROOT/build/DiskInsight.app" "$ROOT/build/$ARCHIVE"
cd "$ROOT/build"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
echo "Release: $ROOT/build/$ARCHIVE"
cat "$ARCHIVE.sha256"
