#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
. tools/localenv.sh; tolkara_load_env
SIM_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; ds=[d for a in json.load(sys.stdin)["devices"].values() for d in a]; print(next(d["udid"] for d in ds if d["state"]=="Booted"))')
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
mkdir -p build/emulation
CC=(xcrun --sdk iphonesimulator clang -target "$(uname -m)-apple-ios17.0-simulator" -isysroot "$SDK" -O1 -g -Wall -Wextra -Werror -Wno-unused-parameter -Wno-deprecated-declarations -Itranslation/AKSupport)
"${CC[@]}" -fno-objc-arc -c tests/autorelease_probe.m -o build/emulation/autorelease_probe.o
"${CC[@]}" -fobjc-arc translation/AKSupport/AKSupport.m translation/Metal/LibraryContainer.m tests/test_metal_library_lifetime.m build/emulation/autorelease_probe.o -framework Foundation -framework UIKit -framework Metal -framework QuartzCore -o build/emulation/test_metal_library_lifetime
xcrun simctl spawn "$SIM_ID" "$PWD/build/emulation/test_metal_library_lifetime"
"${CC[@]}" -fobjc-arc translation/AKSupport/AKSupport.m tests/test_memory_journal.m -framework Foundation -framework UIKit -framework CoreGraphics -o build/emulation/test_memory_journal
xcrun simctl spawn "$SIM_ID" "$PWD/build/emulation/test_memory_journal"
