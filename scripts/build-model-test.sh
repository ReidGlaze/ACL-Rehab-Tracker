#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ ! -f "$TASK_ROOT/ios/ACLRehabTracker/GoogleService-Test.plist" ]]; then
  echo 'Missing test Firebase configuration. See docs/model-testing.md.' >&2
  exit 1
fi
xcodebuild -workspace "$TASK_ROOT/ios/ACLRehabTracker.xcworkspace" \
  -scheme ACLRehabTracker -configuration Debug \
  -destination "${1:-generic/platform=iOS}" \
  -derivedDataPath "${TMPDIR:-/tmp}/acl-model-test-build" \
  -allowProvisioningUpdates build
