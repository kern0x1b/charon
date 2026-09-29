# The accessory setup classes, of 11.3, 13.0, 15.0 and 15.4

Four classes an application uses to add an accessory to a home from the accessory's own HomeKit setup
code, and one of them — `HMAccessoryOwnershipToken` — that they refer to and that this port does not
carry. The header is the source for everything here; no Apple body was read, and nothing on this machine
opened a network connection or a real HomeKit store.

## `HMAccessorySetupPayload` — 11.3, and 13.0

**The release declares no property on this class.** That is the whole of the surface, and it is worth
saying plainly because a reader looking for a getter will not find one: a payload is something a home is
*given*, and the graph reads it by handing it on rather than by asking it. So the port holds the URL it
was made from and nothing else answers publicly.

| member | release | what the port does |
| --- | --- | --- |
| `-initWithURL:` | 11.3 | holds the URL, and answers `nil` when given none — the failure the header's nullable return already documents |
| `-initWithURL:ownershipToken:` | 13.0 | holds the URL and the token, and answers `nil` for a missing URL |
| `-init`, `+new` | 11.3 | **not bound** — the header marks both `NS_UNAVAILABLE`, so a call to either does not compile against the release |

**One object per release, and what that cost.** `-initWithURL:` and
`-initWithURL:ownershipToken:` are API of two releases, and the gate refuses an object carrying the API
of two, so they are two objects: `HMAccessorySetupPayload11_3.m` and
`HMAccessorySetupPayload13_0.m`. The cache ladder decides which a band links — the 11.3 object for 11.3
and 12.0, both from 13.0 up. The 13.0 object therefore reads the 11.3 object's own storage, and it does
so with `@dynamic`, not a second `@synthesize`: a second synthesis of a property another object of the
same class already synthesises is a duplicate definition, and auto-synthesis would have satisfied the
flag by creating a *second* ivar — two payloads' worth of URL in one binary, with the 13.0
initialiser's URL invisible to the 11.3 object's getter.

## `HMAccessoryOwnershipToken` — 13.0, **not carried**

The header's `-[HMAccessoryOwnershipToken initWithData:]` makes a token from data "to be sent to prove
ownership of this accessory", and the header itself says it may return `nil` if the data is too short or
otherwise insufficient. Making one is the accessory's and the daemon's business: it is proved against
hardware. The port therefore does not carry the class, and the 13.0 payload initialiser holds the token
**opaquely** — the SDK's own type, read only for its presence. Copying its bytes or inspecting what is
inside would claim a check the port never made.

## What a device does that this port does not

- **Reading the payload.** A real device reads the setup code's bytes and the accessory's identity out
  of it. The port never opens the URL, re-encodes it, or resolves it.
- **Proving ownership.** With a token, the device checks it before adding the accessory; without one it
  adds on the strength of the setup code alone. The port records which of the two a payload carries and
  verifies neither.
- **Adding the accessory.** `-[HMHome addAndSetupAccessoriesWithPayload:completionHandler:]` is the
  home's side of it and is a separate row; it needs a HomeKit daemon to add an accessory to and a
  transport to reach it with, and this port has neither.
