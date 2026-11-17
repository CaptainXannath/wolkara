# Experimental TACT mutex diagnostic (External JIT only)

This branch investigates the repeatable World of Warcraft Forever 1.60.1.70532
startup crash, **not** a confirmed repair. StikDebug `universal.js` already
prepares executable memory and WoW reaches its own `main()` function, then a
TACT Task Thread encounters `EXC_BAD_ACCESS` at `0x198` inside
`libsystem_pthread.dylib` after roughly 40 seconds.

## November 1: new evidence in native-guest(5).log

The updated diagnostics reported:

```text
[tact-state] saved_caller_x19=0x14c34c480
[tact-state] *(x19+0x10)=0x14c0e40a0
[tact-state] *(*(x19+0x10)+0x700)=0
[tact-probe] earlier guest frame=... guest_preferred=0x102a0bf10
```

The 0x700 field is NULL **at crash time**. The known ARM64 sequence
near the earlier return address loads `x0` from that 0x700 field
before calling an intermediary. A direct `BL` at preferred
`0x102a0bf0c` targets preferred `0x102a2dcac`; this intermediary's
internal operations are the next missing evidence. It is not yet
established that the null 0x700 field was the actual `x0` used at
that call, or that it is caused by a missing download.

The diagnostic now also snapshots 96 ARM64 instruction words from the
intermediary's preferred entry `0x102a2dcac` (after WoW's unpacking,
via the safe read/write alias). Look for `[tact-middle]` messages.
Do not suppress the mutex, fabricate the missing object, or claim a fix.

The earlier WoW crash reports also showed
`Failed to download the patch index`. Since WoW has an
`enableBGDL` CVar, a reversible independent test is to back up
`World of Warcraft/_classic_beta_/WTF/Config.wtf`, close Wolkara,
and set `SET enableBGDL "0"` in it. This is not a proven solution;
BGDL may not be the initializing TACT subsystem or may be ignored
by this client. Revert to the original file after the test.

## November 1, 23:35:34: exact null-pointer path confirmed

The sixth device log `native-guest(6).log`, from the debug IPA produced by
GitHub Actions run [41394284982](https://github.com/CaptainXannath/wolkara/actions/runs/41394284982),
includes the intermediary's live post-unpack instructions. This proves the
following path in WoW Forever **1.60.1.70532**:

```asm
; Previously traced task object (x19), and the nested object.
0x102a0bee4: ldr x8, [x19, #0x10]
0x102a0bee8: ldr x0, [x8, #0x700]     ; the captured field is NULL
0x102a0beec: cbz w1, 0x102a0bf08    ; this path leads to the failing call
0x102a0bf08: mov x1, x2
0x102a0bf0c: bl  0x102a2dcac

; The targeted intermediary does not validate the pointer.
0x102a2dcac: add x0, x0, #0x28       ; NULL becomes 0x28
0x102a2dcb0: ldr w1, [x1]
0x102a2dcb4: b   0x102a39c9c

; Its tail-call helper constructs the mutex pointer.
0x102a39cb8: add x19, x0, #0x170     ; 0x28 + 0x170 = 0x198
0x102a39cbc: mov x0, x19
0x102a39cc0: bl  pthread_mutex_lock   ; invalid address 0x198
```

The first step and the null `+0x700` field were also independently
captured by the saved-register pointer reads. Together, these strongly
establish that the bad mutex is a **consequence of a null TACT object**,
not an error caused by pthread synchronization itself.

**Root cause still not known**: we have not established whether the object
was never allocated, initialized too late, freed, or absent due to some
upstream CASC/download/compatibility failure.

### Certificate hypothesis tested

The debug IPA used for this sixth test was built with
`TOLKARA_SYSTEM_ROOTS=YES`, confirmed in the actual GitHub Actions job log.
The identical crash persisted. A missing public-root certificate package
alone therefore **does not explain this crash**, though the certificate
test does not establish the full TACT network state.

**Do not** replace the null object with a fake object, skip the mutex
call, or claim these diagnostics repair the game. Prefer a controlled
test of WoW's `enableBGDL` setting (if not already done) and compare
the next WoW crash report's `BGDLEnabled` and streaming diagnostics.
Also distinguish installer **Verify and repair** completion from game
runtime TACT patch-index fetching.

## November 2: background-download disable test completed

On iPhone, the user edited the existing
`Documents/World of Warcraft/_classic_beta_/WTF/Config.wtf` and
confirmed the saved line `SET enableBGDL "0"`. The next **new** WoW
crash report `2026-11-02_12.06.18_Crash_22439.txt` (build
1.60.1.70532) explicitly reports:

```text
<BGDLEnabled> No
<CVar.enableBGDL> 0
EXC_BAD_ACCESS: KERN_INVALID_ADDRESS at 0x198
Failed to download the patch index. E-Key: fad27dc8c6b75e4c58d194d338e0ac5f.
Server: 4294967295 | Error (1): unknown failure
```

The TACT Task Thread still faults via the existing
`local.tolkara.app` pthread wrapper at the same WoW callsite;
uptime was 42 seconds, `Current Frame: 0`,
`No GX Device Created`, and successful WoWConnections was 0.

**Result:** The config file is being read, and switching off
background downloading does not avoid the null-object/mutex crash;
the patch-index failure also persists. Do not request that the user
repeat this test or suggest editing the same setting again. This
does not establish whether failed patch-index retrieval *causes* the
uninitialized object or is a separate consequence.

**Next evidence to collect:** Separate the game-runtime TACT
patch-index failure from the app's own installer/update verification.
Back up game data, use Wolkara Settings > Verify and repair game
files once, record whether that check *completes or fails* and its
specific error, then compare the next startup diagnostics. Do not
delete the Data directory or overwrite user settings. If repair
completes but runtime patch-index fetching still fails, focus on
TLS/CDN/file-access compatibility instrumentation rather than
silencing synchronization faults.

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

### November 1, follow-up: earlier frame captured

The next run, `native-guest(4).log`, confirmed the invalid mutex pointer and
produced another stable return address at `0x102a0bf10`. A branch from
`0x102a0bf0c` targets an **intermediate guest routine**, not the helper
containing the mutex call. Therefore the earlier frame's address does
**not** prove it is the direct caller or identify the initialization
step responsible for `0x28`.

The instructions near that earlier frame include:

```asm
ldr x8, [x19, #0x10]
ldr x0, [x8, #0x700]
```

This is only a candidate source of an object pointer; branch conditions and
intervening functions still need to be accounted for.

The next probe version reads the **saved caller x19** from the known
WoW-70532 mutex helper's frame (FP-8), followed by two **read-only,
checked** pointer reads at `x19+0x10` and
`*(x19+0x10)+0x700`. It also inspects up to three older guest frame
records, with short instruction snapshots. All reads use
`vm_read_overwrite` and may legitimately report unavailable; no data
is written. New log prefixes are `[tact-state]`, `[tact-chain]`, and
`[tact-chain-insn]`.

**Interpretation:** if the candidate field contains `0x28`, it supports
the hypothesis that an uninitialized pointer is stored in a TACT-related
object. It still does not establish which earlier failure caused that
state or whether the patch-index download error is causal. Do not
substitute dummy objects, patch WoW code, or suppress mutex calls.

### November 1: the pointer is derived from 0x28

The captured callsite at preferred address `0x102a39cc4` disassembles as:

```asm
mov x21, x0
add x19, x0, #0x170
mov x0, x19
bl pthread_mutex_lock
```

The actual mutex argument is `0x198`, so `x0` on entry to this WoW
function was `0x28`. That is strong evidence of an already-invalid object
pointer (possibly a null base plus a `0x28` field offset); it does **not**
establish which earlier initialization step failed.

The probe follows a validated ARM64 frame record to capture an **earlier
return address** and 64 preceding and eight following instruction words
through the prepared arena's writable alias. Look for `[tact-probe]
earlier guest frame=...` and `[tact-upstream] arm64 preferred=...
word=...` with a `<upstream call>` marker. This frame may not be the
immediate caller. A frame-chain failure is logged without
changing game execution.

The hook is scoped to **External JIT**; other execution modes keep their
existing binding behavior. The probe is intended for temporary use on this
branch, and can affect call timing, so it is not a production workaround.

## Build from Windows, no Mac required

The fork already has `.github/workflows/debug-ipa.yml`:

1. GitHub > **Actions** > **Build Wolkara Debug IPA**.
2. **Run workflow** with branch `diagnostics/tact-mutex-pointer`. The
   workflow now offers `public_root_certificates`: select `YES` for the
   first test. The existing `NO` configuration can be tested afterward to
   compare whether certificate trust affects patch-index downloads. This
   affects only the experimental debug IPA; the public release workflow
   remains unchanged.
3. Download the **Wolkara-Debug-IPA** artifact and extract its ZIP.
4. Sign/install the IPA through the user's existing sideloader. To preserve
   existing game data, ensure the signing and bundle identifier match the
   already installed app. Back up the app's Documents first.
5. Enable JIT with StikDebug **universal.js** as before, then launch the game.
6. Export `On My iPhone > Wolkara/Tolkara > native-guest.log` and, if the
   game crashes, its new `_classic_beta_/Errors/*_Crash_*.txt` report.

## Interpret the log

Look for the failing pointer, its immediate caller, and the upstream instruction snapshot:

```text
[tact-probe] External JIT mutex diagnostics armed; low addresses will be logged without changing lock semantics
[tact-probe] pthread_mutex_lock mutex=0x198 caller=0x... guest_preferred=0x... (will call real pthread)
[tact-probe] arm64 preferred=0x... word=... <call instruction>
[tact-probe] earlier guest frame=0x... guest_preferred=0x...
[tact-upstream] arm64 preferred=0x... word=... <upstream call>
[tact-state] saved_caller_x19=0x...
[tact-state] *(*(x19+0x10)+0x700)=0x...
[tact-chain] depth=2 return=0x... guest_preferred=0x...
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
