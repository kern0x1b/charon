

### The rest of the sync engine surface

`CKSyncEngine17.m` over the same header. The engine, its configuration, the twelve events, the three
pending changes, the batch, the two classes of what the service refused and the two of what it
reports gone. **The whole header is 32 classes and 78 properties, and none of them is an R4 case** —
they are all in the 26.2 surface the corpus measures.

- **The engine's four requests are the operations this package already carries** — a fetch of the
  database is `CKFetchDatabaseChangesOperation`, a fetch of a zone is
  `CKFetchRecordZoneChangesOperation`, a send is `CKModifyRecordsOperation` — so what the engine adds
  is the state and the order, not a request of its own.
- **Both of the engine's initialisers refuse**, and the refusal is worth its own line: the host
  *traps*. `+[CKSyncEngine new]` and `-[CKSyncEngine init]` on the host raise
  `Fatal error: Use of unimplemented initializer 'init()' for class 'CloudKit.__CKSyncEngine'`, because
  the class behind the public one is private and its `-init` is not implemented. A trap takes the
  process down; this port raises `NSInvalidArgumentException` naming the initializer that is allowed.
- **A refusal from the service is handed over with the thing it was about.** A failed record save
  carries the record, a failed zone save the zone, and the failed deletes are dictionaries keyed by
  what was refused. A caller has to decide what to do about a record it did not save, and it cannot
  find that record again by itself.
- **A fetched deletion carries what an identifier does not.** A record deletion carries the record
  type as well as the identifier, and a zone deletion carries which of the three reasons it gives —
  deleted, purged, or the user reset their encrypted data. Those are different problems for a caller
  and the port does not fold them together.
- **A batch asks the delegate's provider for a record through the port's own selector**
  (`-charon_recordForRecordID:`), because the 26.2 headers type the provider as `id` and declare no
  selector for it. A record the delegate has not read is not sent: a port that sent a record it had
  invented would be overwriting one it never saw.

## The record value half, and the one place it does not match the host

`CKRecordZoneID`, `CKRecordID`, `CKServerChangeToken`, `CKReference`, `CKAsset`, `CKRecordZone` and
`CKRecord` are in `CloudKit/CKRecords8.m`, with the parent and share of iOS 10.0 in
`CloudKit/CKRecords10.m` and the two record decoders in `CloudKit/CharonCKRecords.m`. They were
missing from the tree while the registry carried all seven as `implemented` - 82 rows, 75 classes - and
the release-split refused before the link ever ran, so nothing had found it.

Every refusal, default and equality is the host's own, read out of the running iOS CloudKit by
`tests/backports/host/cloudkit/records-cases.h` and held to the same questions by
`tests/backports/host/cloudkit/records-port.m`; `compare.py` reads the two records and names every
difference. 137 answers, 136 of them identical.

**The one difference, and why it is not matched.** The host's `CKRecordZoneID` is *interned*: a zone ID
decoded out of an archive is the same object as the one encoded, and `compare.py` records `identical`
where this port records `equal`. The two zone IDs are equal by value here and are not the same object.
Matching it means a process-wide table of every zone ID ever made, held for the life of the process,
and the host's retention rules for that table are not something this port can measure. A port that
interns would hold every zone name a caller ever built; one that does not holds only what the caller
still references. The values agree, which is what the equality contract is, and the identity is left
to the caller.

Two more answers are compared by shape rather than by value, and neither is a difference: a record
given no name of its own is given a UUID on both sides, and an archive's byte length is not compared
because a port ships its own archive keys - what is compared is the round trip, which decodes to an
equal object for all five classes that are archived.

The measurements that are easy to get wrong, all from the host:

    +[CKRecordID new]                 NSInvalidArgumentException: You must call -[CKRecordID initWithRecordName:] or -[CKRecordID initWithRecordName:zoneID:]
    -[CKRecordID initWithRecordName:nil]  CKException: recordName can not be nil
    +[CKServerChangeToken new]         CKException: You can't call init on CKServerChangeToken
    -[CKAsset initWithFileURL:nil]     NSInvalidArgumentException: Null fileURL
    -[CKAsset copy]                    NSInvalidArgumentException: -[CKAsset copyWithZone:]: unrecognized selector
    a parent in another zone           NSInternalInconsistencyException: Parent record must be in the same zone as the current record
    set a field key of ""              NSInvalidArgumentException: recordKey can not be empty

    the field key grammar, over all 95 printable ASCII characters:
      accepted as the whole key  ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz        (53)
      accepted after the first  $0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz (64)

    CKRecord and CKRecordZone do not override isEqual: - two records of one type are different, a
    copy is a different object carrying the same fields, and +[CKRecordZone defaultRecordZone] is one
    shared object. CKRecordID, CKRecordZoneID and CKReference compare by value.

## The two names the sweep lists that nothing in the pile ever carried

`CKFetchWebAuthTokenOperation` and `CKShareRequestAccessOperation` are on the sweep's list of 72
CloudKit API names main lacks, and they are the two this series does not carry. They are **owed, and
deliberately absent from the registry rather than filed as `absent`**, because the owner's rule is that
`absent` is only for hardware the device physically lacks and these are two more operations that need an
iCloud account to reach the network.

What is true about them here, measured rather than assumed: no commit in the bundle from which this
series was rebuilt declares either class or implements it.

    $ for n in CKFetchWebAuthTokenOperation CKShareRequestAccessOperation; do
        git log --format=%H --all -- packages/a/apple-backports/CloudKit | while read s; do
          git grep -l "@implementation $n" $s -- packages/a/apple-backports/CloudKit && break; done
      done
      no @implementation in any reachable commit   (both names)

So there is nothing to replay: the header does not declare them, no source defines them, and a row that
said `implemented` would be a claim about code that is not in the tree - the defect the gate refused the
value half for and the reviewer refused it for. They are this series' first two **owed** CloudKit names,
and carrying them is the same work as the engine's: a configuration over the transport, a local state, and
the transport's own refusal in `CKErrorDomain` for the one request each would make.

## The five names the two halves of the pile defined without a row

`CKFetchDatabaseChangesOperation`, `CKFetchRecordZoneChangesOptions` and `CKFetchRecordZoneChangesOperation`
are defined in `CloudKit/CKOperations1210.m`, `CKFetchRecordZoneChangesConfiguration` in
`CloudKit/CKOperations12.m`, and `CKSyncEnginePendingZoneDelete` in `CloudKit/CKSyncEngine17.m`. Every one
of them had **no row at all**: the two halves of the pile each carried the definitions, and neither carried
the registry entry that says so. An `implemented` row without code is what the gate refuses; a definition
without a row is the same defect seen from the other side, and the gate's own rule names it - "built, but no
entry in `registry/`". Each of the five now has a row whose `source` is the file that defines it.

Two things were wrong with the check that should have caught this, and both are fixed here rather than
worked around:

- `tools/corpus/cloudkit-registry-mirror.py` printed its two numbers and **returned nothing**, so it exited 0
  whatever it had found. A check that cannot fail is not evidence: the five names above were reported as
  "both directions 0" on the strength of a mirror that could not have said otherwise. It now exits
  non-zero on either direction.
- The duplicate `(CharonCKBuilding)` categories in `CloudKit/CharonCKSubscription.h` were the same fact in
  the source: two categories of one name on one class, where the runtime keeps one and the other's members
  are never registered. `CKUserIdentity` was declared twice - the four properties in one, `-charon_identity`
  in the other - and `CKShareParticipant` twice, the two properties in one and `-initWithType:` in the
  other. Each pair is one category now, carrying every member it had between them. The pile's own final
  commit carries the same duplication, so this is not a replay artefact.

## A row is keyed by (kind, api), not by the name

Both reports keyed a row on its bare name, so `+[CKRecordID new]` and `CKRecordID` were one key. A
member row then answered the class row's question: delete the class row and leave the member row
`implemented`, and every direction in both scripts read 0 and exited 0. Measured on this tree before
the fix:

    class row CKRecordID deleted, +[CKRecordID new] left implemented
      cloudkit-registry-mirror.py   exit 0   (every direction 0)
      cloudkit-checklist.py         exit 0   (every direction 0)

Both are keyed by `(kind, api)` now, and a fourth direction reads a member row against its class: a
member cannot exist without its class, so `+[CKRecordID new]` reading `implemented` beside a class row
that is `absent`, or with no class row at all, says the class is here and not here in the same breath. A
`constant` row is a global symbol and stands on its own - the twenty-five constants in this registry
(`CKErrorDomain`, `CKRecordTypeShare` and the rest) are not members of anything, and asking them for a
class row would be the same mistake pointed the other way. After the fix, the same two plants:

    class row deleted          mirror exit 1   checklist exit 1
    class row marked absent    mirror exit 1   checklist exit 1

The checklist counts a sweep name as carried only through a class row of its own, which is why it now
also reads `a definition here with no row: ['CKRecordID']` where it read nothing at all: the member row
had been standing in for the class row that was not there.

## Corrections to the record

**`eed61c206`'s statement that the light guard "reports 4 failures, all in `registry_test` on
FileProvider entries … which the same guard reports on `main` without any of this work" is withdrawn.**
It is an artefact of how the guard was invoked, not a property of the tree.

`coordination/run_light_tests.lua` takes the checkout it is to read as an argument, and
`review-mechanical.sh` passes its own fresh worktree:

    lg=$(xmake l "$HOME/Git/projects/ios/coordination/run_light_tests.lua" "$wt" 2>&1 | ...)

Run without that argument, from the repository root, the guard resolves a different set of registry
files and reports four `registry_test` complaints that have nothing to do with CloudKit -
`pathRelativeToDocumentStorage`, `identifier` and `displayName` "a property not spelled
`-[Class selector:]`", and `NSFileProviderDomain` "named by both FileProvider/ios11.json and
FileProvider/ios11.json" (the two files are `ios110.json` and `ios160.json` in the tree the guard
reads when it is given a checkout). Both measurements are real; only the second one is the guard the
gate runs:

    xmake l coordination/run_light_tests.lua <checkout>     10 suites OK, 0 FAIL, exit 0
    xmake l coordination/run_light_tests.lua                 4 failures,           exit 1

Measured on `main` at `a66cdcde5` with the checkout argument, which is what the reviewer ran: **10/10,
0 FAIL**. The four FileProvider failures were reproduced on `main` and on this branch alike, which is
what made them look pre-existing rather than like an invocation artefact - they were pre-existing *for
that invocation*, and that invocation is not the gate's.

The claim as written in `eed61c206` is withdrawn rather than amended: the commit stays, and this
section is the correction. Its other measurements are unaffected - the checklist, the mirror, the
`registry_test` exit and the eleven CloudKit compiles were each run directly against the checkout and
are not touched by this.

## One object carries one release, and one minimum

The band machinery puts an object in the band of the release its API arrived in, so an object whose
symbols first appear in two releases belongs to no band at all. The gate refuses it as "an object
carries API that arrived in one release, so split it", and `tools/release-split.lua` measures the same
thing out of the compiled symbols. Measured on the objects of this tree before the split:

    CKOperations10.o  MIXED-RELEASES  10.0.1,8.3
    CKValues10.o      MIXED-RELEASES  10.0.1,8.0,8.3

`CKAcceptSharesOperation` is 8.3 and the four discover and fetch-share operations are 10.0.1, so the
first is `CKOperations83.m` now. `CKShareParticipant` is 8.0 and joins `CKValues8.m`, the first
release's own value file, and `CKUserIdentity` is 8.3 and is `CKValues83.m`. After the split:

    xmake l tools/release-split.lua <objects> <out> <iPhoneOS16.4.sdk>
    release-split: clean, every object file's symbols first-appear in one release (28 files, 185 symbols, 50 releases checked)

The releases are read from the held dyld caches, so 10.0.1 is the first rung that **exports** the
discover and fetch-share symbols and the arrival is bounded from above by it, the way release-split's
own note says for the rungs the ladder skips. The rows said 10.0 where the measurement says 10.0.1,
and the three moved classes said 10.0 where the measurement says 8.3 and 8.0; all thirteen now carry
the release they were measured at, because a row that names another release than the object is the
same defect the split fixes.

The second half of the gate's finding is the registry's `minimum`, which is the release an **object**
is carried from: the minimum of the entries its API answers to, and an object whose entries name
different minimums is refused, "the earliest would carry API below its minimum, the latest would drop
API the registry carries earlier". `CKSyncEngine17.o` had three rows at 6.0 and eighteen naming none,
which is two answers. Every one of the object's thirty rows now names 6.0, the value the three already
gave, and never above 10: armv7's last deployment is 10, and a minimum above it would take the object
out of every band that can link it. A minimum at or below the deployment bounds nothing, which is why
6.0 is the answer that both satisfies the rule and keeps the object in every band.
