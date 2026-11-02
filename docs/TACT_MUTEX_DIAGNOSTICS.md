# Experimental TACT mutex diagnostic (External JIT only)

This branch investigates the repeatable World of Warcraft Forever 1.60.1.70532
startup crash, **not** a confirmed repair. StikDebug `universal.js` already
prepares executable memory and WoW reaches its own `main()` function, then a
TACT Task Thread encounters `EXC_BAD_ACCESS` at `0x198` inside
`libsystem_pthread.dylib` after roughly 40 seconds.

## What changed

The existing guest `pthread_mutex_lock` wrapper is now bound for
External JIT runs. If the guest supplies a low pointer (< 64 KiB), the wrapper
logs the pointer, caller return address, and guest-preferred call site
(maximum eight reports). **It then calls the original pthread function.**
Nothing is unlocked, skipped, faked, or made to succeed.

The diagnostic also snapshots 16 ARM64 instruction words before, and four
words after, the guest return address through the **writable alias** of the
prepared executable arena. These are the post-initializer code bytes, which
may differ from the executable as stored on disk. The word marked
`<call instruction>` is the instruction immediately before the return address.
This is still diagnostic only; raw instructions do not reveal object
ownership or prove the origin of a null pointer without further analysis.

The hook is scoped to **External JIT**; other execution modes keep their
existing binding behavior. The probe is intended for temporary use on this
branch, and can affect call timing, so it is not a production workaround.

## Build from Windows, no Mac required

The fork already has `.github/workflows/debug-ipa.yml`:

1. GitHub > **Actions** > **Build Wolkara Debug IPA**.
2. **Run workflow** with branch `diagnostics/tact-mutex-pointer`.
3. Download the **Wolkara-Debug-IPA** artifact and extract its ZIP.
4. Sign/install the IPA through the user's existing sideloader. To preserve
   existing game data, ensure the signing and bundle identifier match the
   already installed app. Back up the app's Documents first.
5. Enable JIT with StikDebug **universal.js** as before, then launch the game.
6. Export `On My iPhone > Wolkara/Tolkara > native-guest.log` and, if the
   game crashes, its new `_classic_beta_/Errors/*_Crash_*.txt` report.

## Interpret the log

Look for both the failing pointer and the instruction snapshot:

```text
[tact-probe] External JIT mutex diagnostics armed; low addresses will be logged without changing lock semantics
[tact-probe] pthread_mutex_lock mutex=0x198 caller=0x... guest_preferred=0x... (will call real pthread)
[tact-probe] arm64 preferred=0x... word=... <call instruction>
```

- **Probe line with `mutex=0x198`**: confirms the imported
  `pthread_mutex_lock` call came through the runtime hook. The
  `guest_preferred` address can be compared across ASLR-randomized runs.
  It **does not** identify why the pointer became invalid.
- **Armed line but no low-pointer line, with the same crash**: the
  fault may come from a different pthread entry point, an internal library
  call outside the runtime's binding hook, or a separate cause.
  Do **not** assume that a missing line means the pointer was valid.
- **No armed line**: check that the artifact was built from this branch
  and the app uses External JIT.
- **WoW changes behavior or runs**: gather the logs anyway. A
  timing-sensitive issue could appear different under instrumentation.

The repeated game-side crash's first guest frame was offset
`0x2a39cc4` from the guest's **reported mapped image base**, across
multiple runs; a disassembly of the exact build 70532 executable is
still needed to identify the calling routine. The same runs also
reported a TACT patch-index download failure, which is a separate
hypothesis, not yet established as the cause of the mutex fault.

Do not upload game credentials, personal signing keys, pairing records,
or complete game-data archives when sharing crash evidence.
