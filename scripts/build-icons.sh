#!/usr/bin/env bash
# 从已选定的 B 方案导出 macOS 资源。仅重新绘制 SVG 后需先运行 build_icons.py。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/OpenBy-icons.XXXXXX")"
trap 'rm -rf "$ICON_ROOT"' EXIT
mkdir -p "$ICON_ROOT/OpenBy.iconset"
for size in 16 32 128 256 512; do
  cp "$ROOT/design/icons/OpenBy-B-$size.png" "$ICON_ROOT/OpenBy.iconset/icon_${size}x${size}.png"
  double=$((size * 2))
  cp "$ROOT/design/icons/OpenBy-B-$double.png" "$ICON_ROOT/OpenBy.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$ICON_ROOT/OpenBy.iconset" -o "$ROOT/Resources/OpenBy.icns"
rsvg-convert -f pdf -w 18 -h 18 "$ROOT/design/icons/OpenBy-B-menu.svg" -o "$ROOT/Resources/MenuBarIcon.pdf"
