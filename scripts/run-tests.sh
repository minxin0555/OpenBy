#!/usr/bin/env bash
#
# 无 Xcode 环境下运行 OpenBy 测试与基准。
# 用法:
#   ./scripts/run-tests.sh test       # 跑单元测试（默认）
#   ./scripts/run-tests.sh bench      # 跑路由基准（10k 条规则）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

case "${1:-test}" in
  test)
    # 本环境（仅 Command Line Tools，无 XCTest.framework）用自定义 CLI 测试运行器。
    swift run --package-path "$ROOT" -c release OpenByTestRunner
    ;;
  bench)
    swift run --package-path "$ROOT" -c release OpenByBenchmark --rules 10000
    ;;
  *)
    echo "用法: $0 [test|bench]" >&2
    exit 2
    ;;
esac
