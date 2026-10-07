# External JIT prototype

Branch: `feature/external-jit-setup`, based on the working controller build
`e4d2b64`. This prototype adds the **WolkaraExternalJIT** Xcode scheme and
**Wolkara JIT** app. It leaves the normal Wolkara target and its game container
alone. Requires a physical arm64 device running iOS 26 or later.

## What is implemented

- The target contains no authorization extension, Network Extension entitlement,
  shared Keychain group, increased-memory-limit or extended-address-space
  entitlement. It requests development permission (`get-task-allow`).
- Play validates its development permission and StikDebug availability, then
  opens the documented `stikdebug://enable-jit` link for **this process only**,
  with the fixed `universal.js` script. URL acceptance alone is never readiness.
- After attachment, a worker prepares the existing External JIT arena. The UI
  stays responsive. Game entry requires published executable memory and a
  detached debugger. The runtime's existing entry checks still apply.
- Requests are single use. Errors and a five-minute timeout block startup;
  delayed completion cannot launch the game after failure. Once the helper has
  been contacted, retry requires closing the app and opening a new process.
- A separate **Test External JIT setup** diagnostic requests one page, writes
  our own `return 42` fixture, detaches, executes it, then writes and executes
  `return 1337`. It loads no game and consumes the session.

The updater and controllers are unchanged. External JIT is still preparation
per process, not a persistent disk cache or a guarantee of faster startup.

## Setup

1. Install Xcode and XcodeGen on the Mac. Generate the project with
   `bash tools/setup_external_jit.sh` (or `bash tools/generate.sh`). It opens
   Xcode without changing device data or enrolling anything.
2. Select **WolkaraExternalJIT**, your device, and your own **Personal Team** in
   Signing & Capabilities. Use a unique bundle ID ending in `.externaljit`.
   Alternatively keep personal values in ignored `local.env` so regeneration
   preserves them. Run with **Debug executable off** and Metal validation off;
   the shared scheme already disables both. Only this target needs provisioning.
3. Install [LocalDevVPN](https://apps.apple.com/app/id6755608044) and accept its
   VPN configuration on the phone. It does not require a LocalDev account.
4. Install [StikDebug](https://github.com/StikDebug/StikDebug) from its official
   release or build its source with your own Apple Account. It is a separate
   development-signed app, not bundled into Wolkara. This prototype was built
   against StikDebug **3.1.13** and its bundled `universal.js`.
5. Use the [official pairing guide](https://github.com/StikDebug/StikDebug-Guide/blob/main/pairing_file.md):
   connect the phone to the Mac, select it in iloader, choose **Manage Pairing
   File**, then **Place** beside StikDebug. Pairing management does not require
   entering Apple credentials into iloader. Accept device consent if requested.
   Do not export or publish the pairing file. Do not run Wolkara's integrated
   `tools/enroll.sh` for this target; the recipient is StikDebug.
6. Open StikDebug and finish its setup. Keep LocalDevVPN connected. In Wolkara
   JIT, open **Settings → Diagnostics and logs → Test External JIT setup**.
   Approve StikDebug's request if shown and return to Wolkara JIT. A successful
   report must explicitly say the sample executed **after detachment**.
7. Close Wolkara JIT from the app switcher after the test. Its separate library
   can then download a selected edition. Before copying a large existing game,
   first validate the capability and memory gates below. This prototype does
   not duplicate, import or remove the existing Wolkara installation's files.

Logs stay in this app's `Documents/external-jit.log` and
`external-jit.log.status.txt`, accessible through Files / Diagnostics. A
developer can launch only the synthetic check with `--external-jit-probe`.
Never enable JIT for a process that has already entered the game.

## Validation and remaining gates

2026-10-07: sanitizer request/protocol-failure tests and the complete
`tools/test_emulation.sh` suite pass. The Debug arm64 device build succeeds.
The installed app's signed entitlements were checked: development permission
present, tunnel/memory/sharing capabilities absent, no embedded extension.
The build used the existing development identity. **This does not prove free
Personal Team provisioning** or game memory capacity. On iPhone 16 Pro Max /
iOS 27, StikDebug 3.1.13 prepared our one-page fixture, detached, and both
execution and rewrite passed (`42`, then `1337`); the user confirmed the screen.
Physical results are recorded separately in `COMPATIBILITY.md`.

Commands used (personal identity/device values omitted):

```sh
bash tools/generate.sh
bash tools/test_external_jit.sh
bash tools/test_emulation.sh
xcodebuild -project Tolkara.xcodeproj -scheme WolkaraExternalJIT \
  -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/iphone-external-jit-signed -allowProvisioningUpdates \
  ARCHS=arm64 TOLKARA_SYSTEM_ROOTS=YES clean build
```

Before calling this a public free-account workflow, verify actual Personal Team
signing, full-game memory/address-space needs without special entitlements,
manual gameplay, client updates, restart/reboot, cellular-only startup and
seven-day signature renewal without deleting the game. Apple's free
[Personal Team limits](https://developer.apple.com/help/account/basics/about-your-developer-account)
still apply. Moving the tunnel to LocalDevVPN does not eliminate a local VPN or
establish cellular reliability. StikDebug may request new pairing after an OS
update. Setup is not yet one-click and no faster startup measurement is claimed.

This integration implements the documented
[StikJIT URL and breakpoint protocol](https://github.com/StikDebug/StikJIT/blob/main/INTEGRATION.md)
using original host code. No StikDebug/StikJIT source or script is included, and
no game executable is patched, re-signed, repackaged or redistributed.
