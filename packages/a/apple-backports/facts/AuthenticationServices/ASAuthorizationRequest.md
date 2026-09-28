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

## Why `port_has` did not see `-init`, and what it reads

It was asked, and here is what it said. The diagnostic read
`packages/a/apple-backports/AuthenticationServices/ASWebAuthenticationSession.m` — **7231 bytes on
disk, 7231 read**, so the file was not short and not unreadable — found `@implementation
ASWebAuthenticationSession` at offset 3374, and then searched for:

    - (init)

**which no Objective-C method has**, because the return type sits between the parens. Every port-side
answer from that tool was "no" whatever the tree held: the classes it reported as missing were missing
to the search, not to the port. The one real difference it did report — the missing
`-[ASWebAuthenticationSession init]` — came out right for the wrong reason, and the `-init` was added on
the strength of a report the tool could not be trusted to make.

The first correction allowed a space between the sign and the paren and then required the paren to be
the very next character, which `- (instancetype)init` does not have either, so the second run was still
green in the wrong direction. What works is where a declaration puts the selector: a `-` or `+`, optional
space, `(`, the return type, `)`, optional space, and then the member name with a non-identifier after
it — so that `charon_initWithProvider:` is not read as `provider`, which is the next false positive the
prefix form would have given.

    ASWebAuthenticationSession   init                                            yes yes same
    ASAuthorizationRequest      provider                                       yes yes same
    ASAuthorizationRequest      copyWithZone:                                   yes yes same
    ASAuthorizationRequest      encodeWithCoder:                                yes yes same
    shapes: 4 cases, 0 differences

and the mutant, with the base request's `-provider` and its `@synthesize` removed from a copy:

    ASAuthorizationRequest      provider                                       yes no  the port is missing it
    the check exited 1, which is what a check that can see a removed member does

## The member list comes from the header, and a class with no header is an error

The first version kept a table here of which members to ask each class about, and a class missing from
it was asked `init` alone and passed — a check that compares what it happens to have been told to. There
is no table now. The list is parsed at run time out of the framework's own headers, in the SDK the
build compiles against, and **a class the registry carries whose header cannot be found stops the run
and is named**. Asking the host for everything it has instead would ask about the release's private
methods — `initWithProvider:`, `supportsStyle:` — which are not claims and not in the headers.

That widened the questions from four hand-listed members to the seven the two headers declare, and the
run is **red on two of them**, which is the point of the change:

    ASAuthorizationRequest  new                        no  yes  the port adds it
    ASAuthorizationRequest  init                       yes yes  same
    ASAuthorizationRequest  copyWithZone:              yes yes  same
    ASAuthorizationRequest  encodeWithCoder:           yes yes  same
    ASAuthorizationRequest  initWithCoder:             yes yes  same
    ASWebAuthenticationSession  initWithURL:           no  yes  the port adds it
    ASWebAuthenticationSession  start                  yes yes  same
    ASWebAuthenticationSession  cancel                 yes yes  same
    ASWebAuthenticationSession  new                    no  no   same
    ASWebAuthenticationSession  init                   yes yes  same

`ASAuthorizationRequest new` is a defect in `port_has` and not a finding: the source has no `+new` and
no `- (…)new`, and the check reports one. Diagnosed as far as "reports a selector the file does not
contain"; the cause is not yet known and is the next thing to look at, because a matcher that invents a
selector is worse than one that misses one. `ASWebAuthenticationSession initWithURL:` is the same
pattern — a short selector the port has and the check does not see — and the host's answer of "no" for
both is itself suspicious, since a host that answers "no" to a class method the header declares is more
likely the tool's host side than the framework.

**So the gap is closed and the check is red.** It is committed red, with the two cases named, rather
than committed green on the four members the old table happened to list.

## What is not done

578 rows. The value half of the family is measured (30 constants, 30 agree with the host) and the shape
half has a host differential and a mutant; the classes do not exist yet. The differential is currently
**red** on one case — `-[ASWebAuthenticationSession init]`, which the host has and the port's source did
not, and which has since been added — and that red has not been cleared, so the check is committed in a
state its own report says is failing rather than in a state that says `ok`.
