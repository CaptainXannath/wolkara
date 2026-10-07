# Sharing Wolkara

Assessment: 2026-10-07. Wolkara is a WoW-focused fork of Tolkara. Changing its
name, home screen or distribution channel does not change iOS code-execution
requirements. The public fork is distributed as source for personal Xcode builds. No tested
public Wolkara IPA or notarized build is provided. See [Getting started](GETTING_STARTED.md)
and the [fresh-install checklist](FRESH_INSTALL_TEST.md).

## Closest practical goal: open Xcode and Run

This is a feasible packaging/onboarding goal for users with a Mac and suitable
development signing, not the current first-install experience. The current
guide still requires XcodeGen, personal values in `local.env` and a separate
`tools/enroll.sh` after installation. WoW/Battle.net on the Mac is not required.

The next implementation should prioritize this source-build route:

1. Ship a reproducibly generated, sanitized Xcode project or a double-click
   setup assistant. Keep XcodeGen for maintainers. Present one Wolkara scheme
   with debugger attachment and Metal validation already disabled.
2. Select the user's team and connected phone once. Derive unique app/extension
   identifiers and the Keychain group, then retain them for upgrades. Check
   Xcode components, Python and signing capabilities before a long build.
3. Add a local Mac setup helper that waits until installation is complete and
   guides the existing USB enrollment. A normal build phase is too early for
   first-install enrollment. Reuse valid enrollment; recover the exact stored
   reference after reinstall when possible. Never enroll on every Run or attach
   a debugger to a running game. Show setup completion in Wolkara before Play.
4. Guide the remaining system prompts: device trust, Developer Mode and local
   tunnel consent. These remain user actions; they cannot be silently accepted.
5. Validate the entire flow on another user's signing identity and a clean
   device, including a full download, patch, reboot, mobile-data startup and a
   rebuild that preserves game data.

The resulting target experience is **open project → select team and phone →
Run → approve first-time prompts → choose/download an edition → Play**. This
helper has not been implemented here. Making setup simpler also does not remove
the several-minute memory preparation required at each game launch.

[Apple documents Developer Mode and its confirmation/restart](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
The currently documented integrated build uses a paid developer membership;
free Personal Team is not a validated replacement for its tunnel and memory
capabilities. [Capabilities depend on membership](https://developer.apple.com/help/account/reference/supported-capabilities-ios/),
and [Apple's free-account provisioning expires after seven days](https://developer.apple.com/help/account/basics/about-your-developer-account).
A simpler project does not remove either signing requirements or expiry.

## Is the local VPN the only execution route?

For the **current integrated build with recorded iPhone gameplay**, keep it.
`authorization/Tunnel/LocalPacketProvider.m` routes only the private service
address, excludes the default route and sets no DNS override or remote server.
This is on-device access to the developer service, not a commercial VPN or
streaming connection. Cellular-only startup is still an unresolved acceptance
test; local routing alone does not prove it works under every network condition.

The engine has alternatives, but none is currently a verified simpler WoW route:

| Route | What replaces the integrated tunnel | Current limitation |
| --- | --- | --- |
| External JIT | An external enabler prepares executable memory | Still needs a suitable signing profile and setup; an enabler may itself require a local tunnel or computer. WoW on this iPhone is unvalidated in this mode. |
| Local signing | User-signed, per-executable page container | Current tools build it on a Mac. The documented WoW case needs final code pages that Tolkara cannot capture; every changed executable needs a new container. Not a working automatic-update replacement. |

See [the execution-mode implementation notes](BUILDING.md#4-set-up-your-execution-mode).
An ordinary App Store/TestFlight/PAL package does not replace development
authorization: [Apple DTS distinguishes development `get-task-allow` from distribution profiles](https://developer.apple.com/forums/thread/823069).
[AltStore PAL requires notarized distribution](https://faq.altstore.io/developers/distribute-with-altstore-pal).
The conclusion that these channels cannot run our current preparation path is
an engineering assessment of that dependency, not a claim that no different
future runtime could ever work.

## What is currently demonstrated

The existing personal setup uses Xcode signing, the integrated Developer service
target, Developer Mode and one-time device enrolment. Forever gameplay and
Mac-disconnected reboot/launch were reported on an iPhone 16 Pro Max. Those
reports do not prove cellular-only startup, the latest updater revision, or a
fresh install using another user's signing identity. See [COMPATIBILITY.md](../COMPATIBILITY.md).

The updater can check editions and install patches while open. A first full
real-game download is still unvalidated. The controls editor has simulator/signed-build coverage and user-confirmed
physical-game use. A separate clean-install run remains necessary.

Normal launches automatically use the route compiled into the app: Developer
service for the integrated target, External JIT for the diagnostics/sideload
target. The home does not offer Local signing or other startup alternatives.
Explicit development arguments retain those tools. Removing the picker does
not remove the route's preparation, enrolment or signing requirements.

## Practical distribution choices

Expanded research, 2026-10-06: SideStore is one delivery option, not a required
dependency. The key distinction is development signing versus distribution
signing, independently of the installer's name or Debug/Release build setting.
[Apple DTS explains](https://developer.apple.com/forums/thread/823069) that
development profiles permit `get-task-allow`; distribution profiles, including
Ad Hoc, do not. Both our current Developer service preparation and External JIT
need access to the host process before guest entry. A successfully installed IPA
is therefore not evidence that its signing method permits WoW execution.

| Route | Installation experience | Wolkara status |
| --- | --- | --- |
| Personal Xcode build | Mac, own developer signing, Developer Mode, initial enrolment | Closest to the setup with recorded gameplay; still a developer workflow. |
| Small beta, development-signed for registered devices | Maintainer builds/signs; a desktop helper could install and enrol the device without asking testers to use Xcode | Promising first pilot using the existing integrated route; helper and clean-device flow not yet built/tested. Device-registration and certificate limits apply. |
| iLoader or Sideloadly, direct IPA | Desktop installer, USB, user's Apple Account; no compilation by the user | Good general sideloading candidates. Need actual re-signing/entitlement and execution tests; generic IPA currently selects unvalidated External JIT. |
| SideStore / AltStore Classic source | Add a source; supports launcher updates and signature refresh through the user's setup | Useful especially for users already using them, not the only recommended install method. |
| Paid development-certificate service / Feather | Device registration and signing through a service or imported certificate, potentially on-device | Worth a pilot, not a confirmed solution. Require a development profile, correct memory/tunnel/keychain entitlements and initial authorization; a distribution-only certificate will not suffice. |
| TestFlight / App Store | Familiar install and update experience; TestFlight supports public invitation links | Current preparation relies on development-only debugging permission. These channels do not provide a working native WoW route with the current design. |
| AltStore PAL / official web distribution | Marketplace/source or authorized website install | Notarization and distribution requirements remain; no demonstrated compatible native-execution path. |
| LiveContainer | Import Wolkara into another app | Its lack of guest extension support conflicts with our integrated tunnel. JIT-less hosting of an iOS wrapper does not authorize unsigned Mac game pages; External JIT would require separate investigation. |
| TrollStore | Permanent IPA installation on its supported old iOS versions | Its published support excludes the modern iPhone/iOS setup tested here. Not a general-user route. |

[iLoader](https://iloader.app/) supports arbitrary IPAs on macOS, Windows and
Linux, plus pairing-file setup for supported apps. That does not establish
compatibility with our custom enrolment format. Its announced browser installer
is beta and its iOS 27 wireless pairing is work in progress; neither should be
advertised as a proven phone-only Wolkara setup.

[Sideloadly](https://sideloadly.io/faq) supports automatic refresh when a computer
can reach the phone by USB or Wi-Fi. Its documentation gives seven days for free
signing and up to a year for paid developer signing. Signature refresh and game
content updates are separate operations.

For a small development-signed pilot, Apple permits registration of up to
[100 devices per product family per membership year](https://developer.apple.com/help/account/devices/devices-overview/).
This is not an unlimited Reddit distribution method. Testers would still need
Developer Mode, device trust and enrolment; our signing private key stays with
the maintainer and device pairing secrets stay local. A Windows version of the
helper would need to replace the current Mac/Xcode-specific enrolment tooling.

[Signulous](https://www.signulous.com/) now advertises development and
distribution certificates and JIT support. These are vendor claims, not a
Wolkara test or a guarantee against revocation. Check the resulting profiles
and all required entitlements before recommending purchase.
[Feather](https://github.com/claration/feather) is an on-device certificate-based
installer with source support; it is not an independent grant of those permissions.

[TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
offers up to 10,000 external testers, reviewed builds and 90-day build validity.
The present blocker is execution permission as well as distribution review.
[Official EU web distribution](https://developer.apple.com/support/web-distribution-eu/)
requires authorization and notarization; it is not a plain IPA download link.
Enterprise distribution is for an organization's internal apps/employees, not
[a public Reddit release](https://developer.apple.com/programs/enterprise/).

[LiveContainer's documented limits](https://github.com/LiveContainer/LiveContainer#limitations)
include guest entitlements not applying to the host and guest extensions not
being supported. Its separate JIT support needs appropriate setup on newer iOS.
[TrollStore](https://github.com/opa334/TrollStore) lists iOS 14.0 beta 2–16.6.1,
16.7 RC and 17.0, excluding 17.0.1 and later.

[SideStore's prerequisites](https://docs.sidestore.io/docs/installation/prerequisites)
include a computer for initial installation, an Apple Account and connected
Wi-Fi. Its LocalDevVPN must be active for app installation, updates and refresh.
These are store operations, distinct from downloading WoW content inside Wolkara.

[AltStore Classic's remote-server documentation](https://faq.altstore.io/altstore-classic/remote-altservers)
also describes installing/refreshing without the computer after pairing, using
LocalDevVPN and a connected Wi-Fi network. This does not establish cellular-only
Wolkara launch or solve its executable-memory preparation.

An External JIT build needs an enabler. [StikDebug](https://github.com/StikDebug/StikDebug)
is a candidate: its own instructions require pairing/setup and describe limited
app compatibility on newer iOS releases. We have not tested that combination.
Our loader must still obtain executable memory and confirm debugger detachment
before entering any game code.

[PAL distribution](https://faq.altstore.io/developers/distribute-with-altstore-pal)
requires Apple notarization, marketplace processing and hosting the Alternative
Distribution Package before publishing a source. Our engineering conclusion is
that listing Wolkara there cannot itself authorize execution of downloaded Mac
code. No PAL-compatible execution permission or successful test is claimed.

## Before recommending it to nontechnical users

1. Validate one clean installation from start to finish on a separate device:
   signing, first game download, update, login, restart, input and recovery.
2. For the IPA route, validate External JIT and memory capacity with the actual
   signing tier. Free signing drops increased-memory and extended-address-space
   entitlements in the current packaging workflow; compilation is not proof
   that the full client will fit.
3. Validate login in the distributable build. The public release workflow sets
   `TOLKARA_SYSTEM_ROOTS=NO` explicitly to exclude roots exported from macOS;
   running `tools/package_ipa.sh` alone defaults to YES. Public packaging must
   use NO, unlike the personal build tested here. Provide a redistributable
   trust-store solution if needed; never
   disable TLS validation or bundle private signing/enrolment material.
4. Confirm cold startup using mobile data, with no nearby Mac or Wi-Fi. Current
   documentation records a failure and an unvalidated recovery sequence.
5. Publish only our app/runtime and original assets, retaining MIT/third-party
   notices and the independent-project attribution. Never include game files,
   account data, pairing records, personal identifiers, captures or certificates
   exported from macOS. Users obtain authorized game content themselves.

## Suggested Reddit rollout

For the current source release, prioritize the simplified Xcode flow above
with a few independent testers. This reuses the execution route with recorded
gameplay and lets each builder retain their own signing identity. A later
development-signed pilot with a desktop installer could avoid compilation by
testers: connect phone, accept the prompts, press Install, complete local
enrolment, then choose/download an edition. Neither proposed assistant is
implemented or validated yet.

For broader distribution, compare direct iLoader/Sideloadly installation against
a paid development-certificate route using the same clean-device acceptance
tests. Existing SideStore/AltStore users can use a compatible source as an
additional convenience. Do not tie the app architecture to one installer.

The Reddit post can then link a short demo and one installation landing page
that recommends a route based on available computer, signing choice and iOS
version. Prefer a single validated default, with alternatives clearly labeled.
No paid account, service, certificate or public distribution was set up here.

Describe it as a community experiment until another person can complete the
clean-device flow. Do not advertise one-tap installation, PAL availability,
cellular-only startup, or account safety on the strength of a local build or
simulator test. Updating Wolkara through a source and updating WoW from its CDN
are two different operations.
