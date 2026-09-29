# The credential identity types, of iOS 12.0

These are the values that name *what* a stored credential is for, as opposed to `ASCredentialIdentityStore`
which holds them. They are the first classes in this family that exist to be written down rather than
talked to a daemon, and the first that an application reads back after a relaunch.

## `ASCredentialServiceIdentifier`

Which service a credential is for, and whether that service is named by a domain or a URL. The type is
part of the value and not a detail: the same string typed as a domain and typed as a URL is a different
service, and the system will not match an identity stored against the wrong one. `-copyWithZone:` carries
both parts for that reason, and the coder carries both too.

This class does **not** mark its public designated initialiser unavailable — only plain `-init` is — so the
port keeps the release's own `-initWithIdentifier:type:` as it is. That is the opposite of the request
classes two commits back, and it is worth stating because the same construction is right in one place and
wrong in the other.

The port does not parse the string against RFC 1035 or RFC 1738. The release does not either: the header
says what the type *represents* and leaves the conformance to the application that stored it, and refusing
identities the system would have kept is the worse of the two mistakes available.

## What the two checks say about them

The **shape** check reads the members from the header with clang's AST and asks the host and the port
whether each is bound. The **value** check runs both builds and compares what a request holds. Neither of
them can see a class that is not asked about — which is how `ASCredentialServiceIdentifier` went unmeasured
for a round: its registry row said `absent` while the class was in the tree, so the case builder was given
six class names and the class was written but never asked about.

The builder now fails in **both** directions and both are proved:

    set the row to absent       -> these classes are DEFINED in the tree and the registry does not
                                   carry them as implemented, so they are not measured at all:
                                   ASCredentialServiceIdentifier          exit 1
    restored                    -> 8 class rows, 42 members from clang, 42 cases, 0 red   exit 0

and it prints what it was asked for and what it produced, per class, so a class that contributes nothing
is visible rather than inferred:

    ASAuthorization 4   ASAuthorizationAppleIDCredential 10   ASAuthorizationAppleIDProvider 2
    ASAuthorizationAppleIDRequest 2   ASAuthorizationOpenIDRequest 8   ASAuthorizationRequest 3
    ASCredentialServiceIdentifier 3   ASWebAuthenticationSession 10        8 class rows, 42 members

The per-*member* guard came with it: a class can produce a case and still lose members, which is the
other half of what was unexplained.

## The store, and the rule about the host's writing half

`ASCredentialIdentityStore` is the first class in this family with state behind it, and it is the one
where a differential could do real harm, so the rule is written here as well as enforced.

On a Mac these four methods change the **user's** AutoFill state:

    -saveCredentialIdentities:completion:
    -removeCredentialIdentities:completion:
    -removeAllCredentialIdentitiesWithCompletion:
    -replaceCredentialIdentitiesWithIdentities:completion:

A differential that called them to see what they return would be writing to the reviewer's passwords. So
the host side of this family is **read-only**: only
`-getCredentialIdentityStoreStateWithCompletion:`, and only because it asks the system what it already
holds. The writing half's behaviour is documented from the header, and the port's own save-then-query
runs against the port's own store, whose property list lives under `.agent-work/runs/` and never in
`~/Library`.

`tests/backports/host/authservices/host-write-guard.sh` greps the host probe for the four names before
anything is built and refuses to start if any of them appears, and `values.sh` runs it first. Before
this round's first run:

    saveCredentialIdentities                    values.m 0
    removeCredentialIdentities                  values.m 0
    replaceCredentialIdentitiesWithIdentities   values.m 0
    removeAllCredentialIdentities               values.m 0

and the port's own sources, which are the only place any of them is called: 5, 2, 2, 2.

## What the port's store does, and where it differs from the system one

A save replaces an identity already held — matched on the service identifier, the user and the record
identifier, and deliberately **not** on the rank, which is the order the system offers them in and not
part of what they are. A remove takes only the named records, because the header restricts that method
to a store that takes incremental updates and this one does.

`replaceCredentialIdentitiesWithIdentities:` is where the port deliberately differs, and the facts say
so rather than the code quietly: the header restricts it to a store that does **not** take incremental
updates, and this one does, so the port saves the new set as a superset and leaves anything not in it
alone. An application that expected the set to become exactly the array would be surprised. The
alternative — emptying the store to satisfy the letter of a method the header confines to the other kind
of store — would destroy the application's own records.

`-getCredentialIdentityStoreStateWithCompletion:` reports **enabled** and **incremental**, and that is
about the *application's* store, not the system's autofill database. There is no daemon behind this one
and nothing outside the process reads it, which is the honest answer for a port that has no system
credential store to ask.
