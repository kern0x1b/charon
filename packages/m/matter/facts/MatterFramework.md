# The Matter framework, iOS 12 to 26, on iOS 6

The 24 647 rows of the SDK 26.2 surface of the framework Matter are carried by building connectedhomeip's own Darwin
framework for the port's release: `charon@matter` runs that project's GN build of `libCHIP.a` with the port's
toolchain, then compiles the framework's hundred Objective-C++ sources over it and links `libMatterBackports.dylib`.
Nothing here is re-typed; the classes are the Matter SDK's classes, and their behaviour is connectedhomeip's.

## The surface, and what the host's own framework says about it

Measured with `tools/matter-host-diff.lua`, which reads the host's half from a **live process that loaded the
framework** (`tests/backports/host/matter/run.sh`: `objc_copyClassList`, `class_copyMethodList`,
`class_copyPropertyList`, `class_copyProtocolList`, `protocol_copyMethodDescriptionList`, and the surface's function
rows asked of the loaded image by `dlsym`) and the port's half from `libMatterBackports.dylib` with the same modules
the gate's check reads a library with.

| the host's `Matter.framework` carries | of the SDK 26.2 surface |
| --- | --- |
| 985 classes | 985 classes |
| 13 184 methods | 14 014 methods |
| 2650 properties | 2651 properties |
| 11 protocols | 16 protocols |
| 8 functions | 8 functions |

Every class, every function, all but one property and 94% of the methods are in the framework this machine's own macOS
carries. So the port's target is the framework rather than the surface, and a build of connectedhomeip's framework is a
build of that surface. The 830 methods, 1 property and 5 protocols no host framework carries are named in
`.agent-work/host/matter-host-diff.tsv`: they are rows of an SDK release whose framework is older than the SDK, and
they are what the port's own library is compared against row by row.

**The two kinds the surface has and this comparison cannot have.** The 6531 constants are header-declared
enumerations, so they live in the importing program and are not symbols either library exports; the 442 enum types are
typedefs of the same kind, carried by the values the SDK names after them. Neither is a difference between the two
sides, and neither is counted as one.

**Why the host's half is a live process and not a file.** The host's framework is in its dyld shared cache and is not on
disk, and a binary written out of that cache with `dyld.extract` does not carry the Objective-C metadata in a form this
repository's reader can walk: `objc.binary_inventory` finds no classes in it, though it finds all three of a library
built here from source. The class and function counts could be had from its exports, which is where the first run of
this measurement came from; the members could not be had at all until the framework was loaded instead.

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
