

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
