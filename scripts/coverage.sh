#!/usr/bin/env bash
# Runs the tests with coverage and fails if FireWatchCore's line coverage is below the
# threshold (NFR-9). Run inside the Linux Swift container: scripts/dev.sh coverage
set -euo pipefail

THRESHOLD="${1:-80}"
MODULE_DIR="Sources/FireWatchCore"

# Line-buffered through a pty, and backtraces on SIGQUIT, so a hanging test can be found.
LOG="$(mktemp)"
if ! SWIFT_BACKTRACE=enable=yes,threads=all,interactive=no timeout -s QUIT 300 script -qec "swift test --enable-code-coverage" /dev/null >"$LOG" 2>&1; then
    tail -n 400 "$LOG"
    exit 1
fi
BIN_DIR="$(swift build --show-bin-path)"
REPORT="$(llvm-cov report "$BIN_DIR/FireWatchFieldPackageTests.xctest" \
    -instr-profile="$BIN_DIR/codecov/default.profdata" "$MODULE_DIR")"

# Columns: name, regions (3), functions (3), lines (count, missed, cover), branches (3).
echo "$REPORT" | awk '/%/ && !/^Filename/ { printf "%-36s %8s\n", $1, $10 }'
COVERAGE="$(echo "$REPORT" | awk '/^TOTAL/ { gsub("%", "", $10); print $10 }')"
echo "FireWatchCore line coverage: ${COVERAGE}% (minimum ${THRESHOLD}%)"
awk -v coverage="$COVERAGE" -v threshold="$THRESHOLD" 'BEGIN { exit !(coverage >= threshold) }'
