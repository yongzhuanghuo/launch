#!/usr/bin/env bash
# 生成与 Downie6 相同结构的安装 DMG：
#   上方背景标题/图标，左侧安装说明图，右侧 launch.app + Applications 快捷方式。
#
# 用法：scripts/create-dmg.sh <launch.app> <output.dmg> [version]
# 可选素材：
#   scripts/dmg/background.png     DMG 背景（660x420 左右）
#   scripts/dmg/install-guide.png  左侧安装说明图
#   scripts/dmg/.DS_Store          Finder 图标位置（在 macOS 上手工调整一次）
set -euo pipefail

APP_PATH="${1:-}"
OUTPUT="${2:-}"
VERSION="${3:-}"

if [[ -z "$APP_PATH" || ! -d "$APP_PATH" || -z "$OUTPUT" ]]; then
  echo "usage: $0 <path-to-launch.app> <output.dmg> [version]" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VOLUME_NAME="${DMG_VOLUME_NAME:-launch}"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/launch-dmg.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/.background"

# ditto 保留 .app 内的符号链接和签名信息
ditto "$APP_PATH" "$STAGE/launch.app"
ln -s /Applications "$STAGE/Applications"

ASSET_DIR="$ROOT_DIR/scripts/dmg"
if [[ -f "$ASSET_DIR/install-guide.png" ]]; then
  cp "$ASSET_DIR/install-guide.png" "$STAGE/安装说明.png"
fi
if [[ -f "$ASSET_DIR/background.png" ]]; then
  cp "$ASSET_DIR/background.png" "$STAGE/.background/background.png"
fi
if [[ -f "$ASSET_DIR/.DS_Store" ]]; then
  cp "$ASSET_DIR/.DS_Store" "$STAGE/.DS_Store"
fi

rm -f "$OUTPUT"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$OUTPUT"
hdiutil verify "$OUTPUT"

# DMG 签名可选；app 本身已在 release-notarized.sh 里签名/公证/stapled。
if [[ -n "${DMG_SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$DMG_SIGN_IDENTITY" "$OUTPUT"
fi

echo "DMG: $OUTPUT"
if [[ -n "$VERSION" ]]; then
  echo "Version: $VERSION"
fi
