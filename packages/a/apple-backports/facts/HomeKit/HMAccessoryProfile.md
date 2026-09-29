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
