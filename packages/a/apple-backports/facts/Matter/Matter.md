# Matter

`Matter.framework` does not exist before iOS 16.4, so every release this package carries has no Matter
framework to shadow: a client that links one and asks a cluster a question reaches this port's class
instead. The clusters are therefore generated from the SDK's own headers rather than written by hand,
because a class has too many members for a hand transcription to be right and the header is the contract.

## What is carried

142 of the framework's 145 `MTRBaseCluster` classes are emitted by `tools/matter-generate.py` from the
declarations in `MTRBaseClusters.h`, plus the class they all sit on, `MTRGenericBaseCluster`, which SDK 16.4
does not declare: 143 objects, and each one IS the class it implements. The other three are listed in
`tests/backports/host/matter/excluded.txt` with a reason each. Every member a cluster declares - a read, a
write, a subscribe, a command in every shape the header gives it, a cached read, the initialiser - has a body
that answers without reaching a fabric: the value the caller set, or no value and the error the release
documents for a cluster it cannot reach.

The class's own state is one table keyed by the attribute name and guarded by a lock, because armv7 has no
thread-local storage to rely on. A release with no Matter hardware has no node to read from, so the class
methods the header declares answer as Apple documents: no value, and an error.

## What is measured

    tools/matter-generate.py            run exit 0; invariant 0 in BOTH directions; 143 of 143 objects compile
                                        against SDK 16.4; every object names the class it implements, 143 of 143
    tools/matter-registry.py            8596 rows (143 class, 8453 method) over 143 objects; every class an
                                        emitted object defines has a row: 143 of 143
    CharonMatterMTRGenericBaseCluster.m, armv7-apple-ios4.3
                                        fails: MTRDeviceControllerStartupParams.h:240 `property with 'retain
                                        (or strong)' attribute must be of object type`. The smallest of the
                                        143 objects, which imports Matter.h and declares nothing of its own,
                                        is enough to see it: the error is in a header all of them import
    tests/backports/host/matter/plants.sh
                                        plants run 4, failures 0: control 0, drop 1, rename 1, extra 1
    tests/backports/host/matterdifferential/run.sh
                                        DOES NOT BUILD on this host: 142 clusters not built, 0 checked

The invariant asks both ways and each direction has a control. Forward: every selector the header declares is
in the generated file - 1,162 members over 83 clusters when the invariant was first written. Reverse: every
selector the file defines is in the contract - it named 700 on `MTRBaseClusterTestCluster` alone, and an
invented instance method injected into one emitted object is caught and named, so the reverse direction is
not vacuous.

**The differential does not build here, and the reason is the port's own types header.** `CharonMatterTypes.h`
declares every cluster class SDK 16.4 lacks, because the library compiles against 16.4 and an object that
implements a class no `@interface` declares is `cannot find interface declaration for`. This host's
Matter.framework declares 141 of the 142 emitted clusters, and 78 of the port's declarations carry a name
the host also declares, so every one of the 142 programs is `duplicate interface definition for class`. An
earlier version of this file reported `checked 139, differing 0` for this check; that does not reproduce on
this machine at this tree, and the difference is the host's framework, not the port. Running it needs a host
whose `Matter.framework` declares none of the 78, or the port's cluster declarations under a guard the
differential can turn off.

## What is owed

- **The `*Params` classes are forward-declared, not implemented.** 234 of them - `MTRGroupcastClusterJoinGroupParams`,
  `MTRTimerClusterSetTimerParams`, `MTRContentControlClusterUpdatePINParams` and the rest - are named by the
  commands, so they are in the `@class` line of `CharonMatterTypes.h` and every command accepts one and
  passes it through. Nothing implements them yet, so a caller cannot build one: generating that family is
  the next piece of work. Their absence is a gap in what the port IMPLEMENTS, not in what it compiles.
- **3 clusters the SDK spells two ways** are excluded: the SDK declares `MTRBaseClusterOtaSoftwareUpdateProvider`,
  `MTRBaseClusterOtaSoftwareUpdateRequestor` and `MTRBaseClusterWakeOnLan` as DEPRECATED SUBCLASSES of the
  classes the runtime registers, `MTRBaseClusterOTASoftwareUpdateProvider`, `MTRBaseClusterOTASoftwareUpdateRequestor`
  and `MTRBaseClusterWakeOnLAN`. The runtime spellings are carried; on a case-insensitive volume the two file
  names are one inode, which is why the generator treats a case-only collision as an error.
- **`initWithDevice:endpointID:queue:`** is reported `shape-differs` by the differential on the clusters it
  checks. The emitted object carries the header's own declaration verbatim; deciding which side's shape is
  wrong needs the system class's signature read out of the binary.

The first two groups are OWED, not ABSENT: no row anywhere claims the port does not carry them, and no object
is emitted for an excluded name.

## The registry rows

`registry/Matter/ios16.json` is written by `tools/matter-registry.py` from the emitted objects, in the
registry's own layout: one row per class the objects define and one per method they define, which is 143 class
rows and 8453 method rows. The classes are read out of the objects, not out of a list of cluster names, so an
object the run wrote and the gate builds cannot be without a row - which is what four of them were for a whole
series: `MTRBaseClusterContentControl`, `MTRBaseClusterGroupcast` and `MTRBaseClusterTimer` were passed to the
writer with `--skip` on a claim that they do not build, which stopped being true when the params family was
forward-declared, and `MTRGenericBaseCluster` is not a cluster and so was never on a cluster list at all. A
class with no row is what the 6.1.3 gate reports as `neither the SDK, the registry nor a held release's own
cache says which iOS release X arrived in`, and an object with no registry `minimum` is compiled by every band
below the floor its neighbours have, which is how four objects reached armv7-apple-ios4.3 and failed there.

`introduced` is read from the header's own availability annotation, per member where the member carries one:
16.4, 17.0, 17.4, 17.6 and 18.4 are all in the file. A member with no annotation takes its class's, and a class
no member dates takes the annotation on the line above its `@interface` - which is how `MTRGenericBaseCluster`
is dated 17.4, the release `MTRCluster.h` states for it, and the only statement the SDK makes about it since
it declares no member at all. **3057 of the 8453 method rows and 32 of the 143 class rows take a release the
header does not state for them** - the clusters SDK 26.2 annotates `MTR_PROVISIONALLY_AVAILABLE`, which expands
to an export or to `NS_UNAVAILABLE` and names no iOS release - and every one of those rows is listed in
`registry/Matter/ios16.json.unannotated`, a bare class name for a class row and the row's own spelling for a
method row, so the assumption is countable rather than hidden.

**Every row says `minimum` 6.0, and that is measured.** SDK 16.4's `MTRDeviceControllerStartupParams.h`
declares

    @property (nonatomic, strong, nullable)
        dispatch_queue_t operationalCertificateIssuerQueue API_AVAILABLE(ios(16.4), macos(13.3), ...);

`dispatch_queue_t` is a C pointer below iOS 6 and an Objective-C object from 6 on, so that line is
`property with 'retain (or strong)' attribute must be of object type` for `armv7-apple-ios4.3` and clean for
`armv7-apple-ios6.0`. `Matter.h` imports that header and every one of the 143 objects imports `Matter.h`, so
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
