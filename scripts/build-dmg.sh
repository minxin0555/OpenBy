#!/usr/bin/env bash
# Build a drag-to-install DMG. Usage: ./scripts/build-dmg.sh [--universal]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_OPTIONS=(--no-register)
for option in "$@"; do
  case "$option" in
    --universal) BUILD_OPTIONS+=(--universal) ;;
    *) echo "用法: $0 [--universal]" >&2; exit 2 ;;
  esac
done

"$ROOT/scripts/build-app.sh" "${BUILD_OPTIONS[@]}"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/OpenBy-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_ROOT"' EXIT
PAYLOAD="$STAGING_ROOT/payload"
mkdir -p "$PAYLOAD"
# Extract the clean archive to avoid Finder metadata attached to the loose app.
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ditto -x -k "$ROOT/dist/OpenBy-$VERSION.zip" "$PAYLOAD"
codesign --verify --strict --verbose=2 "$PAYLOAD/OpenBy.app"
ARCHS="$(lipo -archs "$PAYLOAD/OpenBy.app/Contents/MacOS/OpenBy")"
case "$ARCHS" in
  arm64) ARCH_LABEL=arm64 ;;
  x86_64) ARCH_LABEL=x86_64 ;;
  "x86_64 arm64"|"arm64 x86_64") ARCH_LABEL=universal ;;
  *) echo "不支持的架构组合: $ARCHS" >&2; exit 1 ;;
esac
ln -s /Applications "$PAYLOAD/Applications"
cat > "$PAYLOAD/安装说明.txt" <<'EOF'
OpenBy 安装说明

系统要求：macOS 14 或更新版本。

1. 如已运行旧版 OpenBy，请先从菜单栏退出。
2. 将 OpenBy.app 拖入 Applications（应用程序）文件夹。
3. 推出此磁盘镜像，从“应用程序”启动 OpenBy。
4. 添加文件类型和位置规则，然后启用自动打开。

本版本使用 ad-hoc 签名，尚未通过 Apple 公证。
若 macOS 拦截首次运行，请确认下载来源可信后，在“系统设置 →
隐私与安全性”中查看系统提供的打开选项。

卸载前请在 OpenBy 中停用自动打开并恢复原应用，再退出并移除应用。
EOF
NAME="OpenBy-$VERSION-$ARCH_LABEL.dmg"
hdiutil create -volname "OpenBy $VERSION" -srcfolder "$PAYLOAD" \
  -format UDZO -fs HFS+ "$STAGING_ROOT/$NAME"
hdiutil verify "$STAGING_ROOT/$NAME"
cp "$STAGING_ROOT/$NAME" "$ROOT/dist/$NAME"
(cd "$ROOT/dist" && shasum -a 256 "$NAME" > "$NAME.sha256")
echo "==> DMG: $ROOT/dist/$NAME"
echo "==> SHA-256: $ROOT/dist/$NAME.sha256"
