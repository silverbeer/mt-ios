#!/usr/bin/env bash
# Generate the Xcode project and run all tests (MTKit + app) on a simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild test \
  -project MissingTable.xcodeproj \
  -scheme MissingTable \
  -destination "$(scripts/sim-destination.sh)" \
  CODE_SIGNING_ALLOWED=NO \
  -quiet
