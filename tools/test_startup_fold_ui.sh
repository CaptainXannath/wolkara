#!/bin/bash
# Synthetic UIKit startup/geometry fixture only; never loads a game.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM=${SIMULATOR:-iPhone 17 Pro Max}
SIM_ID=$(xcrun simctl list devices available -j | python3 -c 'import json,sys; ds=[d for group in json.load(sys.stdin)["devices"].values() for d in group if sys.argv[1] in (d["name"],d["udid"])]; ds.sort(key=lambda d:d["state"]!="Booted"); print(ds[0]["udid"] if ds else "")' "$SIM")
[ -n "$SIM_ID" ] || { echo "No matching simulator; set SIMULATOR."; exit 2; }
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
APP=build/startup-fold-fixture/StartupFold.app
mkdir -p "$APP"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g \
    -Wall -Wextra -Werror -Wno-deprecated-declarations -Iruntime -Ilauncher/App \
    runtime/GuestWait.c launcher/App/StartupActivity.m launcher/App/StartupActivityText.m tests/test_startup_fold_app.m \
    -framework Foundation -framework UIKit -framework QuartzCore -o "$APP/StartupFold"
python3 - <<'PY'
import plistlib
from pathlib import Path
info={'CFBundleIdentifier':'org.tolkara.tests.startup-fold','CFBundleExecutable':'StartupFold','CFBundleName':'Startup fold fixture',
'CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','MinimumOSVersion':'17.0',
'UIDeviceFamily':[1,2],'UILaunchScreen':{},'UISupportedInterfaceOrientations':['UIInterfaceOrientationLandscapeRight','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationPortrait','UIInterfaceOrientationPortraitUpsideDown'],
'UIApplicationSceneManifest':{'UIApplicationSupportsMultipleScenes':False,'UISceneConfigurations':{}}}
Path('build/startup-fold-fixture/StartupFold.app/Info.plist').write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$APP" > /dev/null
xcrun simctl install "$SIM_ID" "$APP"
LOG=build/startup-fold-fixture/self-test.log
xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.startup-fold "$@" 2>&1 | tee "$LOG"
grep -q 'STARTUP_FOLD_UI_PASS:' "$LOG"
