# The Matter framework, iOS 12 to 26, on iOS 6

The 24 647 rows of the SDK 26.2 surface of the framework Matter are carried by building connectedhomeip's own Darwin
framework for the port's release: `charon@matter` runs that project's GN build of `libCHIP.a` with the port's
toolchain, then compiles the framework's hundred Objective-C++ sources over it and links `libMatterBackports.dylib`.
Nothing here is re-typed; the classes are the Matter SDK's classes, and their behaviour is connectedhomeip's.

## The surface, and what the host's own framework says about it

Measured against macOS's own `Matter.framework` (`tools/matter-host-diff.lua`, the corpus's 24 647 rows against the
exports of the host's binary, which is in its dyld shared cache and was written out with `dyld.extract`):

| the host's framework carries | of the SDK 26.2 surface |
| --- | --- |
| 985 classes | 985 classes |
| 8 functions | 8 functions |
| 41 constants | 6531 constants |

Every class and every function of the SDK 26.2 surface is in the framework this machine's own macOS carries, so the
port's target is the framework rather than the surface, and a build of connectedhomeip's framework is a build of that
surface. The constants are not comparable this way and are not a difference: the Matter framework's constants are
header-declared enumerations, which live in the importing program and are not symbols the library exports.

**What this differential does not cover, stated plainly:** the 14 014 methods, the 2651 properties, the 442 enum types
and the 16 protocols of the surface. `objc.binary_inventory` finds no classes in the binary `dyld.extract` writes out
of the host's cache - it finds all three classes of a library built on this machine from source - so the host's
*selectors* cannot be read here, and a per-method host comparison is not something this run measured. It is the
emulator call test that answers for the members: every method this library carries is called on the emulator at 6.1.3
and must not crash. The export-level result above is what was measured, and it is what this file claims.

## What the port's release does not have, and what the build does about it

- **Signposts.** The framework's device browser, `MTRDeviceConnectivityMonitor.mm`, watches a peer's reachability
  through `nw_connection_*` of Network.framework (iOS 12) and the Darwin platform behind it uses the `os_signpost_*`
  family of libsystem (iOS 12). A release below 12 has neither. Network's connection is `libNetworkBackports.dylib`
  (`apple-backports`, `facts/Network/NWConnection.md`): a real datagram socket, the path reported by the path monitor
  the Foundation library already carries, and viability that means the kernel has a route to the address and the
  device's own reachability says the path is satisfied. The signposts are `charon@apple-compat`'s: the system's own
  where a release has them, and here the header's answer for signposts that are turned off, with `os_signpost_enabled`
  false so the emit macros skip at their own test.
- **The SDK's own libc++.** `usr/include/assert.h` reaches the SDK's libc++ of iOS 6, whose headers this compiler does
  not understand. `-nostdinc++` with the port's `charon@libcxx` is the spelling.
- **64-bit atomics on 32-bit ARM.** `ClockBase::mLastTimestamp` is taken and replaced with 64-bit `__atomic_*`
  operations, and clang gives `uint64_t` four bytes of alignment on `armv7-apple-ios` - measured:
  `sizeof(struct { char c; uint64_t v; })` is 12 there, 16 on arm64. A doubleword atomic on ARM has to be eight-byte
  aligned to be defined at all, so the member is aligned (`patches/clock-alignment.patch`) rather than the warning
  turned off.
- **No Xcode, no pigweed.** GN's own `build/toolchain/custom` takes `target_cc`, `target_cxx` and `target_ar`, which
  bypasses `BUILDCONFIG.gn`'s os/cpu selection entirely; the compiler, the archiver and the flags are the toolchain's
  own, the same values `modules/apple/cmake.lua` derives for a CMake build. `//build_overrides/pigweed_environment.gni`
  is a file upstream's bootstrap step writes and its `.gitignore` lists; the install step writes it, empty of
  declarations, which is what it comes to for a build with no pigweed environment.

## Not carried, and why

- The framework's own use of Network is its connection, and that is carried. The rest of Network - listeners, browsers,
  groups, the protocol options, the connection's data calls - is not, and `facts/Network/NWConnection.md` names the
  two honest gaps.
- The framework's XPC surface (`MTRDeviceController+XPC`, `MTRDeviceOverXPC`) is carried as the framework writes it,
  over the release's own XPC, which iOS 6.1.3 has in the form it needs. Whether every XPC service of the current
  framework answers on it is what the emulator call test has yet to say.
