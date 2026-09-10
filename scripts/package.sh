#!/bin/bash
#
# Build a Daily OS.app you can hand to another Mac.
#
# There is no installer and no .pkg. macOS apps are directories: the whole
# product is `Daily OS.app`, and "installing" it means dragging it to
# /Applications. What this script produces is that bundle plus a zip of it,
# because a bundle sent as a loose folder arrives as a folder.
#
# Not signed with a Developer ID and not notarised — see README §"装到另一台 Mac
# 上". The zip is deliberately *not* the recommended transfer: a zip opened from
# AirDrop, a browser or Messages carries `com.apple.quarantine` and gets stopped
# by Gatekeeper. `scp`/`rsync`/USB do not. The zip exists for the cases where
# that is the only channel available, and the recipient then has to go through
# 系统设置 → 隐私与安全性 → 仍要打开.
#
# Usage: scripts/package.sh

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="dist"
APP_NAME="Daily OS.app"
DERIVED=".build/package"

command -v xcodegen >/dev/null || { echo "需要 xcodegen：brew install xcodegen"; exit 1; }

echo "==> 生成工程"
xcodegen generate >/dev/null

# Release, not Debug: this is the copy someone else runs every day, and it
# should not carry the debug build's overhead. Building Release also catches the
# `#Preview`-in-Release breakage class that a Debug build never sees.
echo "==> 构建 Release（通用二进制，arm64 + x86_64）"
xcodebuild build \
  -project DailyOS.xcodeproj \
  -scheme DailyOS \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO \
  >/dev/null

BUILT="$DERIVED/Build/Products/Release/DailyOS.app"
[ -d "$BUILT" ] || { echo "构建产物不在预期位置：$BUILT"; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R "$BUILT" "$OUT/$APP_NAME"

# Ad-hoc sign, explicitly.
#
# Not optional and not cosmetic: **arm64 executables must carry a signature to
# run at all.** A single-arch build gets one for free — the linker ad-hoc signs
# it — but a universal build comes out of `CODE_SIGNING_ALLOWED=NO` unsigned,
# and the result launches on Intel and dies on Apple Silicon with a message that
# blames the app rather than its signature. Going universal without this line
# breaks the exact machines it was meant to serve.
#
# `-` is ad-hoc: enough to run locally, not a Developer ID, still not notarised.
echo "==> Ad-hoc 签名"
codesign --force --sign - --timestamp=none "$OUT/$APP_NAME"
codesign --verify --strict "$OUT/$APP_NAME"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$OUT/$APP_NAME/Contents/Info.plist")
ZIP="$OUT/DailyOS-$VERSION.zip"

# ditto, not `zip`: a .app is a bundle with symlinks and an executable bit, and
# plain zip loses both — the copy that comes out the other end will not launch.
echo "==> 打包"
ditto -c -k --sequesterRsrc --keepParent "$OUT/$APP_NAME" "$ZIP"

echo
echo "架构：$(lipo -archs "$OUT/$APP_NAME/Contents/MacOS/DailyOS")"
echo "版本：$VERSION"
echo "App： $(pwd)/$OUT/$APP_NAME"
echo "Zip： $(pwd)/$ZIP"
echo
echo "对方还需要 daily-os 服务在他自己那台机器上跑起来——这个 App 只是它的客户端，"
echo "首次启动会让他选服务仓库目录。"
