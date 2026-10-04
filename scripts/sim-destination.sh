#!/usr/bin/env bash
# Print an xcodebuild -destination for the newest available iPhone simulator.
set -euo pipefail
xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devs = json.load(sys.stdin)["devices"]
best = None
for runtime, items in devs.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m:
        continue
    ver = (int(m.group(1)), int(m.group(2)))
    for d in items:
        if d["name"].startswith("iPhone") and (best is None or ver > best[0]):
            best = (ver, d["udid"])
if best is None:
    sys.exit("no iPhone simulator available")
print(f"id={best[1]}")
'
