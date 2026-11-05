#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
mkdir -p build/curseforge
xcrun clang -fobjc-arc -Wall -Wextra -Werror -Ilauncher/WoW \
    launcher/WoW/CurseForgeClient.m launcher/App/WolkaraForeverLog.m tests/test_curseforge.m \
    -framework Foundation -o build/curseforge/test_curseforge
build/curseforge/test_curseforge
