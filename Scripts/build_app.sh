#!/usr/bin/env bash
#
# Builds DiskInsight as a native Apple Silicon (arm64) .app bundle.
#
#   ./Scripts/build_app.sh            # release build into ./build/DiskInsight.app
#   ./Scripts/build_app.sh --install  # also copy into /Applications
#
set -euo pipefail

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--install" ) ]]; then
  echo "usage: $0 [--install]" >&2
  exit 1
fi

VERSION="${DISKINSIGHT_VERSION:-1.0.0}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: DISKINSIGHT_VERSION must be a version such as 1.0.0" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="DiskInsight"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"

echo "==> Building $APP_NAME (release, arm64)"
swift build -c release --arch arm64

BINARY="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"
if [[ ! -x "$BINARY" ]]; then
  echo "error: built binary not found at $BINARY" >&2
  exit 1
fi

echo "==> Assembling bundle"
rm -rf "$APP_DIR"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Generating icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
swift "$ROOT/Scripts/make_icon.swift" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - --options runtime --timestamp=none "$APP_DIR" 2>/dev/null \
  || codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "==> Verifying architecture"
lipo -archs "$CONTENTS/MacOS/$APP_NAME"

if [[ "${1:-}" == "--install" ]]; then
  echo "==> Installing to /Applications"
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP_DIR" "/Applications/$APP_NAME.app"
  echo "Installed: /Applications/$APP_NAME.app"
else
  echo "Built: $APP_DIR"
fi
