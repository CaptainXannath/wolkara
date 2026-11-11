#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/public-roots
python3 -m unittest tests.test_public_roots -v

if [ "${1:-}" = --simulator ]; then
    SIM=${SIMULATOR:-iPhone 17 Pro}
    SIM_ID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = [d for group in json.load(sys.stdin)["devices"].values() for d in group if sys.argv[1] in (d["name"], d["udid"])]
devices.sort(key=lambda d: d["state"] != "Booted")
print(devices[0]["udid"] if devices else "")' "$SIM")
    [ -n "$SIM_ID" ] || { echo "No matching simulator; set SIMULATOR."; exit 2; }
    xcrun simctl bootstatus "$SIM_ID" -b
    APP=build/public-roots/ios/PublicRoots.app
    mkdir -p "$APP"
    python3 tools/package_public_roots.py "$APP"
    xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator \
        -fobjc-arc -O1 -g -Wall -Wextra -Werror -Wno-deprecated-declarations \
        -Itranslation/Security -framework Foundation -framework Security -framework UIKit \
        translation/Security/Keychain.m tests/test_system_roots_app.m -o "$APP/PublicRoots"
    cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.tolkara.tests.public-roots</string>
<key>CFBundleExecutable</key><string>PublicRoots</string>
<key>CFBundleName</key><string>Public certificate tests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
    codesign --force --sign - "$APP"
    xcrun simctl install "$SIM_ID" "$APP"
    LOG=build/public-roots/simulator-tests.log
    xcrun simctl launch --terminate-running-process --console "$SIM_ID" org.tolkara.tests.public-roots 2>&1 | tee "$LOG"
    grep -q '^system roots: .* pass$' "$LOG"
else
    APP=build/public-roots/mac/PublicRoots.app
    mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
    python3 tools/package_public_roots.py "$APP/Contents/Resources"
    cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.tolkara.tests.public-roots</string>
<key>CFBundleExecutable</key><string>PublicRoots</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
    xcrun clang -fobjc-arc -Wall -Wextra -Werror -Wno-deprecated-declarations \
        -O1 -g -fsanitize=address,undefined -Itranslation/Security \
        -framework Foundation -framework Security translation/Security/Keychain.m \
        tests/test_system_roots.m -o "$APP/Contents/MacOS/PublicRoots"
    "$APP/Contents/MacOS/PublicRoots" --bundled
fi
