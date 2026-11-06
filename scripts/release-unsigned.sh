#!/usr/bin/env bash
# 不依赖 Apple Developer ID 的 launch 发布构建。
# 产物：build/release/launch-<version>.zip / .dmg / checksums.txt
# app 使用 ad-hoc 签名；首次打开需要用户在“系统设置 → 隐私与安全性”放行。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

DERIVED_DIR="$ROOT_DIR/build/unsigned-derived"
RELEASE_DIR="$ROOT_DIR/build/release"

echo "Building universal SwiftUpdater..."
swift build \
  --package-path UpdaterScripts/SwiftUpdater \
  -c release \
  --arch arm64 \
  --arch x86_64

# SwiftPM 版本不同，universal 产物可能在 .build/out 或 .build/apple。
UPDATER_SRC=""
for candidate in \
  "UpdaterScripts/SwiftUpdater/.build/out/Products/Release/SwiftUpdater" \
  "UpdaterScripts/SwiftUpdater/.build/apple/Products/Release/SwiftUpdater"; do
  if [[ -f "$candidate" ]]; then
    UPDATER_SRC="$candidate"
    break
  fi
done
if [[ -z "$UPDATER_SRC" ]]; then
  UPDATER_SRC="$(find UpdaterScripts/SwiftUpdater/.build -path '*/Products/Release/SwiftUpdater' -type f | head -1)"
fi
if [[ -z "$UPDATER_SRC" || ! -f "$UPDATER_SRC" ]]; then
  echo "error: universal SwiftUpdater binary not found" >&2
  exit 1
fi
DEST_UPDATER="UpdaterScripts/SwiftUpdater/.build/apple/Products/Release/SwiftUpdater"
mkdir -p "$(dirname "$DEST_UPDATER")"
if [[ "$UPDATER_SRC" -ef "$DEST_UPDATER" ]]; then
  echo "SwiftUpdater already in place: $DEST_UPDATER"
else
  cp -f "$UPDATER_SRC" "$DEST_UPDATER"
fi

echo "Building universal launch.app (unsigned)..."
rm -rf "$DERIVED_DIR"
xcodebuild \
  -project launch.xcodeproj \
  -scheme launch \
  -configuration Release \
  -derivedDataPath "$DERIVED_DIR" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$DERIVED_DIR/Build/Products/Release/launch.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app not found at $APP_PATH" >&2
  exit 1
fi

# Dock 按 .app 文件名显示，重命名为中文后 Dock/Finder 才会显示“启动台”。
APP_PATH="$DERIVED_DIR/Build/Products/Release/启动台.app"
rm -rf "$APP_PATH"
mv "$DERIVED_DIR/Build/Products/Release/launch.app" "$APP_PATH"

echo "Ad-hoc signing..."
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" || true

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
if [[ -z "$VERSION" ]]; then
  echo "error: cannot read version" >&2
  exit 1
fi

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"
ZIP_NAME="launch-${VERSION}.zip"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
DMG_NAME="launch-${VERSION}.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
CHECKSUMS_PATH="$RELEASE_DIR/checksums.txt"

echo "Creating ZIP..."
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "Creating DMG..."
"$ROOT_DIR/scripts/create-dmg.sh" "$APP_PATH" "$DMG_PATH" "$VERSION"

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$ZIP_NAME" "$DMG_NAME" > "$CHECKSUMS_PATH"
)

echo "Unsigned release artifacts:"
echo "  App: $APP_PATH"
echo "  $ZIP_PATH"
echo "  $DMG_PATH"
echo "  $CHECKSUMS_PATH"
echo "Version: $VERSION"
