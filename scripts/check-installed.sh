#!/bin/bash
#
# 装在 /Applications 里的那份，是不是这个仓库的最新代码？
#
# 存在的理由：这个问题被问了三次。答案一直是可以查的——设置 → 服务 里有版本戳，
# 终端里有 `git rev-parse` ——但那是两个地方、两步、还要人肉比对一串哈希。
# 一个要分两步做的检查，就是一个不会被做的检查。
#
# 用法：scripts/check-installed.sh

set -uo pipefail
cd "$(dirname "$0")/.."

APP="/Applications/Daily OS.app"
PLIST="$APP/Contents/Info.plist"

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
amber() { printf '\033[33m%s\033[0m\n' "$1"; }

if [ ! -d "$APP" ]; then
  red "✗ /Applications 里没有 Daily OS.app"
  echo "  先跑：./scripts/package.sh 然后把 dist/Daily OS.app 拖进「应用程序」"
  exit 1
fi

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null; }

INSTALLED=$(plist DailyOSBuildCommit)
BUILT_DIRTY=$(plist DailyOSBuildDirty)
BUILT_AT=$(plist DailyOSBuildDate)
HEAD=$(git rev-parse --short HEAD 2>/dev/null || echo "")
TREE_DIRTY=$([ -n "$(git status --porcelain 2>/dev/null | grep -v '^??')" ] && echo YES || echo NO)

echo "已安装 : ${INSTALLED:-（没有版本戳）}${BUILT_AT:+  构建于 $BUILT_AT}"
echo "仓库   : ${HEAD:-（读不到）}  工作区$([ "$TREE_DIRTY" = YES ] && echo "有未提交改动" || echo "干净")"
echo

# No stamp at all: built by Xcode or by hand, so there is nothing to compare and
# saying "up to date" would be a guess dressed as a fact.
if [ -z "$INSTALLED" ]; then
  amber "? 装的这份没有版本戳——不是用 scripts/package.sh 打的，对不出来"
  echo "  重新打一次就能查：./scripts/package.sh"
  exit 2
fi

# A stamped commit that does not describe the bundle's code is worse than no
# stamp, so this outranks the hash comparison even when the hashes match.
if [ "$BUILT_DIRTY" = "YES" ]; then
  amber "⚠ 装的这份是在有未提交改动时打的——commit $INSTALLED 和包里的代码对不上"
  echo "  别拿它当准。提交之后重新打包安装。"
  exit 2
fi

if [ "$INSTALLED" != "$HEAD" ]; then
  red "✗ 不是最新的：装的是 $INSTALLED，仓库是 $HEAD"
  echo "  更新：./scripts/package.sh && rm -rf \"$APP\" && cp -R \"dist/Daily OS.app\" \"$APP\""
  exit 1
fi

if [ "$TREE_DIRTY" = "YES" ]; then
  amber "⚠ 和 HEAD 一致，但工作区有未提交改动——那些改动还没进这个包"
  exit 2
fi

# Being level with the remote is a different question from being level with the
# local repo, and only one of them is what "latest" usually means.
UPSTREAM=$(git rev-parse --short '@{u}' 2>/dev/null || echo "")
if [ -n "$UPSTREAM" ] && [ "$UPSTREAM" != "$HEAD" ]; then
  amber "⚠ 和本地 HEAD 一致，但本地还没和远端同步（远端 $UPSTREAM）"
  exit 2
fi

green "✓ 是最新的（$INSTALLED）"
