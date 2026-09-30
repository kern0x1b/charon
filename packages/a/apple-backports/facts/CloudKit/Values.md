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
