#!/bin/bash
#
# Cut a release: build the app, then publish the manifest the app checks.
#
# The app has no Apple Developer account (LEO-296), so there is no signing,
# no notarisation, and no auto-update. The whole "更新" story is this: the app
# fetches `release/latest.json` from raw main, compares it to its own build
# stamp, and shows a "有新版本，下载" line in 设置 → 服务. This script is what
# keeps that manifest honest.
#
# It does NOT push or create the GitHub release for you — publishing is a
# deliberate, outward step. It writes the manifest and the zip, then prints the
# exact two commands to run.
#
# Usage: scripts/release.sh

set -euo pipefail
cd "$(dirname "$0")/.."

REPO_SLUG="${DAILY_OS_RELEASE_REPO:-alexli-77/daily-os-macos}"

echo "==> 构建并打包（scripts/package.sh）"
scripts/package.sh

APP="dist/Daily OS.app"
PLIST="$APP/Contents/Info.plist"
plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || echo ""; }

VERSION=$(plist CFBundleShortVersionString)
COMMIT=$(plist DailyOSBuildCommit)
DIRTY=$(plist DailyOSBuildDirty)
DATE=$(plist DailyOSBuildDate)
ZIP="dist/DailyOS-$VERSION.zip"

if [ "$DIRTY" = "YES" ]; then
  echo "✗ 工作区有未提交改动（构建戳 dirty）。发布的包必须对应一个干净 commit。先提交再发。" >&2
  exit 1
fi

# The download target is the releases page, not a direct asset: a human opens it,
# reads the install note, and downloads the zip. Direct-pulling an unsigned,
# unnotarised binary through a browser is the worst Gatekeeper path.
URL="https://github.com/$REPO_SLUG/releases/latest"

mkdir -p release
cat > release/latest.json <<JSON
{
  "version": "$VERSION",
  "commit": "$COMMIT",
  "date": "$DATE",
  "url": "$URL"
}
JSON

echo
echo "已写 release/latest.json："
cat release/latest.json
echo
echo "包：$(pwd)/$ZIP"
echo
echo "接下来（都要你手动跑，这两步才是真正的发布）："
echo "  1. 挂上这个版本的 zip 做 GitHub Release："
echo "       gh release create v$VERSION-$COMMIT \"$ZIP\" --repo $REPO_SLUG --title \"v$VERSION ($COMMIT)\" --notes \"...\""
echo "  2. 提交并推送 manifest（App 是从 raw main 读它的，不推等于没发）："
echo "       git add release/latest.json && git commit -m \"release: v$VERSION ($COMMIT)\" && git push"
echo
echo "装到别的 Mac 的注意事项见 README §「装到另一台 Mac 上」——没公证，要走系统设置「仍要打开」。"
