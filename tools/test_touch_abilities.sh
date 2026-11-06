#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SIM=${SIMULATOR:-iPhone 17 Pro Max}
SIM_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; ds=[d for group in json.load(sys.stdin)["devices"].values() for d in group if sys.argv[1] in (d["name"],d["udid"])]; ds.sort(key=lambda d:d["state"]!="Booted"); print(ds[0]["udid"] if ds else "")' "$SIM")
[ -n "$SIM_ID" ]
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
mkdir -p build/touch-abilities
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g -Wall -Wextra -Werror \
    -Itranslation/AppKit translation/AppKit/TouchActionInput.m translation/AppKit/TouchActionLayout.m tests/test_touch_abilities.m \
    -framework Foundation -framework UIKit -framework CoreGraphics -o build/touch-abilities/tests
xcrun simctl spawn "$SIM_ID" "$PWD/build/touch-abilities/tests"
