#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/mobile-interface
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations -framework Foundation \
    launcher/WoW/MobileInterface.m tests/test_mobile_interface_install.m -o build/mobile-interface/install-test
build/mobile-interface/install-test
"${LUA:-lua}" tests/test_mobile_interface.lua
