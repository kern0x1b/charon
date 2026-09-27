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

## The state of the build, measured

- **All 123 sources compile for `armv7-apple-ios6.1.3`**: the 100 `MTR*` Objective-C++ of the framework and the 23
  app-layer C++ files its own Xcode target carries, read out of that target's Sources phase and not guessed. The
  objects are in the package's own source tree; `tools/matter-framework.sh` builds and links them there in minutes
  instead of a whole package resolve.
- **The link fails in the linker, not in Matter**: charon's `ld64 956.6` aborts with
  `Assertion failed: (it != _dylibToOrdinal.end()), function dylibToOrdinal, file OutputFile.cpp, line 5214` while
  encoding the symbol table. Measured, in order:

  | link | result |
  | --- | --- |
  | `libCHIP.a` alone, or with libc++, or with either backport, or with all three | links |
  | the 123 objects, or any one group of them (the 100 MTR, the 6 codegen data model, the 17 server layer), or two groups | links |
  | the 123 objects **and** `libCHIP.a` **and** libc++ **and** the two backports | asserts |

  It is not the C++ runtime's install name: the packaged libcxx (`/usr/lib/charon/org.charon.libcxx-550adb3c/…`,
  absolute install names, a Debian package) asserts, the `@rpath` one asserts, staged copies rewritten with
  `install_name_tool -id` to absolute paths assert, and `-L -l` and full paths and with and without `-rpath` all assert.
  It is not one object: **dropping any one of at least a dozen different objects makes it link** - the six codegen data
  model objects, `MTRAsyncWorkQueue.mm`, `MTRCluster.mm`, `MTRDevice.mm`,
  `MTRDeviceControllerDataStore.mm`, `MTRDeviceControllerXPCConnection.mm`, `MTROperationalCredentialsDelegate.mm`
  among them - which is the signature of a defect in the linker rather than of any symbol in the input. `ld64` writes a
  snapshot of the run next to the output on each abort, which is the artefact to read next.

## Behaviour, held to the host

`tests/backports/host/matter/pure.m` is one program with no device on the other end, written so it compiles against
the host's own `Matter.framework` and against `libMatterBackports.dylib` alike, printing one `name<TAB>answer` per
line; `tools/matter-pure-diff.lua` reads the two files and names every line that differs. What it covers is the part of
the three areas a program meets first that needs no device: the setup payload built from a passcode and a discriminator
and read back, the manual-entry parser over the code the framework itself wrote out of that payload, the onboarding
parser over its base38 form, a payload and a code that are not ones, the commissioning parameters' own defaults, and
`MTRDeviceControllerStorageClasses()`. 38 questions, and the host answers all 38.

What that run measured, and what the port has to reproduce:

- `manualEntryCode` for the standard payload of passcode 20202021 and discriminator 3840 is **34970112332** - the
  framework's own encoder does not put the discriminator there: parsing that code back gives discriminator **15**, and
  `hasShortDiscriminator` YES. So the eleven digits are a code whose discriminator is not the one the payload names,
  and the round trip is not an identity. This is the kind of answer a differential exists for.
- `+isValidSetupPasscode:` answers **true for 1234** as well as for 20202021, so it is not a length check.
- The onboarding payload `MT:Y.K90SO527JA0648G00` is vendorID 65521, productID **32768**, passcode 20202021 and
  discriminator **3839**, not the 32770 and 3840 a reading of the documentation suggests; `initWithPayload:` on a
  string that is not a payload answers nil.
- A manual code of one digit and a code that is not a payload both answer `MTRErrorDomain error 4`, the failure
  answer and not a crash - the half of a differential that only runs would never see.
- The controller names eight storage classes, of which the framework's own are the first three.

**What the host cannot be held for, and why.** The name-to-id and id-to-name mappings of the iOS surface
(`MTRClusterNameForID`, `MTRAttributeNameForID`, `MTRRequestCommandNameForID`, `MTRResponseCommandNameForID`,
`MTREventNameForID`) are **not declared by the host's public headers at all** - macOS's Matter.framework ships 62 public
headers and none of them declares a name mapping - so there is no host answer to compare a port answer with, and
saying the host agrees would be a fiction. `MTRBaseDevice`'s read, write and subscribe and `MTRDeviceController`'s
commission, pair and subscribe need a device and a daemon, and this host has neither. Those are covered by the
emulator call test, which calls every method the port's library carries and requires that none of them crashes - not
by a differential, because there is nothing on the other side to be differential against.

## The framework's own availability switches

The framework's headers mark a member with the iOS release Matter shipped it in, and a member of a *newer* Matter
release is worse than marked: `MTRDefines.h:75` makes `MTR_PROVISIONALLY_AVAILABLE` expand to `NS_UNAVAILABLE`
unless `MTR_ENABLE_PROVISIONAL` is set. The first build of the wrapper therefore refused `MTRDataTypeSemanticTagStruct`
and its `mfgCode`, `MTRAttributePath`'s `label` and `auxiliaryType`, its `readPathsSupported` and
`simultaneousWritesSupported` - and as *explicitly* unavailable, which is a hard error, not a warning any `-Wno-` flag
turns off.

The framework's own build says what to do, in `src/darwin/Framework/Configs/Project.xcconfig:4`:

    GCC_PREPROCESSOR_DEFINITIONS = $(inherited) MTR_NO_AVAILABILITY=1 MTR_ENABLE_PROVISIONAL=1 MTR_ENABLE_UNSTABLE_API=1

All three are now the recipe's flags, which is the whole answer: the framework compiles itself with the availability
marks off and with the provisional and unstable API on, because it is the thing that ships them. The same project
compiles its own availability tests (`MTRAvailabilityTests.m`) with `-UMTR_NO_AVAILABILITY
-Wno-unguarded-availability-new`, so the marks are off for the framework and on exactly where they are the thing
under test. That is upstream's own arrangement, read from its own build, and this recipe adds no judgement of its own.

**What my first attempt got wrong, since it is the kind of thing worth recording:** I reached for
`-Wno-unguarded-availability-new` and reasoned that the link would still catch an SDK call the release lacks. It does
catch that, and it was still the wrong fix: the marks in question are `NS_UNAVAILABLE`, which is a hard error and not
the diagnostic that flag names, so the build failed with the very same six diagnostics. The right answer was three lines
of the framework's own xcconfig, which I had not read yet.

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
