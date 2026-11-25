# Custom Photo-Style WoW HUD & Side Ability Buttons

This custom build updates Wolkara's in-game touch UI (based on the `v0.1.0-stikdebug.1` External JIT repair source) to match a minimal, photo-style mobile WoW HUD with addable side ability buttons.

## What Changed

- **External JIT Memory & Performance Tuning** (`runtime/NativeGuest.m`, `launcher/WoW/WoWViewController.m`, `addons/WolkaraMobile/`):
  - Caps External JIT arena reservation to 256 MiB (with `MADV_FREE` on unused arena pages past the loaded image) so StikDebug page-marking does not exhaust iOS Jetsam limits on devices without `increased-memory-limit`.
  - Defaults iPhone External JIT builds to **Settings → Rendering quality → Performance (1×)** (with active checkmark in Settings; **Balanced (2×)** remains selectable).
  - Lazily constructs `WolkaraMobile` ability buttons as needed instead of eagerly creating all 64 secure frames on load.
- **Top-Center Quick Menu Bar & Collapsible Pill (`⌄`)** (`translation/AppKit/TouchControls.m`):
  - Gameplay (and Login) starts with a single compact dark/warm-gold chevron pill at top-center (`⌄`).
  - Tap `⌄` to expand the top WoW bar: **`Chat | Bags | Map | Character | Talents | Quests | Spellbook | ^ | ...`**.
  - Tap **`Chat`** to toggle the keyboard, **`Bags`–`Spellbook`** (`B`, `M`, `C`, `N`, `L`, `P`) to open game windows, **`...`** to show Wolkara's utility buttons (mouse/trackpad, keyboard, HUD/gamepad mode toggle, settings, dictation, saved-text key, and leave game), or **`^`** to collapse everything back to `⌄`.
- **Round Blizzard Spell/Item Drag-and-Drop Side Buttons (`WolkaraMobile`)** (`addons/WolkaraMobile/`, `launcher/WoW/MobileInterface.*`, `translation/AppKit/AKMobileInterface.h`):
  - Automatically stages the upgraded `WolkaraMobile` companion addon into `_forever_/Interface/AddOns/WolkaraMobile` (enabled by default for Forever; toggle anytime via **Settings → Round Spell Icons (WoW)** and **Arrange Spell Icons…**, or `/wm` in chat).
  - Pre-seeds **20 circular masked Blizzard icon slots** (12 on the left side + 8 on the right side).
  - Open **Spellbook** or **Bags** and **touch-hold-and-drag** any spell, item, or macro directly onto any round button, or tap an empty circle for the **Spells / Items / Macros / Actions Picker** (with an **Edit Layout** shortcut).
  - In **Arrange Spell Icons…** or `/wm edit`, drag round buttons freely, adjust size, toggle **Hide empty**, **Move/size all**, **Reset sides**, and tap **Done & save**.
- **Photo HUD Mode (Default)** (`translation/AppKit/TouchGamepad.m`, `TouchGamepadLayout.h/.m`):
  - **Bottom-Left**: Clean circular movement joystick (no bulky outer D-pad sector wheel; double-tap still sends L3).
  - **Bottom-Right**: **`Target`** pill (`Tab`), **`Interact`** pill (`F`), **`Jump`** circle (`Space`), and **`Camera`** drag pad (right-mouse camera/character look by default, or left-mouse orbit in Settings), plus per-button visibility toggles (**Right HUD Controls**) and a **Left Stick: WASD Keys** option in Settings.
  - Expand `⌄ → ...` and tap the controller icon to switch between **Photo HUD** and **Full Gamepad** mode anytime, or hold to hide/show controls.
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
