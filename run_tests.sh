#!/bin/bash
# Swift Package のテストを実行し、最後にサマリーと失敗一覧を必ず表示する。
set -o pipefail

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
echo "Using Developer Dir: $DEVELOPER_DIR"

ROOT="$(cd "$(dirname "$0")" && pwd)"
LOG="${ROOT}/.build/last-test-run.log"
mkdir -p "$(dirname "$LOG")"

# 詳細ログが必要なとき: VERBOSE=1 ./run_tests.sh
if [[ "${VERBOSE:-0}" == "1" ]]; then
  SWIFT_TEST_ARGS=(-v)
else
  SWIFT_TEST_ARGS=()
fi

echo ""
echo "========== Swift test (logging to ${LOG}) =========="
echo ""

set +e
xcrun swift test "${SWIFT_TEST_ARGS[@]}" 2>&1 | tee "$LOG"
CODE=$?
set -e

echo ""
echo "========== TEST SUMMARY =========="
# XCTest の総括行（複数スイート後の最終行を優先）
grep "Executed .* tests" "$LOG" | tail -5 || true
grep -E "Test Suite 'All tests'" "$LOG" | tail -3 || true

FAIL_LINES=$(grep -c ": error:" "$LOG" 2>/dev/null || echo 0)
echo "Assertion / compiler error lines: ${FAIL_LINES}"
echo ""

echo "---------- Failed test cases ----------"
grep "Test Case '" "$LOG" | grep " failed (" | sed 's/^/  /' || echo "  (none matched — see ${LOG})"
echo "---------------------------------------"

if [[ "$CODE" -ne 0 ]]; then
  echo ""
  echo "---------- Last :error: lines (up to 25) ----------"
  grep ": error:" "$LOG" | tail -25 | sed 's/^/  /'
  echo "----------------------------------------------------"
  echo ""
  echo "Full log: $LOG"
  echo "FAILED (exit $CODE)"
  exit "$CODE"
fi

echo ""
echo "PASSED"
exit 0
