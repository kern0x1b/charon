# The two credential-provider classes, of iOS 12.0

Neither of these was hardware. `absent` is only for hardware that is physically not there, and a
*service* is not hardware: the release's own class is there, its methods are there, and an application
subclasses it. So both are carried, and what they cannot do is written down here rather than hidden in
an absent row.

## `ASCredentialProviderViewController`

A `UIViewController` subclass — the header says `ASViewController`, which is `UIViewController` where
UIKit exists — that a password-manager extension subclasses so the system can ask it for a credential.
The five members, all at `ios(12.0)`, and all read out of the header with clang's AST:

| member | what the base class does |
| --- | --- |
| `-prepareCredentialListForServiceIdentifiers:` | nothing — the header asks an *override* to prepare a list |
| `-prepareInterfaceToProvideCredentialForIdentity:` | nothing — the presentation is the system's |
| `-prepareInterfaceForExtensionConfiguration` | nothing — the settings screen is the extension's own |
| `-provideCredentialWithoutUserInteractionForIdentity:` | nothing — the system asks this only when its store already holds a matching credential, and the port has no store |
| `-extensionContext` | `nil` — there is no system-provided context, and standing in an object that cannot complete anything would be worse |

**A no-op default here is the base class behaving as a base class behaves, not a stub.** An extension
that overrides a member gets its own behaviour; one that overrides none gets the release's own answer,
which is also nothing. What the port will not do is invent a credential the extension never said it
had, or a settings screen the extension did not write.

## `ASCredentialProviderExtensionContext`

An `NSExtensionContext` subclass whose completion methods an extension calls when it has a credential.
The port carries them through a path of its own that **records** the completion, so that the host
application can read what the extension decided — which is the part a device gets from the system and
the port has to hold itself.

## What a device does that the port cannot

- **The AutoFill presentation.** The system shows this controller inside its own UI, and the
  identities on offer come from the system's credential-identity store.
- **That store.** The port's own controller would offer the identities the application's own store
  recorded, which is a different thing from the system's, and saying otherwise would be the lie this
  whole arrangement exists to prevent.

**And the machine's own store is never touched.** The same two halves stand here as for the value
differential: the static scan `tests/backports/host/authservices/writing-selectors-scan.py`, which
requires every writing selector in a harness source to be inside the chokepoint or an allowlist line, and
the runtime refusal `port-store-selftest.m`, which asks the chokepoint's predicate about *this Mac's own*
`ASCredentialIdentityStore` class object and sends nothing. A provider extension that was measured by
asking the real store what it holds would be measured by writing to it.
