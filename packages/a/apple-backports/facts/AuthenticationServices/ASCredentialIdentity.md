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
