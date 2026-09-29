# The sec_trust / sec_identity / sec_certificate family, and the obstacle measured

Nine rows, all from **`Security/SecProtocolTypes.h`**, not from `SecIdentity.h` or `SecTrust.h` as the
names suggest:

| api | line |
| --- | --- |
| `sec_trust_create` | :188 |
| `sec_trust_copy_ref` | :203 |
| `sec_identity_create` | :218 |
| `sec_identity_create_with_certificates` | :237 |
| `sec_identity_access_certificates` | :256 |
| `sec_identity_copy_ref` | :273 |
| `sec_identity_copy_certificates_ref` | :288 |
| `sec_certificate_create` | :303 |
| `sec_certificate_copy_ref` | :318 |

## What the header says they are

```
    34  #ifndef SEC_OBJECT_IMPL
    41  SEC_OBJECT_DECL(sec_trust);
    42  SEC_OBJECT_DECL(sec_identity);
    43  SEC_OBJECT_DECL(sec_certificate);
```

and the comment above them (`SecProtocolTypes.h:36`), which is the specification, in our words: the wrappers make
the trust, identity and certificate CoreFoundation types usable in os_object-style APIs and under ARC, and the
client can take the underlying CF type back out.

So a wrapper is an **object that holds a CF ref** — the honest shape is a small class per type, holding
the ref with a `CFRetain` its `dealloc` gives back, and the getters handing it out `+1`.

## The obstacle, measured rather than assumed

**The types are already declared by the headers a Security port must include.** Writing the family as
three `@interface` declarations in the port's own file does not compile:

```
error: conflicting types for 'sec_identity_access_certificates'
     (SecProtocolTypes.h, the SDK's own declaration)
```

`Security.h` reaches `SecProtocolTypes.h`, so on a build that links the release's headers the port sees
`@interface sec_identity` and the function prototypes **already**, and a second declaration of either is a
conflict rather than an override. Two consequences follow, and they are the decisions this family needs:

1. **The port must not redeclare the class.** It can only implement the nine functions the header
   declares — which is fine, and is what a backport does — but then it cannot add an ivar to hold the
   `CFTypeRef`, because the class's storage is already fixed by the header.
2. **The held state has to live outside the class**: a side table keyed by the object, or a category with
   an associated object. That is a real design choice with a real cost — a side table keyed by object
   pointer needs a lock, needs a removal on `dealloc`, and cannot be a category ivar — and it is the
   reason this family is not a mechanical transcription of the nine functions.

The alternative, declaring the class in the port and **not** including `SecProtocolTypes.h`, is not
available either: the header carries `API_AVAILABLE(ios(13.0))` on all nine, so a file compiled for
`armv7-apple-ios6.0` with `-Werror=unguarded-availability-new` fails on the header's own availability
macros for the very API it provides. That much is in the build log either way.

## Not implemented

The nine rows stay as they are. This file records the header facts, the exact error, and the two design
options, so the next attempt starts from the measurement instead of from the nine greps.
