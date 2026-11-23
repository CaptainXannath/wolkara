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
- **Drag-and-Drop Custom Buttons** (`translation/AppKit/TouchActionLayout.h/.m`, `TouchActionOverlay.m`):
  - Defaults to **8 left-side buttons** (`1`–`8`) and **8 right-side plain buttons** (`9`, `0`, `-`, `=`, `F1`–`F4`) with **no `Ctrl+` chords**.
  - Open **⌄ → Settings (gear) → Custom Buttons (Drag & Drop)…** (or **Edit Layout → Edit Buttons…**) to:
    - **Drag `⊕ Drag Button`** directly off the palette and drop a new button anywhere on screen (with toggleable 16pt **Snap** grid, or **Clear** to start from an empty canvas).
    - Opens in **Drag One** mode by default: drag any individual button, double-tap or tap **Label**, **Copy** to duplicate, **Delete**, or switch between **Drag One**, **Side / Group**, and **Move All**.
    - Bind any circle to a **Keyboard key** (`1`–`0`, `-`, `=`, `F1`–`F12`, `Space`, `Tab`, `Esc`, letters, optional `Shift`/`Ctrl`/`Alt`/`Cmd`), a **Mouse click** (`LMB`/`RMB`/`MMB`), or a **Gamepad chord**.
    - Dock (`⇅ Bottom` / `⇅ Top`) or drag the editor bar anywhere, adjust **Fill** and **Border** opacity (down to `0%` over WoW action bars), and toggle labels on/off.

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
