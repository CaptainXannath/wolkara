#!/bin/bash
# Our UIKit event stream -> actual Lua bindings/snippets, without running a game.
set -euo pipefail
cd "$(dirname "$0")/.."
bash tools/test_direct_touch_camera.sh
WOLKARA_MOBILE_EVENT_TRACE="$PWD/build/direct-touch-camera/mobile-events.tsv" bash tools/test_mobile_interface.sh
