# Custom Photo-Style WoW HUD & Side Ability Buttons

This custom build updates Wolkara's in-game touch UI (based on the `v0.1.0-stikdebug.1` External JIT repair source) to match a minimal, photo-style mobile WoW HUD with addable side ability buttons.

## What Changed

- **External JIT Memory & Performance Tuning** (`runtime/NativeGuest.m`, `launcher/WoW/WoWViewController.m`, `addons/WolkaraMobile/`):
  - Caps External JIT arena reservation to 256 MiB (with `MADV_FREE` on unused arena pages past the loaded image) so StikDebug page-marking does not exhaust iOS Jetsam limits on devices without `increased-memory-limit`.
  - Defaults iPhone External JIT builds to **Settings → Rendering quality → Performance (1×)** (with active checkmark in Settings; **Balanced (2×)** remains selectable).
  - Lazily constructs `WolkaraMobile` ability buttons as needed instead of eagerly creating all 64 secure frames on load.
- **Top-Center Collapsible Pill (`⌄`) & Zero-Scroll 2-Row Glass Drawer** (`translation/AppKit/TouchControls.m`):
  - Gameplay (and Login) starts with a single compact dark/warm-gold chevron pill at top-center (`⌄`).
  - Tap `⌄` to open the **zero-scroll 2-row floating drawer** (tap anywhere outside the drawer or tap `^` to dismiss):
    - **Row 1 — WoW Windows** (auto-closes after opening): **`Char`** (`C`), **`Bags`** (`B`), **`Spells`** (`P`), **`Profs`** (`TOGGLEPROFESSIONBOOK` / `K`), **`Talents`** (`N`), **`Quests`** (`L`), **`Collect`** (`Shift+P`), **`Map`** (`M`), and **`Menu`** (`GameMenuFrame` via `ALT-F5` / `Esc`).
    - **Row 2 — Quick Tools**: **`Chat`**, **`Voice`**, **`Saved`**, **`Trackpad`** (glows cyan when ON), **`Edit Arcs`**, **`Edit HUD`**, **`Settings`** (opens the 3-tab Settings sheet directly), and **`Leave`**.
- **3-Tab Segmented Settings Sheet (`HUD` | `Controls` | `Style`)** (`translation/AppKit/TouchGamepad.m`):
  - **`HUD`**: Quick buttons for **Edit Spell Arcs**, **Edit HUD Layout**, and **Custom Buttons…**, plus switches for Round Spell Icons, Left Stick WASD, Auto-hide on Controller/KB+M, Haptics, and Performance Overlay.
  - **`Controls`**: Binding pickers (`Target`, `Interact`, `Jump`, `Right Stick`), live **Camera Sensitivity** slider, and tappable live visibility chips for all 7 HUD controls (`Target`, `Interact`, `Jump`, `Right Stick`, `Shift`, `Ctrl`, `R-Click`).
  - **`Style`**: Live **Transparency**, **Button Size**, and **Stick Size** sliders, **Photo HUD / Full Gamepad** mode switcher, and **Outer Triggers**.
- **Seamless Curved Side Ability Arcs (`WolkaraMobile`)** (`addons/WolkaraMobile/`, `launcher/WoW/MobileInterface.*`, `translation/AppKit/AKMobileInterface.h`):
  - Automatically mirrors populated WoW action bars into left & right curved thumb arcs on load (hiding desktop bottom bars cleanly while leaving stances/pets visible, and restoring desktop bars automatically whenever round touch icons are turned off or external hardware is connected).
  - Tap **⌄ → Edit Arcs** (or `/wm edit`) for the interactive arc editor:
    - Drag **`Move arc`** above either the Left or Right arc to reposition the entire curved group anywhere on screen.
    - Tap **`+`** above either arc to immediately add spells, professions, bag items, macros, or built-in actions from the Picker.
    - Tap any icon in an arc to select it (name shown at top center) and tap **`Assign`** or **`Remove`**, or tap/drag two icons to swap slots; use **`‹ Set 1 / N ›`** + **`Add set`** / **`Remove set`** for multiple spell pages.
    - Use the bottom **`Default | Cancel | Save`** pill to reset to synced defaults, discard draft changes, or apply live out of combat.
  - Also supports direct Spellbook/Bags drag-and-drop onto any round button or tapping an empty slot.
- **Photo HUD Mode with Left + Right Joysticks & Auto-Hide on Hardware** (`translation/AppKit/TouchGamepad.m`, `TouchGamepadLayout.h/.m`):
  - **Bottom-Left**: Circular movement joystick (supports analog controller stick or **Left Stick: WASD Keys**), alongside quick-access **`Shift`**, **`Ctrl`**, and **`R-Click`** pills (quick-tap to toggle ON/OFF with gold highlight, or hold with one thumb while tapping vendor/bag items with the other finger for stack-buy `Shift + R-Click`, Dressing Room `Ctrl + Click`, or one-tap vendor buying/selling `R-Click`; draggable in **Edit HUD** and toggleable in **Settings → HUD Controls**).
  - **Bottom-Right**: Circular **Right Joystick** (replaces the "Camera" label box — push/hold to smoothly rotate the WoW camera in 360° using Right Drag or Left Orbit mode, plus double-tap for R3), alongside **`Target`** (`Auto`, cycling enemies and out-of-combat friendly NPCs via `WolkaraMobile` with `Tab` fallback), **`Interact`** (`Auto`, `INTERACTTARGET` via `WolkaraMobile` with `F` fallback and first-run `SoftTargetInteract=3` initialization), and **`Jump`** (`Space`).
  - **Automatic Hardware Detection**: Connecting a physical game controller (`GCController`), hardware mouse (`GCMouse`), or hardware keyboard (`GCKeyboard`) automatically hides all on-screen touch HUD controls, top chrome, and circular spell arcs (restoring desktop WoW bars), and brings them back automatically when disconnected (toggleable in Settings via **Auto-hide on Controller / KB+M**).
  - **Edit HUD**: Tap **⌄ → Edit HUD** (or Settings) to drag any button/joystick freely on grid with the same **`Default | Cancel | Save`** pill.
- **PlayPort-Style Custom Buttons (Optional Overlay)** (`translation/AppKit/TouchActionLayout.h/.m`, `TouchActionOverlay.m`):
  - Auto-hidden whenever **Round Spell Icons (WoW)** is active so Blizzard spell circles aren't covered; turn **Touch abilities** on inside **Settings → Custom Buttons (Drag & Drop)…** to use both or run custom iOS overlay buttons independently.
  - Defaults to **8 left-side buttons** (`1`–`8`) and **8 right-side plain buttons** (`9`, `0`, `-`, `=`, `F1`–`F4`) with **no `Ctrl+` chords**.
  - Open **⌄ → ... → Settings (gear) → Custom Buttons (Drag & Drop)…** (or **Edit Layout → Edit Buttons…**) to:
    - **Drag `⊕ Drag Button`** directly off the palette and drop a new button anywhere on screen (with toggleable 16pt **Snap** grid, or **Clear** to start from an empty canvas), and switch between **3 independent Profiles (1–3)**.
    - Opens in **Drag One** mode by default: drag any individual button, double-tap or tap **Label**, **Copy** to duplicate, **Delete**, or switch between **Drag One**, **Side / Group**, and **Move All**.
    - Customize each button's **Behavior** (**Tap**, **Hold**, or **Toggle**), **Shape** (**Circle**, **Pill**, or **Box** + **Stretch** width slider), and **Color** (`Default`, `Gold`, `Red`, `Blue`, `Green`, `Purple`, `Clear`).
    - Bind any button to a **Keyboard key** (`1`–`0`, `-`, `=`, `F1`–`F12`, **Arrows & Nav**, sticky standalone **`Shift`/`Ctrl`/`Alt`/`Cmd`**, `Space`, `Tab`, `Esc`, letters, optional modifiers), a **Mouse click** (`LMB`/`RMB`/`MMB`), or a **Gamepad chord**.
    - Dock (`⇅ Bottom` / `⇅ Top`) or drag the editor bar anywhere, adjust **Fill** and **Border** opacity (down to `0%` over WoW action bars), and toggle labels on/off.

## Building & Publishing a Release

Compiling iOS Objective-C/Swift into an `.ipa` requires **Xcode + XcodeGen on macOS**:

1. **GitHub Actions & Releases (no Mac required):**
   - Push to `feature/photo-hud` (or `main`) to build `Wolkara-IPA` (`Wolkara.ipa` + `Wolkara.ipa.sha256`) and run simulator tests.
   - To publish a GitHub Release automatically after all tests pass:
     - Either push a version tag (for example `v0.2.0`), or run **Actions → Build & Release Wolkara IPA → Run workflow** and enter a `release_tag` (such as `v0.2.0`).
   - Download `Wolkara.ipa` from the Release (or workflow artifact) and sideload with development signing (`get-task-allow`) for StikDebug.
2. **On a Mac:**
   ```bash
   chmod +x tools/*.sh tools/*.py
   TOLKARA_SYSTEM_ROOTS=NO bash tools/package_external_jit_ipa.sh Wolkara.ipa
   ```
