# Custom Photo-Style WoW HUD & Side Ability Buttons

This custom build updates Wolkara's in-game touch UI (based on the `v0.1.0-stikdebug.1` External JIT repair source) to match a minimal, photo-style mobile WoW HUD with addable side ability buttons.

## What Changed

- **Collapsible Top-Center Pill (`⌄`)** (`translation/AppKit/TouchControls.m`):
  - Gameplay starts with a single compact dark/warm-gold chevron pill at top-center (`⌄`).
  - Tap it to expand or collapse the Wolkara utility bar (mouse/trackpad, keyboard, HUD/gamepad mode toggle, settings, dictation, saved-text key, and leave game).
- **Photo HUD Mode (Default)** (`translation/AppKit/TouchGamepad.m`, `TouchGamepadLayout.h/.m`):
  - **Bottom-Left**: Clean circular movement joystick (no bulky outer D-pad sector wheel; double-tap still sends L3).
  - **Bottom-Right**: **`Target`** pill (`Tab`), **`Interact`** pill (`F`), **`Jump`** circle (`Space`), and **`Camera`** drag pad (right-mouse camera/character look by default, or left-mouse orbit in Settings).
  - Expand `⌄` and tap the controller icon to switch between **Photo HUD** and **Full Gamepad** mode anytime, or hold to hide/show controls.
- **Side Ability Buttons (`+ Left` / `+ Right`)** (`translation/AppKit/TouchActionLayout.h/.m`, `TouchActionOverlay.m`):
  - Defaults to **8 left-side buttons** (`1`–`8`, above the left joystick) and **8 right-side buttons** (`C-1`–`C-8`, below the minimap and above `Camera`).
  - Open **⌄ → Settings (gear) → Side Ability Buttons (+ Left / + Right)…** to:
    - Add more buttons onto the **left** or **right** sides (`+ Left` / `+ Right`).
    - Bind any circle to a **Keyboard hotkey** (`1`–`0`, `-`, `=`, `F1`–`F12`, `Space`, `Tab`, `Esc`, letters, plus `Shift`/`Ctrl`/`Alt`/`Cmd` modifiers) OR a **Gamepad chord** (`A/B/X/Y/LB/RB/D-pad + LT/RT`).
    - Set a custom short label, adjust **Fill** and **Border** opacity (down to `0%` to overlay WoW's own circular action bar icons), or toggle labels on/off during play.
    - Drag circles individually, per side/group, or as a whole layout; dragging across any ability circle still smoothly pans the camera.

## Building the `.ipa`

Compiling iOS Objective-C/Swift into an `.ipa` requires **Xcode + XcodeGen on macOS**. You have two ways to produce the `.ipa` from this project:

1. **GitHub Actions (no Mac required):**
   - Push this folder (`C:\Users\hydro\.gemini\antigravity\scratch\wolkara-custom-ui`) to a GitHub repository (`main` branch), or trigger **Actions → Build Custom HUD Wolkara IPA → Run workflow**.
   - Download `Wolkara-custom-hud-IPA` from the completed workflow run's **Artifacts** and sideload with development signing (`get-task-allow`) for StikDebug.
2. **On a Mac:**
   ```bash
   chmod +x tools/*.sh tools/*.py
   TOLKARA_SYSTEM_ROOTS=NO bash tools/package_external_jit_ipa.sh Wolkara-custom-hud.ipa
   ```
