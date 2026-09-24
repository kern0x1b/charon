# NSError, the user info key of iOS 11.0

`NSLocalizedFailureErrorKey` (the string `NSLocalizedFailure`) arrived in iOS
11.0: a sentence naming what failed, which `-localizedDescription` puts in front
of the reason.

Source: the host's Foundation.

## Behaviour

iOS 11 builds `-localizedDescription` in this order (`NSError.h`): the
`NSLocalizedDescriptionKey` of the user info as it is; the failure of the user
info, followed by the reason; the provider's description
(`+setUserInfoValueProviderForDomain:provider:`); the provider's failure,
followed by the reason; then what the releases before did (the reason with a
generic sentence, or a string made from the domain and code). The reason is
`-localizedFailureReason`: the user info's, then the provider's, then the one
the release generates for the domain and code. Failure and reason are joined by
a space.

Measured on the host's Foundation:

- failure and reason: `The file could not be saved. The disk is full.`;
- the failure alone, domain `charon`: `Only the failure.`;
- the failure alone, `NSCocoaErrorDomain` `4`: `Only the failure. The file
  doesn’t exist.` (the reason the release generates);
- with `NSLocalizedDescriptionKey` as well: that description;
- an error made by `CFErrorCreate` with failure and reason: the same sentence as
  the first, from `-localizedDescription` and from `CFErrorCopyDescription`;
- a provider answering a description, a failure and a reason: the failure of the
  user info with the provider's reason (`Own failure. Provided reason.`) wins
  over the provider's description; the provider's description wins over its
  failure; the provider's failure takes the reason of the user info when there
  is one, and stands alone when nothing gives a reason.

## What the port carries

The key, exported under its own string `NSLocalizedFailure`, and what iOS 11
does with it: `Foundation/NSLocalizedFailureErrorKey.m` wraps `-[NSError
localizedDescription]` on a release whose Foundation does not export the key
(`dlsym` on the loaded Foundation) and answers the two failure steps above,
leaving the others to the release. Below iOS 9 the provider's steps are
`NSError+UserInfoValueProvider.m`'s wrapper, installed from `+load`; the failure
wrapper has to sit outside it, since the failure of the user info comes before
the provider's description, so it is installed from a constructor, which runs
after every `+load` of the library.

Without the key an application that names it does not get a poorer message, it
gets no key at all: a strong import is a missing symbol and dyld stops the
application at launch (Delta imports it that way), and a weak import reads
`NULL`.
