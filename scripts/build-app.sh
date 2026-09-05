#!/usr/bin/env bash
#
# 构建 OpenBy.app：swift build -c release + 手工组装 .app 包 + ad-hoc 签名 + LaunchServices 注册。
# 用法: ./scripts/build-app.sh [--universal]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/OpenBy.app"
BUILD_ARCH=()

if [[ "${1:-}" == "--universal" ]]; then
  BUILD_ARCH=(--arch arm64 --arch x86_64)
fi

echo "==> 1/6 swift build -c release"
swift build --package-path "$ROOT" -c release "${BUILD_ARCH[@]}"

echo "==> 2/6 重建 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 3/6 拷贝 Info.plist"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> 4/6 拷贝二进制"
# 应用可执行文件是 OpenByApp（库 OpenBy + 薄入口）；包内文件名保持 OpenBy。
cp "$ROOT/.build/release/OpenByApp" "$APP/Contents/MacOS/OpenBy"
chmod +x "$APP/Contents/MacOS/OpenBy"

echo "==> 5/6 校验 plist 与可执行文件"
plutil -lint "$APP/Contents/Info.plist" >/dev/null
test -x "$APP/Contents/MacOS/OpenBy"

echo "==> 6/6 签名 + 注册 LaunchServices"
# arm64 上未签名的二进制无法运行；本应用无内嵌框架，直接整体签名即可。
codesign --force -s - "$APP"
codesign --verify --strict --verbose=2 "$APP"

# -f 强制刷新注册：Finder/Launch Services 依赖此步把文件路由给 OpenBy。
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$APP"

echo "==> 完成: $APP"
echo "手动测试: open \"$APP\" <某个文件>"
