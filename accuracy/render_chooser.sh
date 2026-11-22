#!/bin/sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${TMPDIR:-/tmp}/render_chooser"
swiftc -parse-as-library -o "$BIN" \
  "$ROOT/ios/ACLRehabTracker/Theme/Theme.swift" \
  "$ROOT/ios/ACLRehabTracker/Models/MeasureMode.swift" \
  "$ROOT/ios/ACLRehabTracker/Views/Measure/MeasureModePicker.swift" \
  "$ROOT/accuracy/render_chooser.swift"
"$BIN" "$@"
