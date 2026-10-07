#!/bin/bash
# UIKit visual fixture only. Requires an already booted iPhone/iPad simulator.
# On multi-screen devices set SIMULATOR_DISPLAY to the active screen from `simctl io ... enumerate`.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
probe_simulator="${1:-booted}"
probe_appearance="${2:---light}"
mkdir -p build/LaunchProgressProbe.app build/launch-progress
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator \
    -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -fobjc-arc -Wall -Wextra -Werror -Ilauncher/App -framework UIKit -framework QuartzCore \
    launcher/App/LaunchProgressView.m launcher/App/StartupActivity.m launcher/App/StartupActivityText.m tests/launch_progress_probe.m \
    -o build/LaunchProgressProbe.app/LaunchProgressProbe
python3 - <<'PY'
import plistlib
from pathlib import Path
info = {
    'CFBundleIdentifier': 'local.tolkara.LaunchProgressProbe',
    'CFBundleName': 'Launch Progress Probe', 'CFBundleExecutable': 'LaunchProgressProbe',
    'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0', 'CFBundlePackageType': 'APPL',
    'LSRequiresIPhoneOS': True, 'UIDeviceFamily': [1, 2], 'UILaunchScreen': {},
    'UISupportedInterfaceOrientations': ['UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'],
    'UIApplicationSceneManifest': {
        'UIApplicationSupportsMultipleScenes': False,
        'UISceneConfigurations': {'UIWindowSceneSessionRoleApplication': [
            {'UISceneConfigurationName': 'Default', 'UISceneDelegateClassName': 'ProgressProbe'}]},
    },
}
Path('build/LaunchProgressProbe.app/Info.plist').write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - build/LaunchProgressProbe.app
xcrun simctl install "$probe_simulator" build/LaunchProgressProbe.app
xcrun simctl launch --terminate-running-process "$probe_simulator" local.tolkara.LaunchProgressProbe "$probe_appearance" \
    > build/launch-progress/launch.txt
python3 - "$probe_simulator" <<'PY'
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

pid = int(Path('build/launch-progress/launch.txt').read_text().strip().split(':')[-1])
def screenshot(name):
    display = ['--display=' + os.environ['SIMULATOR_DISPLAY']] if os.environ.get('SIMULATOR_DISPLAY') else []
    subprocess.run(['xcrun', 'simctl', 'io', sys.argv[1], 'screenshot',
                    *display, 'build/launch-progress/' + name + '.png'], check=True, capture_output=True)
time.sleep(3)
screenshot('before')
# The probe holds its main thread from 4 to 10 s: the activity lines must still change.
time.sleep(3)
screenshot('busy-1')
time.sleep(2.5)
screenshot('busy-2')
container = subprocess.check_output(['xcrun', 'simctl', 'get_app_container', sys.argv[1],
                                     'local.tolkara.LaunchProgressProbe', 'data'], text=True).strip()
ready = Path(container) / 'Documents/progress-game-ready.txt'
deadline = time.monotonic() + 20
while not ready.exists():
    if time.monotonic() >= deadline:
        raise RuntimeError('The synthetic startup did not reach the Game phase')
    time.sleep(0.2)
time.sleep(1)  # Let the final main-thread transaction reach the compositor before suspension.
screenshot('game')
try:
    os.kill(pid, signal.SIGSTOP)
    time.sleep(3)
    screenshot('suspended')
finally:
    try:
        os.kill(pid, signal.SIGCONT)
    except ProcessLookupError:
        pass
print('Review build/launch-progress screenshots: Memory becomes Game only after the fixture finishes its step;')
print('activity in the current segment must remain visible while the process is suspended (no elapsed counter).')
print('busy-1 and busy-2 (main thread held): the activity step, its seconds and the report size must advance.')
PY
