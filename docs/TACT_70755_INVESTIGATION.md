# Forever 1.60.1.70755 startup investigation

Status: diagnostics corrected; **startup is not demonstrated fixed**. This
continues [PR #1](https://github.com/CaptainXannath/wolkara/pull/1), whose
70532 addresses and device experiments are historical evidence only. The
baseline for this increment is `fix/forever-ios-compat-diagnostics` at
`65b412d`. No WoW executable, integrity check, game settings or installed data
are changed by this increment.

## Evidence reviewed

The supplied `native-guest(20261104-042347).log`, `Tact(5).log` and
`2026-11-03_22.08.52_Crash_32250.txt` identify External JIT, build 70755 and
executable SHA-256
`29b5e106f5ff89a91b7e1bec0d475dc8b31fb684f34217fff571d8a0888519d8`.
The log reports all 13,305 initializers returning, followed by guest main.
All 1,402 archive indexes, 78 patch archive indexes, the file index and
patch-file index are locally present. Presence does not validate every byte.

The crash-time observation reads a null pointer through the saved caller's
`owner+0x10`, then `+0x700`. Mutex address `0x198` follows from the null
object plus `0x28` and `0x170`. The existing branch **returns EINVAL instead
of calling pthread** for this address. The later crash has return value
`x0=0x16` (EINVAL), `x21=0x28` and reads `x21+0x16c=0x194` at preferred PC
`0x102a3aa3c`. Thus the guard moves the fault; it does not repair the object.
This increment removes both near-null lock and unlock guards and preserves
errno around diagnostic observations. The real pthread functions run.

The owner sampler logs its start and first scan but never finds the owner in
this evidence. Only the crash-time null is established. It is unknown whether
the field was never set, was cleared or freed, or was published too late.
Returning from every static initializer does not establish successful TACT
object initialization in main.

The supplied run has SecureTransport, DNS and socket **bindings**, but no
SecureTransport operation, DNS resolution or connect trace. Those bindings
do not establish an HTTP attempt. Existing hooks do not cover every possible
network stack, so their silence does not prove no network request occurred.
Generic Security stubs are imported but have no invocation records. The
only generic-stub call recorded is `CGSSetDebugOptions`. Disk Arbitration
calls occur during crash reporting, after the invalid mutex guard. Neither
is evidence of the missing object's initialization failure. Local build
config and CASC index reads/mappings succeed in the recorded run; the
allocation-failure section is empty.

## Failed E-Key provenance and the misleading 403

Public metadata was checked on **2026-11-04 at 04:41 UTC**, anonymously:

- The [Forever versions table](https://us.version.battle.net/v2/products/wowf/versions)
  identifies 70755 with BuildConfig `9d9888f2d89a2dcc9eacc68a2d7cb3dc`.
- The [build configuration](https://level3.ssl.blizzard.com/tpr/wow/config/9d/98/9d9888f2d89a2dcc9eacc68a2d7cb3dc)
  is 59,606 bytes, with MD5 equal to its config key. Its `patch-index` field
  has content key `f5dac064c0740aa65482c7f66b79f449` and **encoded key
  `46c3d32d04ba185323ebea70f24ce282`**. `patch-index-size` is `40865 35927`.
  The separate `patch` field has key `549106111a026eda62977e47accd1876`.

This is a build-config **patch-index manifest**. It is distinct from the
CDN config's `patch-archives` and `patch-file-index` archive catalogs. Searching
only the CDN config therefore missed its origin.

| Anonymous diagnostic request | HEAD | GET | Validation |
| --- | --- | --- | --- |
| [Metadata-backed `/data/46/c3/46c3d32d04ba185323ebea70f24ce282`](https://level3.ssl.blizzard.com/tpr/wow/data/46/c3/46c3d32d04ba185323ebea70f24ce282) | 200 | 200 | 35,927 bytes; 36-byte BLTE header hashes to E-Key; decoded 40,865-byte payload hashes to C-Key |
| Assumed `/patch/46/c3/46c3d32d04ba185323ebea70f24ce282.index` | 403 | 403 | Different resource category; no valid object obtained |

The standalone 403 is explained by probing an unsupported resource path.
It is not a HEAD-only failure; GET on the same assumed path also fails. The
metadata-backed object exists and is accessible without credentials on this
host. HTTP 403 alone cannot distinguish the CDN's internal treatment of a
missing path from an access rule. These probes **do not capture WoW's actual
URL, method, authorization or response**. They cannot explain its TACT error
`Server: 4294967295 | Error (1): unknown failure` by themselves.

No game content from the probe is committed. The old guessed startup HEAD
requests are removed. Startup now inspects local, checksum-verified active
Build Key and CDN Key configs; it records manifest-key provenance separately
from archive-index presence. `tools/inspect_tact_metadata.py` provides a
read-only offline equivalent for exported metadata, with synthetic tests.

## Diagnostic corrections and coverage

- Actual HTTP observation is added at the transport calls identified in the
  import audit: HTTP/1 through guest socket calls and SecureTransport plaintext
  reads/writes. Request methods and permitted CDN URL/path components are
  logged with response status and transport error codes; headers, credentials,
  query values, fragments and response bodies are excluded. Limits bound
  connection state, line size and emitted observations. See the focused tests
  for malformed, fragmented and sensitive inputs. HTTP/2, statically linked
  OpenSSL TLS plaintext and calls made internally by host frameworks are not
  covered. Unsupported framing stops parsing rather than interpreting bodies
  as requests. No new device request capture is yet available.
- The 70755 field/frame/address probes require the exact SHA-256 above and
  External JIT. Other builds do not reuse those offsets. Code observations use
  the writable alias and checked kernel reads instead of dereferencing the
  executable view. The sampler revalidates the owner signature before each
  field observation and stops if it changes. Sampling is timing-sensitive,
  searches a limited address band and can miss initialization or short changes.
- `dlsym` returns original export addresses. The previous untyped tracing
  trampoline could change stack argument positions and also wrap a data
  export without knowing its type. This is a diagnostic compatibility defect;
  no wrapped calls occur in the supplied log, so it is not assigned as this
  startup failure's cause.

## Validation and the next device run

The debug IPA workflow runs focused diagnostic/metadata tests, builds the
External JIT IPA and checks that its default identifier remains
`local.tolkara.app`. A separate job runs the required
`tools/test_emulation.sh` sanitizer suite. Record the exact run URL and
commit in the pull request; a green build is not a device startup result.
Windows cannot run Xcode or the native Mac regression executables locally.

Install the resulting IPA through the existing sideloader with the same
installed signing identity and bundle identifier, preserving the app's
Documents container. Do not uninstall, delete/reinstall WoW, rerun index repair
or repeat the already completed root-certificate/BGDL experiments. Launch with
the existing StikDebug `universal.js` setup. No debugger is attached after
guest entry. Export the fresh native log, Tact log and crash report privately;
do not publish raw credentials, pairing records or signing material.

Correlate the actual request, its completion/error and owner field
observations in the new run. If no supported HTTP operation is observed,
first identify the actual transport or the compatibility failure preceding
transport setup. If a specific compatibility API fails, reproduce that API
contract with a synthetic test before correcting it. **There is not yet a
demonstrated Wolkara API failure causing this null field**, and no production
startup repair is claimed.
