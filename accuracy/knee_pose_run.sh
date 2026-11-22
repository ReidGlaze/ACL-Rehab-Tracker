#!/bin/sh
# Usage: accuracy/knee_pose_run.sh <fixturesDir> <out.json>
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${TMPDIR:-/tmp}/knee_pose_run"
swiftc -O -parse-as-library -o "$BIN" \
  "$ROOT/ios/ACLRehabTracker/Core/KneeAngleMath.swift" \
  "$ROOT/ios/ACLRehabTracker/Services/KneePoseEstimator.swift" \
  "$ROOT/accuracy/knee_pose_run.swift"
"$BIN" "$@"
