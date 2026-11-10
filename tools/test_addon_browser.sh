#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SIM=${SIMULATOR:-iPhone 17 Pro}
SIM_ID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
items=[d for group in json.load(sys.stdin)["devices"].values() for d in group if sys.argv[1] in (d["name"],d["udid"])]
items.sort(key=lambda d:d["state"]!="Booted")
print(items[0]["udid"] if items else "")' "$SIM")
[ -n "$SIM_ID" ] || { echo 'Set SIMULATOR to an available simulator.'; exit 2; }
xcrun simctl bootstatus "$SIM_ID" -b > /dev/null
ROOT=$PWD/build/addon-browser
APP=$ROOT/AddonBrowserFixture.app
mkdir -p "$APP"
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -O1 -g -Wall -Wextra -Werror \
    -Wno-deprecated-declarations launcher/WoW/AddonBrowser.m launcher/App/WKLocalization.m launcher/App/WolkaraForeverTheme.m launcher/App/WolkaraForeverLog.m \
    tests/test_addon_browser_app.m -framework UIKit -framework WebKit -framework Foundation -framework CoreGraphics -o "$APP/AddonBrowserFixture"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.tolkara.tests.addon-browser</string>
<key>CFBundleExecutable</key><string>AddonBrowserFixture</string>
<key>CFBundleName</key><string>Addon browser fixture</string><key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string><key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict><key>UIApplicationSupportsMultipleScenes</key><false/><key>UISceneConfigurations</key><dict/></dict>
<key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
<key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationLandscapeLeft</string><string>UIInterfaceOrientationLandscapeRight</string></array>
</dict></plist>
PLIST
for lang in en de; do cp -R "launcher/App/$lang.lproj" "$APP/"; done
codesign --force --sign - "$APP" >/dev/null
xcrun simctl install "$SIM_ID" "$APP"
server_pid=''
trap 'if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; fi' EXIT
if [ "${1:-}" = --live ]; then
    args=(--live)
else
    port_file=$(mktemp "$ROOT/port.XXXXXX")
    python3 tools/tests/addon_web_server.py "$port_file" &
    server_pid=$!
    for _ in {1..50}; do [ -s "$port_file" ] && break; sleep 0.1; done
    port=$(cat "$port_file"); rm "$port_file"
    [ -n "$port" ] || exit 1
    args=("http://127.0.0.1:$port/")
fi
xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.addon-browser "${args[@]}" 2>&1 | tee "$ROOT/result.log"
if [ "${1:-}" = --live ]; then
    grep -q 'ADDON WEB LIVE:' "$ROOT/result.log"
else
    grep -q 'ADDON WEB PASS:' "$ROOT/result.log"
fi
