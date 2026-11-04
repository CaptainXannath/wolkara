# Forever 70755 patch-index retrieval and owner diagnostics

This continues [the 70755 network investigation](TACT_70755_INVESTIGATION.md).
The patch archive index repair completed on the device, but the subsequent
clean launch still crashed. The latest supplied
`native-guest(20261104-052959).log` reaches the TACT thread and reports
`pthread_mutex_lock(0x198)` from preferred return address `0x102a3aa3c`,
followed by `EXC_BAD_ACCESS`. The exact-image owner probes say `disabled`.
The launcher's printed SHA-256 is its saved app record, not a fresh source-file
hash. Thus that line cannot establish why the old probe gate failed.
The available `Tact(5).log` patch-index failure is about 81 minutes earlier
than this clean launch; it cannot be time-correlated with the latest mutex
fault. That launch's pre-fault native log contains an unimplemented
`NSPasteboard generalPasteboard` call and a failed `libmsquic.lttng` load, but
no evidence connects either to TACT construction. Its observed file mappings
all succeeded. No causal compatibility failure has been established.

This branch adds **observation**, not a startup repair. It does not write game
files, modify the WoW executable, suppress the fault, change locks, or bypass
integrity validation. The sideload identifier remains `local.tolkara.app`.

## Object and retrieval contract

The active 70755 BuildConfig carries the `patch-index` manifest as C-Key
`f5dac064c0740aa65482c7f66b79f449`, E-Key
`46c3d32d04ba185323ebea70f24ce282`, and decoded/encoded sizes
`40865 35927`. This is a BLTE **data object**. The public
`/tpr/wow/data/46/c3/<E-Key>` GET previously returned 200 and 35,927 encoded
bytes, with verified E-Key and decoded C-Key. The guessed
`/tpr/wow/patch/46/c3/<E-Key>.index` returned 403 to both HEAD and GET.
That 403 does not describe a guest request or show that the actual data object
is inaccessible.

The existing HTTP/1 observer now follows an exact target request through
request, response, bounded entity data, completion, and transport/error paths.
It records the actual guest method, allowlisted URL/path, status, native error
code and `errno`. User info, unrecognized hosts and paths, query and fragment
values, headers, and body bytes stay out of text logs. A GET 200 with identity
HTTP content encoding and complete framing can feed at most 35,927 bytes to
the independent object verifier. It reuses Wolkara's BLTE/chunk verifier and
decoder, then checks both declared hashes and decoded length. The output says
`source=guest-http-observer` and `guest-decoder=unobserved`: a successful
observer check does **not** mean WoW accepted or used the result. Short bodies,
wrong status/method, conflicting framing, HTTP content encoding, and native
errors have explicit outcomes. Error or cancellation cannot turn a truncated
close-delimited body into success.
Sequential retries on one HTTP/1 connection remain observable past the eighth
target request; only eight simultaneous requests can be queued. Text reports
and target event logs have explicit limits. If the 64-entry transport registry
fills, the log says that later transports may be unobserved. A limit message
means silence after it cannot be interpreted as no request.

The read-only CASC observer opens existing indexes without creating a missing
directory or verification receipt. CASC indexes contain only a **nine-byte
key prefix**. A hit is reported as a candidate until its 30-byte envelope,
the full encoded object and both hashes have been checked. The observer uses
bounded `pread` snapshots, compares file identity/stamps before and after,
and never moves the guest's file offset. Guest `stat`, `open`, `fopen`,
`read`, `pread`, `fread`, mapping and close observations are associated with
known key names or the confirmed segment identity; mapping overlap does not
prove that code consumed a mapped byte. A local verified candidate and an
actual guest cache hit are separate observations.

The metadata route enables retrieval tracing for an External JIT guest under
the Forever app bundle with an active local 70755 row, even if the exact-image
owner gate fails. The owner gate independently streams and hashes the source
executable and reports open, read, file-change or hash mismatch reasons.
Automatic tracing records structured TACT/cache and transport information;
generic directory entries, file names and environment values require the
explicit `--trace-guest` option. Only the CDN hosts observed for this
investigation and the established `level3.blizzard.com` variant are printed
verbatim; unfamiliar authorities are redacted, even if their suffix resembles
a Blizzard domain. URL user info, query and fragment values remain redacted.
Only an exact SHA-256 match to
`29b5e106f5ff89a91b7e1bec0d475dc8b31fb684f34217fff571d8a0888519d8`
may enable fixed 70755 owner addresses. Even then, the current post-unpack
writable code alias must match the 70755 ARM64 frame, owner-load and thunk
contract before saved-register or field reads. The startup sampler requires
the same live contract and checks independent object sentinels before each
read-only sample. No 70532 offset is used for this gate.
A sampled signature match is labelled a candidate. At the fault, its address
is compared with the root read from the crashing stack; a different address
cannot explain that root's lifetime. The validated instruction windows do
not prove that the nearby `owner+0x10` and `+0x700` loads feed the later call
at `0x102a0cc88`, so the field observation is not yet a causal chain.

Review also found logging wrappers that could overwrite the guest's `errno`
after directory or socket calls. They now restore the native result's `errno`.
The `getsockopt` logger reads `SO_ERROR` only after a successful call, avoiding
an observer dereference on a kernel-reported failure. These are compatibility
layer safety corrections, not an established repair for the TACT startup fault.

## What remains unknown

There is no device run of this branch yet. The supplied clean-launch log
cannot show the actual patch-index URL/method/status, whether WoW read a
verified local copy, or why the `+0x700` field is null. A bounded sampler can
miss a short-lived value or an owner outside the observed address bands. The
observer does not see HTTP/2 frames, private host-framework networking, or
statically linked OpenSSL plaintext; silence in these hooks is not proof that
no request happened. Local snapshots are independent checks of stored bytes,
not instrumentation of WoW's internal decoder. No compatibility-layer cause
of the null field has yet been demonstrated, so no startup fix is claimed.

The next device run should preserve the installed app and Documents container,
use the existing External JIT and StikDebug setup, and export the new native,
TACT and crash logs privately. Correlate `tact-cache`, `tact-http`,
`tact-object`, `tact-owner` and `tact-lifetime` entries by time and request.
If a specific Wolkara API failure precedes the missing field, reproduce its
contract in a focused test before changing that API.

## Build and regression evidence

The debug IPA build passed in GitHub Actions for commit `c76117c`; the focused
HTTP, object, cache, metadata and owner tests passed there. A later regression
job on that commit ran the full suite and failed only the same three Local
Signing assertions reproduced from the pinned unchanged base: `test_macos_dlopen`,
`test_macos_executable_runs`, and `test_matches_codesign_byte_for_byte`.
Neither result is a 70755 device launch. The follow-up observer safety and
retry changes still require a new IPA build.
