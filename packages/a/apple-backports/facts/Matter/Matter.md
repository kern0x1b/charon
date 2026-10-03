# Matter

`Matter.framework` does not exist before iOS 16.4, so every release this package carries has no Matter
framework to shadow: a client that links one and asks a cluster a question reaches this port's class
instead. The clusters are therefore generated from the SDK's own headers rather than written by hand,
because a class has too many members for a hand transcription to be right and the header is the contract.

## What is carried

**1,067 objects, one class each, all emitted by `tools/matter-generate.py` from the SDK's own declarations.**
Two families, and both are read out of the headers rather than listed:

- **the 144 cluster objects** - 142 of the framework's 145 `MTRBaseCluster` classes from the declarations in
  `MTRBaseClusters.h`, plus the two classes they all sit on: `MTRGenericBaseCluster`, which SDK 16.4 does not
  declare, and `MTRCluster`, which it does. **Both bases are carried, not just the one the SDK lacks**: a
  declaration says a class exists at compile time, and the object is what makes it exist at runtime, and the
  release this family is carried into has no `Matter.framework` at all. Every one of the 142 cluster objects
  names `_OBJC_CLASS_$_MTRCluster` - measured over all 144 objects: of every symbol they leave open, those
  two (`MTRCluster`'s class and metaclass) are the only Matter ones - so without that object the library does
  not link: `Undefined symbols for architecture armv7`. 16.4's `MTRCluster.h` declares `-init` and `+new`
  `NS_UNAVAILABLE` and no member, so that is what its object carries: the class and nothing else. The other
  three are listed in `tests/backports/host/matter/excluded.txt` with a reason each. Every member a cluster
  declares - a read, a write, a subscribe, a command in every shape the header gives it, a cached read, the
  initialiser - has a body that answers without reaching a fabric: the value the caller set, or no value and
  the error the release documents for a cluster it cannot reach.

- **the 923 plain data classes** - every `@interface` in the SDK's Matter headers whose name carries
  `Params`, `Struct` or `Event`, holding 3,260 properties. They are the types the commands and the events name,
  and they were forward-declared and nothing more until now: a caller could not build one, which is what the
  `*Params` bullet under "What is owed" used to say. Nothing in this family reaches a fabric. A class holds
  what the caller put in it, hands back what it holds, and `-copyWithZone:` is written out over its own ivars
  so writing to the copy never reaches back into the original. 565 of the 923 carry `<NSCopying>` in their own
  protocol list and the rest inherit it from a superclass that does, so 863 of them get the copy; the 60 that
  do not are the event classes, and the host's own method list is what says so - `-copyWithZone:` is written
  for a class the MEASUREMENT gives one, which is `respondsToSelector:` read over the class's own methods and
  not the protocol list, because the protocol list is a declaration and this is a binary.

  **`-init` IS written, and it is not NSObject's.** Every class in this family except the ones whose header
  marks it `NS_UNAVAILABLE` gets an initialiser that stores what the host's initialiser stores: a NONNULL
  object member is the zero value of its own type and a nullable one is nil. Measured, by
  `tests/backports/host/matter/params-probe.m`:

      fresh  MTRGroupsClusterAddGroupParams  groupID               NSNumber(0)
      fresh  MTRGroupsClusterAddGroupParams  groupName             NSString()
      fresh  MTRGroupsClusterAddGroupParams  timedInvokeTimeoutMs  (nil)
      fresh  MTRTestClusterClusterSimpleStruct  d                  NSData(0)

  The three exceptions are the classes whose own header writes `- (instancetype)init NS_UNAVAILABLE`, and an
  `@implementation` that defines an unavailable method is the compiler's own error.

**Three declarations, because the SDK this library compiles against (16.4) does not have all of it.** Which
one applies is read, not chosen:

| the port writes | how many | why |
| --- | --- | --- |
| the whole `@interface`: superclass, protocols, every property | 538 | the library's SDK declares no class of that name, and an object that implements a class no `@interface` declares is `cannot find interface declaration for` |
| a class **extension** with only the properties a later SDK added | 72 | the library's SDK declares the class, so redeclaring it is `duplicate interface definition for class`; 26.2 adds properties to 313 of the classes it declares - `MTRReadParams` gains `minEventNumber` and `assumeUnknownAttributesReportable`, `MTRSubscribeParams` gains `minInterval` and `maxInterval` |
| a **category** with the properties the SDK declares in one | 17 | a category's property cannot be synthesized in the class's `@implementation`, and `MTRGroupsClusterAddGroupParams` carries the old `groupId` in a `(Deprecated)` category beside the `groupID` of its own `@interface` |

The 17 category properties are the SDK's own API - `MTRGroupsClusterAddGroupParams.groupId` is a corpus row at
16.1 - so they are carried, with their accessors written out by hand over storage in the port's own class
extension. Both alternatives are clang's own answer and both were measured: `@synthesize not allowed in a
category's implementation`, and `property declared in category 'Deprecated' cannot be implemented in class
implementation`. The accessors are written with the type the **library's** SDK declares, because Apple relaxed
a nullability between the two SDKs - `MTRDiagnosticLogsClusterRetrieveLogsResponseParams`' `content` and
`timeStamp` are `_Nonnull` in 16.4 and `_Nullable` in 26.2 - and the port does not redeclare the property, so
writing 26.2's spelling is `nullability specifier '_Nullable' conflicts with existing specifier '_Nonnull'`.

The class's own state is one table keyed by the attribute name and guarded by a lock, because armv7 has no
thread-local storage to rely on. A release with no Matter hardware has no node to read from, so the class
methods the header declares answer as Apple documents: no value, and an error.

## What is measured

    tools/matter-generate.py            run exit 0; invariant 0 in BOTH directions; 1067 of 1067 objects
                                        compile against SDK 16.4; every object names the class it
                                        implements, 1067 of 1067; `plain data classes written: 923, 3260
                                        properties; 0 named but not declared in the SDK`; `the SDK this
                                        library builds against declares 385 of them itself ... 72 of them as
                                        a class extension. For the other 538 the port declares the class,
                                        its superclass and every property.`
    tools/matter-registry.py            14948 rows (1067 class, 9446 method, 4435 property) over 1067 objects;
                                        every class an emitted object defines has a row: 1067 of 1067; 5236
                                        rows take the 16.0 fallback the header states nowhere - 376 class,
                                        3214 method, 1646 property - and all of them are listed in
                                        ios16.json.unannotated (6978 declarations)
    the ledger, coordination/corpus/ledger-2026-10-03/Matter.tsv
                                        2870 of the framework's 11675 `missing` rows are `implemented` by
                                        this family - 637 class, 2233 property - and all 2870 name a class
                                        this commit adds: 0 of them are owned by an object main already had
    the 1067 objects, armv7-apple-ios6.0, the package's own flags
                                        0 lines matching ` error: ` over all 1067, xargs -P 2
    coordination/work-2026-10-03/tools/relcheck.lua, BP_LIBRARY=MatterClusterBackports
                                        `compiled 1067 objects of MatterClusterBackports` then
                                        `check_releases: every object of MatterClusterBackports holds API of
                                        one release` - measured from the held caches' EXPORT TRIE, not from
                                        API_AVAILABLE
    nm -gU over those 1067 objects     1067 distinct _OBJC_CLASS_$_ symbols, one per object, and every one
                                        is either Charon-prefixed or a class the registry carries as
                                        `implemented`: 0 that are neither. The only other exported symbol is
                                        _OBJC_LABEL_PROTOCOL_$_NSCopying, from the NSCopying conformance the
                                        plain data classes carry, which internal_symbol() does not exempt -
                                        check_releases measured it as placed anyway
    coordination/build-gate.lua 6.1.3   exit 0; `build: 6.1.3 compiled 3890 of 1969 objects in 27.9s,
                                        measured their releases in 35.2s, linked 69 libraries in 4.9s,
                                        checked in 4.7s`, and no -Wincompatible-sysroot in the log
    coordination/build-gate.lua 4.3     exit 0; `build: 4.3 compiled 3890 of 1969 objects in 25.3s,
                                        measured their releases in 34.7s, linked 69 libraries in 3.9s,
                                        checked in 4.1s` - the same note as 6.1.3: the band links
                                        MatterClusterBackports without Matter, which the release has not
    CharonMatterMTRGenericBaseCluster.m, armv7-apple-ios4.3
                                        fails: MTRDeviceControllerStartupParams.h:240 `property with 'retain
                                        (or strong)' attribute must be of object type`. The smallest of the
                                        144 objects, which imports Matter.h and declares nothing of its own,
                                        is enough to see it: the error is in a header all of them import
    the 144 objects, the package's own flags, before the plain data family
                                        armv7-apple-ios6.0, iPhoneOS16.4.sdk, -fobjc-arc -Os -Wall
                                        -Werror=objc-missing-property-synthesis, xargs -P 2, one log per
                                        object: 144 of 144 compiled, 0 errors, 0 warnings from the port's
                                        code. One flag pair is named rather than counted: the repository's
                                        own host compiles add -Wno-incompatible-sysroot
                                        (tests/macho_test.py and every gate call), and with it the 144 logs
                                        are empty. Without it the only diagnostic clang can add is its own
                                        `using sysroot for 'iOS 16.4' but targeting 'thumbv7-apple-ios6.1.3'
                                        [-Wincompatible-sysroot]`, which is the SDK against the deployment
                                        target and not a line of the port's - so it is named here instead
                                        of being rounded into "0 warnings"
    the same 144 objects for armv7-apple-ios4.3
                                        0 of 144 compile, and the same diagnostic is in all 144 logs
    tests/backports/host/matter/plants.sh
                                        plants run 4, failures 0: control 0, drop 1, rename 1, extra 1
    tests/backports/host/matterdifferential/run.sh
                                        DOES NOT BUILD on this host: 142 clusters not built, 0 checked

The invariant asks both ways and each direction has a control. Forward: every selector the header declares is
in the generated file - 1,162 members over 83 clusters when the invariant was first written. Reverse: every
selector the file defines is in the contract - it named 700 on `MTRBaseClusterTestCluster` alone, and an
invented instance method injected into one emitted object is caught and named, so the reverse direction is
not vacuous.

**The designated-initializer diagnostic cannot be satisfied, and the 60 objects that raise it silence it
where the repository silences it.** 60 of the 144 objects are the clusters SDK 16.4 declares AND marks
`-initWithDevice:endpointID:queue:` `NS_DESIGNATED_INITIALIZER` on: clang then asks the initializer to chain
to a designated initializer of the superclass, and the superclass `MTRCluster` declares
`-init NS_UNAVAILABLE` (MTRCluster.h:40 in 16.4, :42 in 26.2), so

    self = [super init];        error: 'init' is unavailable

is the measurement, not an assumption, and it is the same through a category or a class extension that
redeclares `-init` (both probed; the attribute stays). Four ways of writing the chain are measured in
`coordination/crutches.md`. What the 60 objects therefore carry is

    #pragma clang diagnostic ignored "-Wobjc-designated-initializers"

directly under the imports, with the reason in the comment above it, which is where this repository puts that
pragma - `MTLRasterizationRate13.m`, `GCMouseInput.m`, `CXCall10.m` and about twenty others. The predicate is
read from the SDK, not from a list: `chain_blocked()` is true where 16.4's own block carries the attribute on
the initializer, which is 60 of the 63 clusters 16.4 declares - `MTRBaseClusterBasic`,
`MTRBaseClusterBridgedDeviceBasic` and `MTRBaseClusterTestCluster` it declares without it, and those three
objects get no pragma. The 79 objects whose `@interface` the port writes carry none either.

The initializer itself does the work that matters: it writes the device, the endpoint and the queue it was
given into the three ivars its class declares, boxing the `uint16_t` that the header's deprecated
`initWithDevice:endpoint:queue:` hands it.

**The differential does not build here, and the reason is the port's own types header.** `CharonMatterTypes.h`
declares every cluster class SDK 16.4 lacks, because the library compiles against 16.4 and an object that
implements a class no `@interface` declares is `cannot find interface declaration for`. This host's
Matter.framework declares 141 of the 142 emitted clusters, and 78 of the port's declarations carry a name
the host also declares, so every one of the 142 programs is `duplicate interface definition for class`. An
earlier version of this file reported `checked 139, differing 0` for this check; that does not reproduce on
this machine at this tree, and the difference is the host's framework, not the port. Running it needs a host
whose `Matter.framework` declares none of the 78, or the port's cluster declarations under a guard the
differential can turn off.

## What the host differential says about the PORT (2026-10-03, the coordinator's ruling)

`sh tests/backports/host/matter/params-diff.sh` runs the same probe on both sides - the host against
`/System/Library/Frameworks/Matter.framework`, the port against the generator's own objects regenerated for
this host with `--sdk16 <the host SDK>`, the same rule the shipped tree applies to 16.4. It compares what
each side answers for the same driver, and it runs a RED CONTROL: one value in one port object changed, and
the run must notice.

**THE PORT DOES NOT YET MATCH, and the numbers are the measurement.** Three runs, each with the red control:

    run                             ownDescription    description    fresh         alias
    first (port side generated with no --host-measurements)
                                   66 of 918          0 of 918      3141 of 3273  25 of 37
    second (--host-measurements, -description through the accessors)
                                   918 of 918         393 of 918    3141 of 3273  26 of 37
    third (--host-measurements, -description through the OWN STORAGE)
                                   918 of 918         393 of 918    3141 of 3273  26 of 37

66 on `ownDescription` was exactly the number of classes that do NOT override `-description`, which is what a
port that wrote none of them looks like. It is 918 of 918 now. The red control moved 923 readings each time,
so the comparison can fail and its verdict is a verdict.

**What is left, each with the measurement that explains it.**

**The ruling changed what these numbers mean.** The host's Matter.framework is built from a LATER SDK than
the one the port implements - it renames `thumbnailUrl` to `thumbnailURL` and reorders members - so a
difference in member SET, ORDER or NULLABILITY between the two is a difference between two RELEASES. The port
keeps 26.2's declaration, and `tests/backports/host/matter/predict.py` lays the port's own VALUES out in the
HOST SDK's declaration order and set, read from that SDK's headers with the generator's own reader. Three
families of reading:

    identical   the port's reading IS the host's
    predicted   a difference the two SDKs' DECLARATIONS account for, named one by one
    unexplained a difference no declaration difference accounts for. THIS IS WHAT MUST BE ZERO.

    run                                          description                      fresh                    alias
    first (no --host-measurements on the port side)
                                                  66 of 918 ownDescription, 0 of 918 description
    second (-description through the accessors)    918 / 393 / 0                   3141 / 0 / 132           25 of 37
    third (-description through the OWN STORAGE)   918 / 393 / 0                   3141 / 0 / 132           26 of 37
    fourth (an own member that shares an ivar is emitted like a category member)
                                                  918 / 3151 / 39 / 83            3151 / 39 / 83            37 of 37
    fifth (a nonnull member of another plain data class is [[X alloc] init]; the family closes over
           the classes its members name, which added MTRUnitTestingClusterNestedStructList)
                                                  918 of 919 / 3216 / 39 / 25     3216 / 39 / 25           37 of 37

`alias` is 37 of 37 and the fourth and fifth runs each carry the red control. What the 25 are, and it is
three things:

* **an own member that shared an ivar and was still `@synthesize`d** - which is now fixed. The synthesis
  gave `MTRApplicationBasicClusterApplicationStruct.catalogVendorId` a second ivar, so the member answered
  nil where its successor answered the shared value, with both SDKs declaring it `NSNumber * nonnull`.
* **a nonnull member whose type is another plain data class**: the host allocates one and the port held nil.
  It is `[[X alloc] init]`, the same construction the class's own `-init` does, and 83 readings were this
  one cause. Making it so added one class to the family - `MTRUnitTestingClusterNestedStructList`, which ends
  in none of the three suffixes and is named by
  `MTRTestClusterClusterTestNestedStructListArgumentRequestParams`'s `list` member. Without an object for it
  the library did not LINK: `Undefined symbols for architecture arm64:
  "_OBJC_CLASS_$_MTRUnitTestingClusterNestedStructList"`. The family now CLOSES over the classes its members
  name, so 924 classes and 1068 objects, and the oracle for 26.2's own defaults is the connectedhomeip tree
  already on this machine at `charon/.agent-work/upstreams/chip/src/darwin/Framework/CHIP/zap-generated/`,
  whose generated `MTRCommandPayloadsObjc.h` is the 26.2-era shape (`groupID` at `MTR_AVAILABLE(ios(16.4))`,
  the same as 26.2).

* **NOT FIXED, and named**: `MTRDeviceControllerStartupParams.fabricID` and `.ipk` - the host holds `(null)`
  where the port holds a zero, and both SDKs declare the member `nonnull`. That is host behaviour the port
  does not reproduce, it is two readings, and it needs its own measurement of which members the host's
  `-init` deliberately leaves nil.

* **NOT FIXED, and named**: `ownDescription` is 918 of 919, the one being
  `MTRUnitTestingClusterNestedStructList` - the class the closure added after the measurement was taken. The
  measurement has to be re-taken with the class in it; one reading.

* `alias` 26 of 37. Eleven rows where the port's own `measured=` differs from the host's: the host says
  `MTRApplicationBasicClusterApplicationStruct.applicationId` shares `applicationID` and the port's own probe
  says `own`. The port's accessors and the shared ivar are right - `applicationId` and `applicationID` are both
  `NSString *` and both read the same slot - so the port's BEHAVIOUR test is what is wrong: it writes the alias
  through a setter that copies, and two writes of one sentinel then read equal. The test has to write two
  DIFFERENT values of the type, which is what the host-side run does.

**The second run's port side does not build.** Generated with `--host-measurements` and `--sdk16 <the host
SDK>`, 23 of 1067 objects do not compile against the macOS SDK - `CharonMatterMTRAccessControlCluster
AccessControlEntryStruct.m`, `CharonMatterMTRChannelClusterProgramStruct.m` and 21 more - because the
port's `-description` reads each member through its SDK 26.2 getter and the host SDK declares some of them
differently or not at all. That is the same defect the shipped tree has for its own target and it is NOT
fixed. Until it is, the honest statement is: the three behaviours are measured, the port has the -init
defaults and the alias storage, and it has NOT been shown to answer -description or the alias conversions the
way the host does.

## What the host answers, and what the port does not (measured 2026-10-03, review of 5b0f9f271)

Three behaviours of the 923 plain data classes are NOT what the port does. They are measured here by
`tests/backports/host/matter/params-probe.m`, one program that runs against the host's Matter.framework and
prints, per class, what a fresh `[[X alloc] init]` holds, the alias round trip, the copy in both directions
and the `-description`. The probe reads nothing at compile time - the class, the properties and their names
come from the runtime and from its driver - so the same source is the whole comparison.

**1. `-init` leaves members nil where the host fills them.** Measured:

    fresh  MTRGroupsClusterAddGroupParams  groupID                NSNumber(0)
    fresh  MTRGroupsClusterAddGroupParams  groupName              NSString()
    fresh  MTRGroupsClusterAddGroupParams  timedInvokeTimeoutMs   (nil)
    fresh  MTRTestClusterClusterSimpleStruct  a                   NSNumber(0)
    fresh  MTRTestClusterClusterSimpleStruct  d                   NSData(0)
    fresh  MTRAccessControlClusterAccessControlEntryStruct  privilege  NSNumber(0)
    description  MTRGroupsClusterAddGroupParams  <MTRGroupsClusterAddGroupParams: groupID:0; groupName:; >

so a NONNULL object property is the zero value of its own type and a NULLABLE one is nil. That IS derivable
from the header - the type and the nullability are in the declaration - and the derivation is
`default_of()` in `tools/matter-generate.py`. The port's side is NOT yet shown to match - the differential
counts 3141 of 3273 `fresh` readings identical - so this is "written and measured on the host", not "matched".

**2. A deprecated alias is the same value as its successor.** Measured, both directions:

    alias  MTRGroupsClusterAddGroupParams  groupId   groupID   NSNumber(1001)
    alias  MTRGroupsClusterAddGroupParams  groupID   groupId   NSNumber(1001)

88 alias pairs are named by the SDK's own deprecation text - `@property ... NSNumber *groupId
MTR_DEPRECATED("Please use groupID", ...)` - and the pair is read out of that text, never from a list. The
MEASURED pair is what decides, because the text does not always name a member: 82 were measured, and **49 of
them disagree with the text**. `MTRControllerFactoryParams.storageDelegate` says "Please use the storage
property", which is prose, and the host gives it storage of its own. LANDED: the probe finds the shared
storage by setting the alias to a sentinel and reading every own member, so the name is a measurement and not
a reading of the prose.

**Whether an alias shares storage is MEASURED, per pair, and the answer is not what the deprecation text
says.** The probe writes the alias TWICE, with two values of the alias's OWN type, and watches whether another
member's reading moves. An earlier version of it wrote one `NSValue` sentinel through KVC whatever the type
was, and that produced 11 rows reading `raised` which were the probe's own artifact and not host behaviour: a
`BOOL` or a `uint64_t` member answers an `NSValue` with `NSInvalidArgumentException`. With a typed value the
run is clean - **0 raised rows** - and 36 of the 37 alias pairs measure as SHARING their successor's storage.

Four of those 36 are pairs whose two types DIFFER, and the host converts between them rather than keeping two
storages. The conversion is measured too, by writing the successor and reading the alias:

    aliasBack  MTRReadParams  filterByFabric  fabricFiltered  NSNumber(1)
    aliasBack  MTRSubscribeParams  replaceExistingSubscriptions  keepPreviousSubscriptions  NSNumber(0)
    aliasBack  MTRSubscribeParams  resubscribeAutomatically  autoResubscribe  NSNumber(1)

A `BOOL` ivar read back through an `NSNumber *` alias reads 0 or 1 and never the value written - 42 goes in as
a `BOOL`, 1 comes out - so the ivar is the successor's type and the alias's accessors convert. The four:
`MTRReadParams.fabricFiltered`, `MTRSubscribeParams.keepPreviousSubscriptions`,
`MTRSubscribeParams.autoResubscribe`, and `MTRDeviceControllerStartupParams.fabricId`, whose successor
`fabricID` the host measures as NOT shared.

**One pair measures as NOT sharing**: `MTRDeviceControllerStartupParams.fabricId`, whose declared successor
is `fabricID`. That is host behaviour and the port answers the same - its own storage. So one alias keeps
storage of its own, and the generator counts and names it rather than a list of six that included five
measurements nobody had taken.

**3. `-description` is overridden, BUT NOT BY EVERY CLASS.** The format, where it is overridden, is measured:

    description  MTRGroupsClusterAddGroupParams  <MTRGroupsClusterAddGroupParams: groupID:0; groupName:; >
    description  MTRAccessControlClusterAccessControlEntryStruct  <MTRAccessControlClusterAccessControlEntryStruct:
        privilege:0; authMode:0; subjects:(null); targets:(null); auxiliaryType:(null); fabricIndex:0; >
    description  MTRReadParams  <MTRReadParams: 0x1022a9a20>

`<` + the class name + `: ` + `name:value; ` per property of the class's OWN @interface, in declaration
order, + `>` - inherited properties are not in it, and the value is what `%@` prints. **66 of the 918 classes the host has do NOT override it**, and that is NSObject's own `<Class: 0xADDRESS>`.
So which classes override `-description` is a fact about the host's binary and not about the header. It is
MEASURED: `tests/backports/host/matter/params-probe.m` reads `class_copyMethodList` on the class itself -
`respondsToSelector:` answers YES for every class that inherits NSObject's - and the run's output is
committed as `tests/backports/host/matter/host-measurements.tsv` with the host's own version
(`Matter.framework 1.4.0.94`) and the date in its first line. `tools/matter-generate.py
--host-measurements` reads it, and a class the host does not have is 5 of the 923: the port keeps the
header's answer for those and says so, per class, in the object. The port's side is NOT yet shown to match:
the differential counts 25 of 37 alias readings identical.

The copy the port writes is right: `copy  <class> <property> original-after-copy-write` and
`copy-after-original-write` differ on the host in every fixture tried, and so do they in the port.

## What is owed

- **The plain data classes are carried; their initialisers are not.** The 923 `*Params`/`*Struct`/`*Event`
  classes are generated, declared and implemented - "What is carried" above - and 86 of the framework's
  `missing` rows are the members those classes carry beyond their properties:
  - **82 are `-initWithResponseValue:error:`**, one per response params class
    (`MTRDoorLockClusterGetUserResponseParams`, `MTRAccessControlClusterReviewFabricRestrictionsResponseParams`,
    `MTROTASoftwareUpdateProviderClusterQueryImageResponseParams` and the rest). The host measurement of what
    that method answers with is in the section below; the SUCCESS path is still unmeasured, because
    `MTRCommandPathKey` must hold an `MTRCommandPath` object, which is another SDK class the port does not
    carry yet (the next bullet family: `MTRClusterPath` and the three that extend it).
  - **`MTRSubscribeParams`** carries `-init`, `+new` and `-initWithMinInterval:maxInterval:`; its two
    properties are carried and the three methods are not.
  - **`MTRDeviceControllerStartupParams`** carries `-init`, `+new` and the four `initWith...` initialisers the
    header gives it, and **`MTRDeviceControllerFactoryParams`** `-init` and `-initWithStorage:`. Each is a
    plain holder, so each keeps what it was given. `-init` is `NS_UNAVAILABLE` on the first, which is why no
    object in this family writes one.
- **3 clusters the SDK spells two ways** are excluded: the SDK declares `MTRBaseClusterOtaSoftwareUpdateProvider`,
  `MTRBaseClusterOtaSoftwareUpdateRequestor` and `MTRBaseClusterWakeOnLan` as DEPRECATED SUBCLASSES of the
  classes the runtime registers, `MTRBaseClusterOTASoftwareUpdateProvider`, `MTRBaseClusterOTASoftwareUpdateRequestor`
  and `MTRBaseClusterWakeOnLAN`. The runtime spellings are carried; on a case-insensitive volume the two file
  names are one inode, which is why the generator treats a case-only collision as an error.
- **`initWithDevice:endpointID:queue:`** was reported `shape-differs` by an earlier differential run, on the
  clusters that run compared. The emitted object carries the header's own declaration verbatim and nothing
  re-measures it now, because the check does not build on this host (see "What is measured"); deciding which
  side's shape is wrong needs the system class's signature read out of the binary.
- **The comparison against the system framework is OWED.** `tests/backports/host/matterdifferential/run.sh`
  reports `DOES NOT BUILD on this host: 142 clusters not built, 0 checked` for the reason given above, so no
  member set has been compared with the system framework's. Every `effect` in `registry/Matter/ios16.json`
  therefore claims only the generator's own two-way check, which is what the run measures.
- **`MTRCluster`'s 17.4 `endpointID` is not carried.** SDK 26.2's `MTRCluster.h` gives the class one member the
  library's own SDK does not declare: `@property (nonatomic, readonly) NSNumber *endpointID
  NS_REFINED_FOR_SWIFT MTR_AVAILABLE(ios(17.4), macos(14.4), watchos(10.4), tvos(17.4))`. 16.4 declares the class
  with `-init` and `+new` `NS_UNAVAILABLE` and no member, so `CharonMatterMTRCluster.m` is the class and nothing
  else, and a client that asks a port cluster for its endpoint gets no responder. No row claims the member -
  `MTRCluster`'s row says `no member and no state of its own` and names the omission. `SHARED_TYPES` already
  names `endpointID` for `MTRCluster`, so emitting it is a small follow-up behind the same `minimum`
  machinery, not a design question, and the plain data family above did NOT change it: that family declares
  only what a *payload* class needs, and `MTRCluster` is a base. The endpoint a caller does have is the one its
  own initializer was given, in `_charon_endpoint`.
- **`MTRClusterPath`, `MTRAttributePath`, `MTRCommandPath` and `MTREventPath` are declared and not
  implemented** - 15 of the framework's `missing` rows - and they are what `-initWithResponseValue:error:`
  needs before its SUCCESS path can be measured on the host. `tools/matter-generate.py --paths` writes the
  four objects and the host measurement of their shape is the section "The path classes, as the host answers"
  below; the wiring is what is owed.
- **4 of the 145 `MTRBaseCluster` classes have no object** - `MTRBaseClusterBarrierControl`,
  `MTRBaseClusterBinaryInputBasic`, `MTRBaseClusterElectricalMeasurement` and
  `MTRBaseClusterOnOffSwitchConfiguration` - and 1,202 rows are missing with them. They are not excluded and
  not unread: the generator emits the other 142 from `clusters-emitted.txt`, and these four are simply not on
  that list. They are owed with the concrete `MTRCluster*` classes.
- **The 122 concrete `MTRCluster*` classes have no object** - `MTRClusterOnOff`, `MTRClusterThermostat`,
  `MTRClusterElectricalMeasurement` and the rest, declared in `MTRClusters.h` as `: MTRGenericCluster` - and
  3,361 rows are missing with them. They carry the same members their `MTRBaseCluster` counterpart does, in the
  SDK's own declaration, so the generator reads them the same way; what they need is the class list and the
  base class each of them declares.
- **The 3,179 `+readAttribute...WithClusterStateCache:endpoint:queue:completionHandler:` and `+new` rows on the
  142 emitted clusters are not carried.** The generator deliberately does not answer them: a cluster-state
  cache is a live node's state and a release with no Matter hardware has none. They are OWED, not ABSENT -
  `tests/backports/host/matter/excluded.txt` and the registry hold no claim either way.
- **Attribute state is per cluster CLASS, not per cluster instance.** `+charon_port_values` is one
  `static NSMutableDictionary` per class, indexed by attribute name alone, so two cluster objects of the same
  class over two endpoints share every value written through either. What IS per instance is the identity the
  initializer was given: `_charon_device`, `_charon_endpoint` and `_charon_queue`, which the object's own
  initializer writes and no member reads back, because no member here reaches a fabric. Per-instance storage
  keyed by (device, endpoint) is what a real node needs, and it is owed with the rest of the fabric-free
  behaviour.

Every group above is OWED, not ABSENT: no row anywhere claims the port does not carry them, and no object is
emitted for an excluded name.

## The registry rows

`registry/Matter/ios16.json` is written by `tools/matter-registry.py` from the emitted objects, in the
registry's own layout: one row per class the objects define and one per method they define, which is 144 class
rows and 8475 method rows. The classes are read out of the objects, not out of a list of cluster names, so an
object the run wrote and the gate builds cannot be without a row - which is what four of them were for a whole
series: `MTRBaseClusterContentControl`, `MTRBaseClusterGroupcast` and `MTRBaseClusterTimer` were passed to the
writer with `--skip` on a claim that they do not build, which stopped being true when the params family was
forward-declared, and `MTRGenericBaseCluster` is not a cluster and so was never on a cluster list at all. A
class with no row is what the 6.1.3 gate reports as `neither the SDK, the registry nor a held release's own
cache says which iOS release X arrived in`, and an object with no registry `minimum` is compiled by every band
below the floor its neighbours have, which is how four objects reached armv7-apple-ios4.3 and failed there.

`introduced` is read from the header's own availability annotation, per member where the member carries one:
16.1, 16.4, 17.0, 17.4, 17.6 and 18.4 are all in the file. Four tiers, taken in order: the member's own
annotation; the `@interface`, category or `@protocol` it sits in; the first dated sibling property or method
of the class; and only when none of those exists the annotation on the line above the `@interface`. The
third tier is the plain data family's, and it is what dates 599 of the 1067 class rows: a payload class
declares no method at all, so the method loop leaves it undated and the annotation above its `@interface` is
a comment. A member with no annotation of its own takes its class's, and `MTRGenericBaseCluster` is dated 17.4
and `MTRCluster` 16.1 by the annotation above its own. **5236 of the 14948 rows take the 16.0 fallback, which
the header states nowhere - 376 class, 3214 method and 1646 property rows - and a further 815 method rows carry
no annotation of their own and take their class's release, which the header does state.** What falls back is
what SDK 26.2 annotates `MTR_PROVISIONALLY_AVAILABLE`: it expands to an export or to `NS_UNAVAILABLE` and
names no iOS release, so there is nothing to read and the tool says so rather than inventing a number per row.
`registry/Matter/ios16.json.unannotated` lists every declaration the header leaves undated - 6978 of them, a
superset of the 5236 that take the fallback - so both sets are countable from one file and neither is hidden.
The counts are by KIND, which the tool used to get wrong: it sorted the fallback rows by whether the row's
name holds a `[`, so every `Class.property` row counted as a class and it reported 2022 class rows over 1067
classes.

**Every row says `minimum` 6.0, and that is measured.** SDK 16.4's `MTRDeviceControllerStartupParams.h`
declares

    @property (nonatomic, strong, nullable)
        dispatch_queue_t operationalCertificateIssuerQueue API_AVAILABLE(ios(16.4), macos(13.3), ...);

`dispatch_queue_t` is a C pointer below iOS 6 and an Objective-C object from 6 on, so that line is
`property with 'retain (or strong)' attribute must be of object type` for `armv7-apple-ios4.3` and clean for
`armv7-apple-ios6.0`. `Matter.h` imports that header and every one of the 1067 objects imports `Matter.h`, so
the whole family is carried from 6.0 on: `modules/apple/backports.lua`'s `floors()` reads `minimum` off the
rows and compiles an object only from the release its rows name, and `band()` puts it in the `left` list for
every release below it.

## `initWithResponseValue:error:`, as the host answers it

Measured on the host framework with `tests/backports/host/matterdifferential/probe-response-value.m`, four
fixtures against `MTRAccessControlClusterReviewFabricRestrictionsResponseParams`:

| fixture | returns | error domain | code | localizedDescription |
| --- | --- | --- | --- | --- |
| a command data response with a command path that is an `NSNumber` | nil | `MTRErrorDomain` | 4 | `response-value command path is not an MTRCommandPath` |
| the same, with the field's value the wrong class of object | nil | `MTRErrorDomain` | 4 | `response-value command path is not an MTRCommandPath` |
| a dictionary that is not a command data response | nil | `MTRErrorDomain` | 4 | `commandPath is null when not expected to be` |
| nil | nil | `MTRErrorDomain` | 4 | `commandPath is null when not expected to be` |

Two things follow, and only the first is implemented so far. The failure domain and code are fixed —
`MTRErrorDomain` code 4 for every rejection, whatever the reason — so a generic port implementation can
report one error and put the reason in `NSLocalizedDescriptionKey`. The reason itself names the exact
precondition, so the port can mirror the wording.

The SUCCESS path is not yet measured: `MTRCommandPathKey` must hold an `MTRCommandPath` object, which is
another SDK class the port does not carry, so no fixture yet gets past the command-path check. That is the
next measurement, not a guess: build a real `MTRCommandPath` on the host and re-run the same four fixtures.

## The path classes, as the host answers

Measured on the host by `tests/backports/host/matterdifferential/probe-paths.m`:

    commandPath(1,2,3)   MTRCommandPath  command=3  description=<MTRCommandPath endpoint 1 cluster 0x2 (2) command 0x3 (3)>
    attributePath(1,2,7) MTRAttributePath attribute=7
    eventPath(1,2,5)     MTREventPath    event=5
    copy: same class, isEqual 1, same hash 1
    built again from the same ids: isEqual 1, same hash 1
    a different id:          isEqual 0, same hash 0

`MTRClusterPath` is `NSObject <NSCopying, NSSecureCoding>` with readonly `endpoint` and `cluster`; each of
the three adds one readonly id. The header marks `-init` and `+new` `NS_UNAVAILABLE` on `MTRClusterPath`, so
a path is built only through the factory. The host's `description` annotates a cluster and an id it does not
recognise as `<Unknown clusterID 2>`; the port has no cluster table, so it emits the same format without that
annotation and says so.
