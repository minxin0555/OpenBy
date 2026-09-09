#!/usr/bin/env bash
# Native window geometry regression checks; temporary config, no system association writes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/OpenBy-layout-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
SOURCES=()
while IFS= read -r source; do SOURCES+=("$source"); done < <(find "$ROOT/Sources/OpenBy" -name '*.swift' -type f)
swiftc -swift-version 5 -module-name OpenByWindowLayout "${SOURCES[@]}" "$ROOT/Tests/WindowLayout/main.swift" -o "$STAGING/check-window-layout"
"$STAGING/check-window-layout"
