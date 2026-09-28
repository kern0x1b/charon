# ASAuthorizationRequest, iOS 13.0

The base every request in AuthenticationServices is, and therefore the template the rest of this family
is written in: a subclass adds two or three members and nothing else, and what it inherits is a
provider, a copy and a coder.

## What the host says, measured

macOS 27.0's own `AuthenticationServices.framework` has the class, and `tests/backports/host/authservices`
asks it with `dlopen` and `class_getInstanceMethod` for each member. The class list holds eight instance
methods:

    provider   initWithProvider:   initWithCoder:   init
    .cxx_destruct   copyWithZone:   encodeWithCoder:   supportsStyle:

`-provider` and the three `NSCopying`/`NSSecureCoding` members are the public contract; `initWithProvider:`
is the release's own way in and is not in the public header, so the port does not reach for it — the port's
construction is named and declared in `CharonASConstruction.h`, which is the same mechanism HomeKit's
graph uses and for the same reason.

## The parts that are decided, and how

- **`-provider` is a strong reference and is kept as one.** It is what the controller asks when it runs
  the request; a request that outlived its provider would be a request nothing can service.
- **`+supportsSecureCoding` answers NO.** A provider is an object the caller supplies and the release
  does not document it as archivable; the port writes the provider under its own key and reads it back
  only when the coder can produce an object, so a round trip of a request without a provider gives a
  request without one rather than pretending.
- **A copy is the same request with the same provider**, and a subclass copies what it adds — the base
  copies only what the base holds.

## The census this is the first of

`tools/verify.py` over the 26.2 AuthenticationServices surface, against a registry export of this tree:

    613 objc rows -> 582 real work, 31 carried by the registry

582 is the whole family. This class is the first of them, and the next ones are its subclasses.

## What is not done

579 rows. The value half of the family is measured (30 constants, 30 agree with the host) and the shape
half has a host differential and a mutant; the classes do not exist yet. The differential is currently
**red** on one case — `-[ASWebAuthenticationSession init]`, which the host has and the port's source did
not, and which has since been added — and that red has not been cleared, so the check is committed in a
state its own report says is failing rather than in a state that says `ok`.
