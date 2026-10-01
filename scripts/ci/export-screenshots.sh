#!/usr/bin/env bash
# Exports the screenshots attached to tests in an .xcresult bundle, named after their
# attachment names rather than UUIDs. Usage: export-screenshots.sh Tests.xcresult out/
set -euo pipefail

result="$1"
out="$2"
[ -d "$result" ] || { echo "No result bundle at $result (did the build fail?)"; exit 0; }
mkdir -p "$out"
xcrun xcresulttool export attachments --path "$result" --output-path "$out"

# The manifest maps exported UUID file names to readable names like "01-launch_0_<UUID>.png".
manifest="$out/manifest.json"
[ -f "$manifest" ] || exit 0
jq -r '.[].attachments[] | [.exportedFileName, .suggestedHumanReadableName] | @tsv' "$manifest" |
    while IFS=$'\t' read -r file name; do
        clean="$(echo "$name" | sed -E 's/_[0-9]+_[0-9A-Fa-f-]{36}(\.[A-Za-z0-9]+)$/\1/')"
        [ "$file" != "$clean" ] && mv "$out/$file" "$out/$clean"
    done
ls -la "$out"
