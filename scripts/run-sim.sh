#!/usr/bin/env bash
# Build the app, boot the newest iPhone simulator, install and launch.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
dest="$(scripts/sim-destination.sh)"
udid="${dest#id=}"
xcodebuild build -project MissingTable.xcodeproj -scheme MissingTable \
  -destination "$dest" -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet
xcrun simctl boot "$udid" 2>/dev/null || true
# Show the simulator window if this Xcode ships a Simulator app; the device runs either way.
open -a Simulator 2>/dev/null || echo "note: Simulator app not found; device is booted headless (udid $udid)"
xcrun simctl install "$udid" build/Build/Products/Debug-iphonesimulator/MissingTable.app
xcrun simctl launch "$udid" io.silverbeer.mt
