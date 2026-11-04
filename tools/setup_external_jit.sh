#!/bin/bash
# Generate the isolated prototype, then open Xcode. Does not install or enroll.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null || { echo 'Install XcodeGen first: brew install xcodegen'; exit 1; }
xcodebuild -version >/dev/null
bash tools/generate.sh
cat <<'MESSAGE'
Select the WolkaraExternalJIT scheme and your physical iPhone/iPad (iOS 26+).
In Signing & Capabilities, select your own Personal Team and a unique bundle ID.
Keep Debug executable OFF. The app is named Wolkara JIT and has separate data.
StikDebug + LocalDevVPN must be installed and paired before Play can prepare JIT.
First test: Settings > Diagnostics and logs > Test External JIT setup.
See docs/EXTERNAL_JIT.md. Personal Team game support is not yet validated.
MESSAGE
open Tolkara.xcodeproj
