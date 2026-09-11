#!/bin/bash
#
# 把整套服务塞进 .app —— Node 运行时、服务代码、生产依赖、提示词。
#
# 目标是一步部署：拖进「应用程序」，双击，完事。没有 clone、没有 npm install、
# 没有 npm run service:install。
#
# 三件必须搞对的事，每一件错了都只在别人的机器上才暴露：
#
#   1. **Node 必须是官方发行版，不能是 Homebrew 的那个。** Homebrew 的 `node`
#      是个 68K 的壳，动态链接 /opt/homebrew/opt/... 下的一堆 dylib。把它拷进
#      bundle，做出来的东西只能在「已经装了 Homebrew Node」的机器上跑 ——
#      正好是这次要消灭的那个前置条件。官方二进制 104M，只链系统框架。
#   2. **代码和数据必须分开。** bundle 在升级时整个被替换，写进去的任何东西都会
#      在第一次更新时消失。代码在 Resources/service，数据在
#      ~/Library/Application Support/DailyOS。
#   3. **通用二进制要对齐。** Swift 那边已经是 arm64 + x86_64；Node 也得是，
#      否则 Intel Mac 上 App 能开、服务起不来——比直接打不开更难查。
#
# 用法：scripts/bundle-service.sh <app-path> [service-repo]

set -euo pipefail

APP="${1:?用法: bundle-service.sh <Daily OS.app 路径> [服务仓库路径]}"
SERVICE_REPO="${2:-$(cd "$(dirname "$0")/../.." && pwd)/daily-os-feishu}"
NODE_VERSION="${DAILY_OS_NODE_VERSION:-v22.14.0}"
CACHE="$(cd "$(dirname "$0")/.." && pwd)/.build/node-cache"

[ -d "$SERVICE_REPO" ] || { echo "找不到服务仓库：$SERVICE_REPO"; exit 1; }

RES="$APP/Contents/Resources"
PAYLOAD="$RES/service"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD" "$CACHE"

# --- Node ------------------------------------------------------------------
# Cached because it is 100M+ per architecture and it never changes for a given
# version — re-downloading it on every package run would make the whole script
# something people avoid running.
fetch_node() {
  local arch
  local dir
  arch="$1"
  dir="$CACHE/node-$NODE_VERSION-darwin-$arch"
  if [ ! -x "$dir/bin/node" ]; then
    # stderr, not stdout: this function's stdout *is* the path the caller
    # captures, and a progress line on it becomes part of that path.
    echo "  下载 node $NODE_VERSION ($arch)…" >&2
    curl -fsSL "https://nodejs.org/dist/$NODE_VERSION/node-$NODE_VERSION-darwin-$arch.tar.xz" \
      | tar xJ -C "$CACHE"
  fi
  echo "$dir/bin/node"
}

echo "==> Node 运行时"
ARM=$(fetch_node arm64)
X64=$(fetch_node x64)
lipo -create "$ARM" "$X64" -output "$RES/node"
chmod +x "$RES/node"
echo "  架构：$(lipo -archs "$RES/node")"

# Anything outside /usr/lib and /System means the binary expects libraries that
# are not on a stock Mac, which is the Homebrew trap this check exists to catch.
# Only tab-indented lines are dependencies. A universal binary makes `otool`
# print an "(architecture arm64):" header per slice, and matching those as if
# they were libraries failed the check on a binary that was perfectly fine.
BAD=$(otool -L "$RES/node" | grep $'^\t' | grep -v -e '/usr/lib/' -e '/System/' || true)
if [ -n "$BAD" ]; then
  echo "  ✗ node 依赖了非系统库，装到别人机器上会起不来："
  echo "$BAD"
  exit 1
fi
echo "  ✓ 只依赖系统库"

# --- 服务代码 ---------------------------------------------------------------
echo "==> 服务代码"
( cd "$SERVICE_REPO" && npm run build >/dev/null 2>&1 ) || { echo "  服务构建失败"; exit 1; }
cp -R "$SERVICE_REPO/dist" "$PAYLOAD/dist"
cp -R "$SERVICE_REPO/prompts" "$PAYLOAD/prompts"
cp "$SERVICE_REPO/package.json" "$PAYLOAD/package.json"
cp "$SERVICE_REPO/.env.example" "$PAYLOAD/.env.example"
mkdir -p "$PAYLOAD/config"
cp "$SERVICE_REPO/config/config.example.yaml" "$PAYLOAD/config/config.example.yaml"

# --- 生产依赖 ---------------------------------------------------------------
# `--omit=dev` because the test and build toolchain is most of the weight and
# none of it runs here. Scripts are *not* skipped: better-sqlite3 resolves its
# prebuilt binary during install, and both darwin arches ship in the package, so
# the universal app finds the right one at runtime.
echo "==> 生产依赖"
STAGE="$(mktemp -d)"
cp "$SERVICE_REPO/package.json" "$SERVICE_REPO/package-lock.json" "$STAGE/"
( cd "$STAGE" && npm ci --omit=dev >/dev/null 2>&1 ) || { echo "  npm ci 失败"; rm -rf "$STAGE"; exit 1; }
cp -R "$STAGE/node_modules" "$PAYLOAD/node_modules"
rm -rf "$STAGE"
echo "  $(du -sh "$PAYLOAD/node_modules" | cut -f1)"

echo "==> 服务负载 $(du -sh "$PAYLOAD" | cut -f1)，加上 node 共 $(du -sh "$RES" | cut -f1)"
