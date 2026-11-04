#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/emulation
xcrun clang -fobjc-arc -Wall -Wextra -Werror -O1 -g \
    -fsanitize=address,undefined -fno-omit-frame-pointer -framework Foundation -lz -Iruntime \
    launcher/WoW/Manifest.m launcher/WoW/CASC.m runtime/GuestTactObject.m \
    runtime/GuestTactCache.m tests/test_tact_cache.m \
    -o build/emulation/test_tact_cache
build/emulation/test_tact_cache
