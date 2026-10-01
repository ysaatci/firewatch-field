#!/usr/bin/env bash
# Developer tasks, run inside the Linux Swift container.
# Native Swift on Windows is avoided: Smart App Control blocks unsigned test binaries.
#
# Usage: scripts/dev.sh <command>
#   check    Everything CI runs: lint, strict build, tests (core and server)
#   test     Build (warnings are errors) and run the core package's tests
#   format   Rewrite sources with swift-format
#   lint     Fail if any source is not formatted
#   shell    Open a shell in the dev container
#   coverage Fail if FireWatchCore line coverage is below 80 %
#   server   Run the simulator server on http://localhost:8080 (docker compose)
set -euo pipefail

IMAGE="firewatch-field-dev:latest"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Docker on Windows needs a Windows-style path; Git Bash provides it via `pwd -W`.
if host_root="$(cd "$ROOT" && pwd -W 2>/dev/null)"; then :; else host_root="$ROOT"; fi
export MSYS_NO_PATHCONV=1

ensure_image() {
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        docker build -t "$IMAGE" -f "$host_root/docker/Dockerfile.dev" "$host_root/docker"
    fi
}

run() {
    ensure_image
    local tty=()
    [ -t 0 ] && [ -t 1 ] && tty=(-it)
    # Mounted under the repository's own name: SwiftPM names the Server package's path
    # dependency after this directory. Build products live in named volumes, which are
    # faster than bind mounts and keep Linux artefacts out of the Windows working tree.
    docker run --rm "${tty[@]}" \
        -v "$host_root:/firewatch-field" \
        -v firewatch-field-build:/firewatch-field/.build \
        -v firewatch-field-server-build:/firewatch-field/Server/.build \
        -w /firewatch-field "$IMAGE" "$@"
}

SOURCES="Package.swift Sources Tests Server/Package.swift Server/Sources Server/Tests App"
LINT="swift format lint --strict --recursive --parallel $SOURCES"
STRICT="-Xswiftc -warnings-as-errors"
TEST="swift build --build-tests $STRICT && swift test --skip-build"
SERVER_TEST="swift build --package-path Server --build-tests $STRICT && swift test --package-path Server --skip-build"

case "${1:-help}" in
    check)  run bash -c "$LINT && $TEST && $SERVER_TEST" ;;
    test)   run bash -c "$TEST" ;;
    shell)  run bash ;;
    format) run swift format format --in-place --recursive --parallel $SOURCES ;;
    lint)   run bash -c "$LINT" ;;
    coverage) run scripts/coverage.sh ;;
    server) cd "$ROOT" && docker compose up --build ;;
    *)      sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
