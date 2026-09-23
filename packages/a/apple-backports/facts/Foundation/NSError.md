# NSError, the user info key of iOS 11.0

`NSLocalizedFailureErrorKey` (the string `NSLocalizedFailure`) arrived in iOS
11.0: a sentence naming what failed, which `-localizedDescription` puts in front
of the reason.

Source: the host's Foundation.

## Behaviour

With both keys, `-localizedDescription` is the failure and the failure reason
joined by a space: `The file could not be saved. The disk is full.` With the
failure alone, the reason is the one the release generates for the domain and
code, so `NSCocoaErrorDomain` `4` reads `Only the failure. The file doesn't
exist.` `NSLocalizedDescriptionKey`, when present, wins over both.

## What the port carries

The key itself: `NSLocalizedFailureErrorKey` is exported under its own string,
`NSLocalizedFailure`, from `Foundation/NSLocalizedFailureErrorKey.m`. Without it
an application that names the key does not get a poorer message, it gets no
key at all: a strong import is a missing symbol and dyld stops the application
at launch (Delta imports it that way), and a weak import reads `NULL`, which
`userInfo` literals then insert as a nil key and throw.

## What it does not honour

Honouring the key means changing what `-localizedDescription` returns, a method
every release already has. The attachment mechanism adds only what a class does
not answer, and the port does not replace system implementations. An error that
carries the key on iOS 6 gets a `-localizedDescription` that ignores it: the
message is the release's own, the sentence naming the failure is lost, nothing
fails, and nothing says so. The registry records this as `ignored`.
