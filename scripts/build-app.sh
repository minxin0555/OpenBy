#!/usr/bin/env bash
# Release 构建；在本地临时目录签名，避免同步目录并发附加 FinderInfo。
# 用法: ./scripts/build-app.sh [--universal] [--no-register]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_APP="$ROOT/dist/OpenBy.app"
BUILD_ARCH=()
REGISTER=true
for option in "$@"; do
  case "$option" in
    --universal) BUILD_ARCH=(--arch arm64 --arch x86_64) ;;
    --no-register) REGISTER=false ;;
    *) echo "未知选项: $option" >&2; exit 2 ;;
  esac
done

echo "==> 1/5 swift build -c release"
swift build --package-path "$ROOT" -c release "${BUILD_ARCH[@]}"
BIN_PATH="$(swift build --package-path "$ROOT" -c release "${BUILD_ARCH[@]}" --show-bin-path)"

STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/OpenBy-build.XXXXXX")"
trap 'rm -rf "$STAGING_ROOT"' EXIT
APP="$STAGING_ROOT/OpenBy.app"

echo "==> 2/5 在本地临时目录组装应用"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT/dist"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :OpenByBuildDate string $(date -u +%Y-%m-%dT%H:%M:%SZ)" "$APP/Contents/Info.plist"
cp "$BIN_PATH/OpenByApp" "$APP/Contents/MacOS/OpenBy"
chmod +x "$APP/Contents/MacOS/OpenBy"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "==> 3/5 签名与严格校验"
xattr -cr "$APP"
codesign --force -s - "$APP"
codesign --verify --strict --verbose=2 "$APP"

echo "==> 4/5 生成不含 Finder 扩展属性的发布包"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ARCHIVE="$ROOT/dist/OpenBy-$VERSION.zip"
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$ARCHIVE"

# 桌面/iCloud 可能再次给裸 .app 附加 FinderInfo；发布 zip 的字节不受影响。
echo "==> 5/5 输出应用与可选的 Launch Services 注册"
rm -rf "$OUTPUT_APP"
ditto --norsrc --noextattr "$APP" "$OUTPUT_APP"
if [[ "$REGISTER" == true ]]; then
  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  "$LSREGISTER" -f "$OUTPUT_APP"
fi

echo "==> 应用: $OUTPUT_APP"
echo "==> 发布包: $ARCHIVE"
