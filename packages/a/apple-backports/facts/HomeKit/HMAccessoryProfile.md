# HMAccessoryProfile and HMCameraProfile

Two classes of **10.0**, in `HMAccessoryProfile10_0.m`: what an accessory publishes about itself, and the
profile of its camera.

## What the header declares, and what the port answers

`HMAccessoryProfile.h:19-20` marks the class
`API_AVAILABLE(ios(10.0), watchos(3.0), tvos(10.0), macCatalyst(14.0)) API_UNAVAILABLE(macos)`, and
declares three properties, **none of them nullable**:

| member | line | type | attributes |
|---|---|---|---|
| `uniqueIdentifier` | 27 | `NSUUID * _Nonnull` | readonly, copy, nonatomic |
| `services` | 32 | `NSArray<HMService *> * _Nonnull` | readonly, nonatomic |
| `accessory` | 37 | `HMAccessory * _Nullable` | readonly, nonatomic, **weak** |

`HMCameraProfile.h:25-26` subclasses it and adds four, **all nullable** — `streamControl` (33),
`snapshotControl` (38), `settingsControl` (43), `speakerControl` (48), each
`readonly, nonatomic, strong`. The difference in nullability between the two sets is the properties' own:
a profile always has an identity, a service list and an accessory-or-nil, while a camera publishes the
controls it has and says of the rest by answering nil.

The four controls are answered nil, and that is the answer rather than a stand-in: this library carries no
camera control class, and nil is what the header's own nullability allows an accessory that has published
nothing to say.

## How these rows are checked, and what each check is worth

**`tests/backports/host/homekit/ast_check.py` — the contract, and it runs.** It compiles the port's source
for `arm64-apple-ios12.0` against the 26.2 SDK and reads clang's AST. One dump carries both sides: the
header's declarations arrive through the port's own import and are tagged with the SDK file they came from,
and the port's are not. For every member above it compares the **type including nullability** and the
**attributes**, and each comparison prints the header line it came from. A hand-written accessor counts as
the port declaring the member, because this library writes its accessors out rather than redeclaring the
properties — requiring a property redeclaration would fail a correct port and teach the check nothing.

It carries a **control**: a scratch copy of the port's file with `streamControl`'s `nonatomic` changed to
`atomic` must be caught, and the run names what it caught. A check that cannot fail is not a check, so a
control that is *not* caught fails the run.

**`tests/backports/host/homekit/oracle.py` — structural, and weaker than it looks.** It counts selector
names in the 12.0 and 16.0 arm64 caches with a boundary after the name, and counts a positive control
(`HMAccessory`, which the held caches are measured to carry: 1259 at 12.0, 383 at 16.0) and a negative one
(a name this port invents: 0 in both). A wrong control fails the run.

Those counts are **global, not per class**: a cache holds one copy of a selector name, shared by every
class that uses it, so a count says the release spells the name, **not** that the class a row names has it,
and a short name like `home` is also a token inside many other identifiers. Answering per class needs the
release's own method list, which is the runtime half.

## What is not checked here, and the standing limit

The **runtime half** — whether the library answers what the header declares — is not checked by any of this,
and there is no way to check it on this machine: no `HomeKit.framework` exists in any macOS SDK, and the
SDK's own HomeKit types are marked `API_UNAVAILABLE(macos)`, so nothing of the model compiles for this host
at all. `xcrun simctl list runtimes` is empty, so there is no simulator either. The native fix is the
armv7 emulator, which is a heavy job to run when a slot is free; the registry rows' `source` and
`coordination/crutches.md` both say so. The crutch names it as the native fix.

## The `-init` and `+new` of thirty HomeKit classes, read out of a real release's own metadata

This host has no HomeKit binary at all - `/System/Library/Frameworks/HomeKit.framework` holds only a
`PlugIns` directory and there is no simulator - so the oracle for HomeKit is the release's own metadata,
read with the repository's own `tools/corpus/objc-inventory.lua` over the **arm64e cache of iOS 16.0**,
which is the newest held cache that still exports HomeKit's public classes (`_OBJC_CLASS_$_HMHome` is in
it; the cache of 18.0 exports none of them). It is a real release's own class list, which answers the
corpus row's question - is the selector in the class's own method list - and not the other one, what a
caller reaches at run time.

Thirty of this package's classes carry such a row today, and the cache splits them twenty and ten.

| what iOS 16.0's own class carries | classes | what the port does |
| --- | --- | --- |
| neither selector | 20 | carries neither; NSObject's pair answers, which is what the framework's own class answers |
| `-init` only | 10 | **undecided** - see below |

The ten are `HMAccessControl`, `HMAction`, `HMActionSet`, `HMHome`, `HMHomeManager`, `HMRoom`,
`HMServiceGroup`, `HMTimerTrigger`, `HMUser` and `HMZone`. Their ten rows stay `missing` and the decision
is not this page's: the measurement says Apple's class implements `-init` and says nothing about what it
returns, and there is nothing on this machine that can say more - no host framework, no simulator, and a
dyld cache carries method lists rather than answers. What the table
(`tests/backports/host/unavailable-init/expectations.tsv`) can hold for such a class is already there: an
`oracle` column naming where the answer came from, and `port-init`/`port-new` read off `own-init` and
`own-new`. When the answer is known, a row is one line.

**Two of the twenty were not true when this was measured**, and both are fixed:
`HMCharacteristicWriteAction` defined an `-init` that only forwarded to NSObject's, and `HMEvent` defined
one that invented a fresh UUID for the event - a value no framework produces, since an event's
identifier is the framework's and one made through `-init` has none. Nothing in the tree called either, and
neither definition matches Apple's class; both are gone, and their rows say why.

The rule the port follows, from the coordinator's answer of 2026-10-03: where Apple's own class carries a
selector the port carries it with the measured body; where Apple's own class does not, the port does not
either, because a definition would change what the class is and answer the caller exactly what NSObject's
already answers.

## The ten `-init` IMPs are out of the cache, and what the first of them does

The ten rows above are decided by the code, not by the header, and the code is in the cache.
`apple.objc.method_imps` (added for this, commit b9089f454, held by the coordinator until the commit that
uses it lands) reads, in one pass over the arm64e cache of iOS 16.0, every method the ten classes define
themselves with the address and 512 bytes at it: 1060 methods over the ten classes, written to
`charon/.agent-work/worktrees/v-health/.agent-work/runs/cachewalk/hk-init-imp.out`. The addresses are the
cache's own UNSLID addresses, so a page-relative `adrp` inside a body resolves the same way whatever the
slide. A pass costs minutes - 157s measured on the cache of iOS 18.0, 525s on 16.0 - which is why the
reader takes the whole set of names at once.

**How to read those bytes.** A wrapper Mach-O is not needed and does not work: a hand-built one is called
malformed by llvm-objdump (measured, `offset field plus size field of section 0 in LC_SEGMENT_64 extends
past the end of the file`). What works is assembling them into an object file with clang and running
llvm-objdump over that. The first body read that way: **`-[HMZone init]` calls one function and returns
nil** - not a raise, and not a constructed object. Which function it calls is the next measurement, and
the answer for the row follows from it: a nil-returning `-init` is a third shape, neither the SensorKit
raise nor the HealthKit raise nor the NSObject forward, and the port has to match whichever it is.

Three traps in the reader, measured here and not to be paid for twice:

1. this tree's lua does not parse the `%` operator and has no `pcall` and no `os.args`; use
   `string.format` and `function main(arg, ...)`;
2. `method_list(read, address, names)` takes a collection and indexes it, while `method_entries(read,
   address, each)` is the one that yields `(name, imp)`; passing a function to the first is
   `attempt to index a function value (local 'names')`;
3. `method_entries` is a file-local defined near the end of `objc.lua`, so a function that uses it has to
   be defined after it.
