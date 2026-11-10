#!/bin/bash
# Builds/opens our own input fixture, never an imported application.
# Optional --self-test checks keyboard layout, text delivery and focus.
set -euo pipefail
cd "$(dirname "$0")/.."
SIM=${SIMULATOR:-iPhone 17 Pro}
SIM_ID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = [d for group in json.load(sys.stdin)["devices"].values() for d in group if sys.argv[1] in (d["name"], d["udid"])]
devices.sort(key=lambda d: d["state"] != "Booted")
print(devices[0]["udid"] if devices else "")' "$SIM")
[ -n "$SIM_ID" ] || { echo "No matching simulator; set SIMULATOR."; exit 2; }
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
APP=build/toolbar-dictation/TouchControls.app
mkdir -p "$APP"
for lang in en de; do cp -R "launcher/App/$lang.lproj" "$APP/"; done
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -isysroot "$SDK" -fobjc-arc -O1 -g \
    -Wall -Wextra -Werror -Wno-deprecated-declarations \
    -Ilauncher/Input -Ilauncher/Voice -Ilauncher/App \
    launcher/Input/*.m launcher/Voice/*.m launcher/App/WolkaraForeverLog.m \
    tests/test_toolbar_dictation.m -framework Foundation -framework UIKit -framework GameController \
    -framework AVFAudio -framework Speech -o "$APP/TouchControlsFixture"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.tolkara.tests.toolbar-dictation</string>
<key>CFBundleExecutable</key><string>TouchControlsFixture</string>
<key>CFBundleName</key><string>Touch input fixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/><key>UISceneConfigurations</key><dict/></dict>
</dict></plist>
PLIST
codesign --force --sign - "$APP" > /dev/null
xcrun simctl install "$SIM_ID" "$APP"
if [[ " $* " == *" --self-test "* ]]; then
    # simctl may report success even when the app aborts an assertion.
    LOG=build/toolbar-dictation/self-test.log
    xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.toolbar-dictation "$@" 2>&1 | tee "$LOG"
    grep -q 'VOICE PASS:' "$LOG"
else
    xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.toolbar-dictation "$@"
fi
