#!/usr/bin/env bash
# Prints the UDID of an iPhone simulator on the newest installed iOS runtime. Device names
# change with every Xcode release, so CI asks rather than hard-coding one.
set -euo pipefail

xcrun simctl list devices available --json | jq -r '
  [ .devices | to_entries[]
    | select(.key | test("iOS-[0-9]+"))
    | . as $runtime
    | .value[]
    | select(.name | test("^iPhone"))
    | { udid, name, version: ($runtime.key | capture("iOS-(?<major>[0-9]+)-(?<minor>[0-9]+)")
                                         | [(.major | tonumber), (.minor | tonumber)]) } ]
  | sort_by(.version)
  | (map(select(.name | test("^iPhone [0-9]+$"))) | last) // last
  | .udid'
