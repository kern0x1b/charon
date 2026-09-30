# The value half of CloudKit

What this delivery carries, what it does not, and where each answer comes from.

## What is here

The classes a caller can build, name, keep, compare, archive and read back before a single request
is made, and the twenty-five constants CloudKit exports. Twenty-seven classes: the record and its
identifier, the zone and its identifier, the server change token, the asset, the reference, the query,
the query cursor, the location sort descriptor, the subscription and its three subclasses, the
notification and the three kinds it comes in, the notification identifier, the notification
information, the user identity and its lookup information, the share participant, the share metadata,
the operation configuration, the operation group and the allowed sharing options.

Nothing here reaches the network. The operations and the transport are a later delivery, and so is
`CKSyncEngine`. That is why `CKOperation` and the twenty operation classes are not here either: an
operation whose `-main` does nothing is a class that exists and does not, which is the one thing the
contract forbids, and an operation cannot be honest until there is something for it to send.

## Where each answer comes from

macOS has CloudKit, so every answer below is a measurement against the host's own framework rather
than a reading of a header. The measurements are in
`.agent-work/plan-and-analysis/musickit-cloudkit/host-measurements.md` of the band that wrote them,
and `tests/backports/host/cloudkit/run.sh` holds this package to them.

The initializers CloudKit refuses are refused with the host's own exception and the host's own words:
`[CKQueryCursor new]` and `[CKServerChangeToken new]` raise `CKException` with "You can't call init on
...", `[CKDatabase new]` raises `NSInternalInconsistencyException`, and the rest raise
`NSInvalidArgumentException` naming the initializers that are allowed. A refusal here is not a decision
this port made: the table of them is in the `effect` of each entry of `registry/CloudKit/values.json`.

The twenty-five constants carry the values the host's own framework hands out, read out of the running
framework:

    CKRecordTypeUserRecord              Users            CKErrorDomain                     CKErrorDomain
    CKRecordTypeShare                   cloudkit.share   CKPartialErrorsByItemIDKey        CKPartialErrors
    CKRecordZoneDefaultName             _defaultZone     CKRecordChangedErrorAncestorRecordKey  AncestorRecord
    CKOwnerDefaultName                  __defaultOwner__ CKRecordChangedErrorServerRecordKey    ServerRecord
    CKCurrentUserDefaultName            __defaultOwner__ CKRecordChangedErrorClientRecordKey    ClientRecord
    CKRecordRecordIDKey                 ___recordID      CKErrorRetryAfterKey              CKRetryAfter
    CKRecordCreationDateKey             ___createTime    CKErrorUserDidResetEncryptedDataKey  CKUserDidResetEncryptedData
    CKRecordModificationDateKey         ___modTime        CKAccountChangedNotification       CKAccountChangedNotification
    CKRecordCreatorUserRecordIDKey      ___createdBy     CKQueryOperationMaximumResults    0
    CKRecordLastModifiedUserRecordIDKey ___modifiedBy     CKRecordParentKey                  ___parent
    CKRecordShareKey                    ___share         CKShareTitleKey                    cloudkit.title
    CKRecordNameZoneWideShare           cloudkit.zoneshare  CKShareTypeKey                  cloudkit.type
                                                          CKShareThumbnailImageDataKey      cloudkit.thumbnailImageData

**`CKQueryOperationMaximumResults` is a `const NSUInteger` and not a string, and it answers 0.** The
first reading of the host took it for nil, because the host's `%@` prints a zero as `(null)`; the
header is what settled it. A limit is a property of a container's configuration, and CloudKit's own
client is handed the service's limit when it asks for none, so 0 is the honest "none" and a number
written into the library from anything else would be a claim about a container this port has never
spoken to.

## The defaults, and whose they are

- A record made of a type and nothing else lands in the default zone of the current user under a fresh
  name; the name is a UUID because CloudKit makes one.
- A record identifier made of a name and nothing else lands in the default zone of the current owner.
- A zone made of a name and nothing else has no capabilities; `+defaultRecordZone` is `_defaultZone`
  of `__defaultOwner__`.
- A record zone subscription made without a zone is the default zone of the current owner.
- A subscription made without an identifier is given a UUID, because a subscription the service cannot
  name cannot be fetched or deleted again.
- An operation configuration that is new is not long-lived, allows cellular access, and carries the
  two timeouts a URL request of this release carries.
- An operation group that is new is given an identifier and has a default configuration.
- A share that has not been told who may be added invites nobody; `+standardOptions` is the read-only
  pair CloudKit's own header documents.

## The rules that are not obvious

- **A field set back to nil is not a change to send.** The host's own `-allKeys` and `-changedKeys`
  agree: after `[record setObject:nil forKey:@"n"]` the key is gone from `-allKeys` and `-changedKeys`
  is empty. A save is idempotent because of this, and a port that kept a nil in the changed set would
  send a change that is not one.
- **A record's equality is its identity, not its values.** Two records of the same name in the same
  zone are the same record whoever wrote them, so `-isEqual:` compares the identifier, the type and
  the change tag.
- **`allTokens` is the string fields only.** A token is a string CloudKit can put in a query, so a
  number, a date and a location are not one.
- **An asset is its file URL, not its bytes.** The bytes travel in a request of their own.
- **A cursor is a token and a token is a string.** Neither is made by an application, and both refuse
  to be made by one.
- **A notification is only ever made by the service.** The factory that reads a remote notification
  payload is the only way in, and the fifteen members a payload fills in are the SDK's readonly
  properties: CloudKit makes a notification by reading one rather than by setting anything, so they
  are readwrite in the port for that reason and for no other.
- **`CKNotificationID` is an empty class in the SDK** - no property, no method, only `NSCopying` and
  `NSSecureCoding`. The name CloudKit gives a notification and the object it was sent to are the
  port's own state; an identifier with no name is the one a notification that has not been delivered
  yet carries.
- **A share's metadata is not instantiated by an application.** The host refuses with its own words
  and so does this port.
- **A subscription is a name and a type, and the base class is a record zone subscription as far as
  the type goes.**

## What is not here, and what answers instead

| not carried | what answers | why |
| --- | --- | --- |
| the requests, the endpoints, the bearer token | `CKErrorNotAuthenticated` (9) or `CKErrorBadContainer` (5) | the transport is a later delivery, and those are the codes the header names for a client that is not signed in and for a container that is not provisioned |
| `CKOperation` and the twenty operation classes | nothing | an operation with nothing to send is a class that exists and does not |
| `CKShare`, `CKSyncEngine` and its events | nothing | they are the request, and the request is the transport |
| `CKShareTransferRepresentation`, the `NSItemProvider` sharing support | nothing | carrying a share out of the process is the share sheet, which is an application |
| `CKShare`'s own record fields of iOS 26 | nothing | `CKShare` is the save, and the save is the transport |

## What the container and the database answer

Added after the value half; the wire shapes are in `WebServices.md`.

- **`CKContainer` is a name and three databases.** The identifier is read out of the Info.plist key
  CloudKit's own tooling writes and kept as given. A database is made once per scope, because the
  transport is told which container a database belongs to and a database with no container could not
  make a request.
- **`+[CKDatabase new]` and `-[CKDatabase init]` raise** `NSInternalInconsistencyException` with the
  host's own words, measured: *"Use +[CKContainer privateCloudDatabase] or +[CKContainer publicCloudDatabase]
  instead of creating your own"*.
- **A query whose predicate the service has no form for never leaves the process.** The caller is
  answered `CKErrorInvalidArguments` on the transport's own queue, which is the code `CKErrorCode`
  names for a malformed predicate.
- **A lookup that found nothing answers `CKErrorUnknownItem`**, and a missing zone
  `CKErrorZoneNotFound`. The service answers 200 with an empty list for both, and a caller handed
  `nil` with no error cannot tell that from a record whose value is nil.
- **A save sends a create or an update, and the change tag decides which.** A record that has never
  been saved is a `create`; one that has a change tag is an `update`, and the tag is what the service
  issued. A port that invented one would overwrite a record it had not read. The system fields - the
  change tag, the dates and the two user record identifiers - are kept out of the fields that go up,
  because the service keeps those and a port that sent them back would be asking it to take its word
  for its own state.
- **The account status is `CKAccountStatusNoAccount`.** Whether the device has an iCloud account is
  the release's own question and this release has no account service to ask, so a device that has none
  answers that, and a process with no container answers it with `CKErrorBadContainer`. This is a
  reading of the release's own state, not a guess: `facts/CloudKit/Errors.md` says what the port does
  and does not claim here.
- **The user discoverability permission is never granted.** A permission that has never been asked
  for answers the header's own initial state; asking for one answers *could not complete* with
  `CKErrorNotAuthenticated`, because asking needs the service and an account and this port has
  neither, and a caller told the initial state instead would be told nothing had happened.
- **The user record is answered without a request.** The record of the signed-in user is the only user
  record a container has, under `_defaultOwner` in the default zone, so a caller that asks for the
  identifier of the user it is in gets it without one; a container with no user yet is answered the
  same way, because the service creates it on first use.

## The operations

`CKOperations8.m`, over the transport. The endpoints and the wire shapes are in `WebServices.md`.

Three promises, because they are what a caller writes code against:

- **The per-item blocks are called on the transport's queue, in the order the service answered, and
  the operation's own completion is called last and exactly once.** A batch that failed in part is
  `CKErrorPartialFailure` with the per-item errors under `CKPartialErrorsByItemIDKey`, which is where
  the header puts them. The service answers such a batch with 200 and the failures beside it, so an
  operation that only looked at the status would tell a caller everything worked.
- **A query whose predicate the service has no form for never leaves the process.** The completion is
  answered `CKErrorInvalidArguments` — the code `CKErrorCode` names for a malformed predicate — and no
  per-item block is called at all.
- **A fetch of records answers a dictionary keyed by the identifier**, and a record that was asked
  for and not found arrives in the per-item failures as `CKErrorUnknownItem` rather than as the fetch
  itself failing. That is the distinction the header draws: the fetch did not fail, one item was not
  there.

Two things worth writing down because a plausible answer would have been wrong:

- **A modify with nothing in it is not a request.** The service would answer 200 with an empty list,
  and a caller's per-item blocks would be called for work nobody asked for, so the operation ends
  with an empty success instead.
- **A create or an update is decided by the service's change tag, never by this port.** A record that
  has never been saved is a create; one that has a tag the service issued is an update. Inventing one
  would overwrite a record that was not read.

**The initializers of the operation classes are refused with the port's own words, not a measured
one.** Every operation class except `CKDatabaseSubscription` marks its `-init` as the designated
initializer, so the port's `-init` is that one and `+new` reaches it. `+[CKOperation new]` and
`-[CKOperation init]` raise `NSInvalidArgumentException` with "You must instantiate one of the
CKOperation subclasses" — the same shape the host answers for a `CKSubscription`, which *was*
measured, and the words for the operations themselves were not probed. That is a written-down
divergence and not a measurement, and it is the one place in this family where the port is not held
to the host's own answer.

**The end of an operation goes through the port's own `-charon_finish`.** This release's
`NSOperation` declares no `-finish` of its own, so the scheduler is what releases a caller waiting on
an operation, and the flag that says an operation has ended is the port's own.
