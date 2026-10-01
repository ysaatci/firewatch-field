#!/usr/bin/env bash
# Developer tasks, run inside the Linux Swift container.
# Native Swift on Windows is avoided: Smart App Control blocks unsigned test binaries.
#
# Usage: scripts/dev.sh <command>
#   test     Build (warnings are errors) and run all tests
#   build    Build all targets
#   format   Rewrite sources with swift-format
#   lint     Fail if any source is not formatted
#   shell    Open a shell in the dev container
#   server   Run the simulator server (added in M4)
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
    # .build lives in a named volume: faster than a bind mount and keeps Linux
    # build products out of the Windows working tree.
    docker run --rm "${tty[@]}" \
        -v "$host_root:/src" -v firewatch-field-build:/src/.build \
        -w /src "$IMAGE" "$@"
}

case "${1:-help}" in
    test)   run bash -c "swift build --build-tests -Xswiftc -warnings-as-errors && swift test --skip-build" ;;
    build)  run swift build --build-tests ;;
    shell)  run bash ;;
    format) run swift format format --in-place --recursive --parallel Package.swift Sources Tests ;;
    lint)   run swift format lint --strict --recursive --parallel Package.swift Sources Tests ;;
    server) echo "The simulator server arrives in milestone M4." >&2; exit 1 ;;
    *)      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
