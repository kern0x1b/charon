
## The operations of 9.2, 12.0 and 26

| operation | endpoint | note |
| --- | --- | --- |
| `CKFetchWebAuthTokenOperation` (9.2) | `users/login` | the path a client *handed* a web authentication token uses, rather than signing one of its own |
| `CKFetchRecordZoneChangesOperation` (12.0) | `changes` | one request for several zones, one half per zone |
| `CKFetchDatabaseChangesOperation` (11.0) | `changes` | which zones moved, before any zone is fetched |
| `CKShareRequestAccessOperation` (26.0) | `shares/requestAccess` | asking to be let into a share |

`CKFetchRecordZoneChangesConfiguration` and `CKFetchRecordZoneChangesOptions` are **the same three
members under two names** — the token the last fetch ended at, how many to ask for, and which fields —
and one reader builds the per-zone half out of either. A caller of the iOS 10 shape and a caller of
the iOS 12 one are therefore answered the same way, which is what the header's keeping both is for.

`CKFetchDatabaseChangesOperation` was listed by the corpus at 11.0 and is implemented in the 12.0
file because it arrived with the other changes operations and the band machinery puts an object in
the band of the release the majority of its API came in; the registry entry names 11.0 and this
paragraph says so rather than leaving the two to disagree.

### The iOS 26 surface, and what is not carried

`CKShareRequestAccessOperation` is in the 16.4 headers' absence, so it is **declared in
`CKOperations26.m` beside its own implementation** and not in a header: the build compiles with
`-Werror=objc-missing-property-synthesis`, and that check fires on a class whose properties are
declared in a header whose implementation is in another file. Its three properties are the iOS 26.2
headers' own, transcribed.

**Named for the next delivery, and not carried here:**

- `CKShareAccessRequester` and `CKShareBlockedIdentity` — values the service fills in, declared when
  they are carried, which is with `CKShare`.
- The five iOS 26 members of `CKShare` itself: `allowsAccessRequests`, `allowsParticipantsToInviteOthers`,
  `requesters`, `blockedIdentities`, and `-blockRequesters:`, `-unblockIdentities:`, `-denyRequesters:`.
  They are members of a class this family does not carry, and a port that answered them on a class it
  does not implement would be answering *for* CloudKit.

`CharonCKIOS26.h` forward-declares all of them so the names are in the tree for the lift's sets to
be measured against.

## The sync engine: the state group

`CharonCKSyncEngine26.h` and `CKSyncEngineState17.m`. The surface is thirty-two classes; this is the
first group of them, and the header is a transcription of the iOS 26.2 declarations, which is what
lets the declarations live in a header at all: the build's `-Werror=objc-missing-property-synthesis`
fires on *implicit* synthesis, so **every `@implementation` in this family carries an explicit
`@synthesize` for each of its properties**. That was the whole of the blocker, and it is mechanical.

**Every class and property in that header is a rule R4 case** — the lift's sets are re-measured for
all of them in this push.

In this group: the two scopes, the two options, the two contexts, the state and its serialization.
Four things worth writing down:

- **A scope is one of two things, never both.** Either some zones, or all but some zones, and
  `-containsZoneID:` answers that scope rather than a stored set. A scope of records says which records
  whatever zone they are in, and a zone save or a zone delete is about a zone and not about a record —
  so a record scope does not contain it. There is no fourth case.
- **The state's three collections are copies.** A caller reads them and a caller adds to them through
  the four add and remove methods; the only way out is the same four. A caller that could add to the
  state behind the engine's back would be a change the engine never sends.
- **`+[CKSyncEngineState new]` traps on the host**, measured: `Fatal error: Use of unimplemented
  initializer 'init()' for class 'CloudKit.__CKSyncEngine'`, behind its private class. A trap takes
  the process down. This port refuses with the words that name the two ways a state is had.
- **The two contexts' members are the port's own.** Both initialisers refuse, which is the header's
  marking, so the engine makes one and fills it in and the delegate reads it; the properties are
  therefore writable here while the initialisers still refuse. A context a caller could write would
  be a context the engine never ran.

### Not carried yet, and named

`CKSyncEngine` itself — the four request methods are the walk and are the next group — and with it
`CKSyncEngineConfiguration`, the twelve events, the three pending changes, the batch, the
`CKSyncEngineFailedRecordSave` family and the two fetched-deletion classes. `CKSyncEngine` is
registered **`absent`** with its reason, so nothing is claimed for it: `NSClassFromString` answers nil
and a compile-time reference does not link.

