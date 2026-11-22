#!/bin/sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${TMPDIR:-/tmp}/knee_math_test"
swiftc -parse-as-library -o "$BIN" \
  "$ROOT/ios/ACLRehabTracker/Core/KneeAngleMath.swift" \
  "$ROOT/ios/ACLRehabTracker/Services/KneePoseEstimator.swift" \
  "$ROOT/accuracy/knee_math_test.swift"
"$BIN"
