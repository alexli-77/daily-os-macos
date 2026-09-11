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

# --- 把服务塞进去 ---------------------------------------------------------
#
# 这一步之后，这个 .app 就是完整产品：Node 运行时、服务代码、依赖、提示词全在里面。
# 对方不需要 clone 仓库，不需要 npm，不需要跑任何安装脚本。
"$(dirname "$0")/bundle-service.sh" "$OUT/$APP_NAME" "${DAILY_OS_SERVICE_REPO:-}"

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
# Stamp the build, so the app can answer "am I running the latest?" itself.
#
# Every build from this repo carries the same CFBundleShortVersionString, so
# without this two apps a week apart are indistinguishable from inside. The
# alternative was reading a binary's mtime in a terminal, which is not something
# to ask of someone who just wants to know whether their fix landed.
#
# `dirty` is stamped too: a commit hash that does not describe the code actually
# in the bundle is more misleading than no hash at all.
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "")
DIRTY=$([ -n "$(git status --porcelain 2>/dev/null | grep -v '^??')" ] && echo YES || echo NO)
PLIST="$OUT/$APP_NAME/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :DailyOSBuildCommit string $COMMIT" "$PLIST" >/dev/null 2>&1 \
  || /usr/libexec/PlistBuddy -c "Set :DailyOSBuildCommit $COMMIT" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :DailyOSBuildDirty string $DIRTY" "$PLIST" >/dev/null 2>&1 \
  || /usr/libexec/PlistBuddy -c "Set :DailyOSBuildDirty $DIRTY" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :DailyOSBuildDate string $(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PLIST" >/dev/null 2>&1 \
  || /usr/libexec/PlistBuddy -c "Set :DailyOSBuildDate $(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PLIST"

# After the plist edits, never before: changing a file inside the bundle
# invalidates a signature that was already applied.
# Inside out, and every nested executable individually.
#
# `lipo -create` on the two official node binaries **invalidates the signature
# Node ships with**, and an arm64 binary with a broken signature does not run —
# it is killed on exec. The native `.node` modules are in the same position.
# Signing only the outer bundle produces something that verifies, launches, and
# then cannot start its own service.
echo "==> Ad-hoc 签名（由内向外）"
NESTED=0
while IFS= read -r -d '' f; do
  codesign --force --sign - --timestamp=none "$f" 2>/dev/null && NESTED=$((NESTED + 1))
done < <(find "$OUT/$APP_NAME/Contents/Resources" \( -name '*.node' -o -name '*.dylib' \) -print0 2>/dev/null)
codesign --force --sign - --timestamp=none "$OUT/$APP_NAME/Contents/Resources/node"
NESTED=$((NESTED + 1))
echo "  嵌套可执行文件 $NESTED 个"

codesign --force --sign - --timestamp=none "$OUT/$APP_NAME"
codesign --verify --strict "$OUT/$APP_NAME"
# The outer verify does not walk into Resources, so the one failure this whole
# block exists to prevent would pass it. Check the payload itself.
codesign --verify "$OUT/$APP_NAME/Contents/Resources/node" \
  || { echo "  ✗ 打包进去的 node 签名无效，装到别的机器上会被系统直接杀掉"; exit 1; }
echo "  ✓ node 签名有效"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
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
echo "服务已经打包在里面了。对方只要把 .app 拖进「应用程序」并打开——"
echo "第一次启动会自己建 ~/Library/Application Support/DailyOS、登记后台任务、拉起服务。"
echo "不需要 clone 仓库，不需要 npm，不需要跑任何安装脚本。"
echo
echo "还需要对方自己填的：模型密钥、飞书凭据这些，在 App 的设置里填。"
