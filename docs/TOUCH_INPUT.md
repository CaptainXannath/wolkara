# Touch controls and text input

The toolbar offers mouse/trackpad, Apple keyboard, gamepad, settings, leave app,
microphone and saved-text key controls. Touches outside controls use the trackpad;
opening an editor releases held inputs. Settings → Edit layout lets you move both
the gamepad controls and individual toolbar buttons. Positions are saved relative
to the safe area and stay on screen when the window changes size. Transparency,
size, shoulder swapping and haptics remain configurable.

## Apple keyboard

Select the game's text field before opening the keyboard. Write or dictate into
the visible native draft; iOS autocorrection and spelling are enabled. **Replace**
replaces the whole focused game field without submitting. **Send** (including the
keyboard's Send key) replaces it, sends Return once and dismisses the keyboard.
An empty Replace clears the field. Duplicate submission callbacks are ignored.
Escape, Tab, arrows, game backspace and Return remain available on the accessory
row. Newlines and control characters in pasted text cannot become extra commands.

The bridge cannot inspect which game field is focused. Whole-field replacement
uses the game's macOS Select All/backspace behavior. Opening a draft never reads
text or passwords from the game. Closing or backgrounding discards the local draft;
temporary focus changes used by Apple's text UI preserve it.

## Microphone and reviewed dictation

Tap the microphone to send one Return (opening WoW chat) and start on-device Apple
Speech recognition. Partial and final results appear **only in the visible draft**.
Tap the draft to pause recognition and edit it with Apple's keyboard. Confirm with
✓ to send exactly the reviewed text, Return, then one Escape to close the empty chat.
Cancel with × to discard it and send one Escape. Backgrounding discards without
sending any keys. Late speech/permission callbacks cannot reopen or submit a draft.

Check that chat opened before confirming; the compatibility layer cannot identify
the game's focus. Speech and microphone permission, a supported language and
on-device recognition availability are required. This uses `SFSpeechRecognizer`,
not Whisper. You can also use Apple's own dictation microphone on its keyboard.

## Saved-text key

Tap the key to edit and save a value. Its explanation is:

> Hold key to type what's in the box and send it. Useful for your password

Holding the key for 0.6 seconds types the stored value and sends one Return. It
never opens chat first: select the destination field yourself. A tap only edits;
an empty save deletes the value. Storage uses this device's unlocked Keychain,
with no synchronization, clipboard copy, plaintext config or input diagnostics.
Unsaved editor text is cleared when the app enters the background. Wolkara and
WolkaraForever do not share this credential store.

## Implementation and checks

`translation/AppKit/TouchControls.m` owns UIKit editing; `AppKit.m` converts an
explicit submission into balanced macOS key events. `ToolbarDictationController`
owns the reviewed voice transaction. `SavedTextController` and `SavedTextStore`
keep stored values out of ordinary event diagnostics. The native-control event
pump services both default and tracking modes while the guest owns the main loop.

Run `tools/test_toolbar_dictation.sh --self-test` and
`tools/test_touch_controls_ui.sh --self-test`. The latter also accepts
`--saved-text-test`, `--review-draft-test`, `--toolbar-test` and
`--tracking-progress-test` with `--self-test`. Tests use synthetic app views,
speech/audio doubles and a Keychain double. The ad-hoc simulator fixture cannot
prove real device Keychain persistence or microphone capture; those require the
signed app on a physical device. No game input is automated by these tests.
