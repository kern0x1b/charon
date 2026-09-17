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

## Why the port does not carry it

The key is a string, and honouring it means changing what
`-localizedDescription` returns — a method every release already has. The
attachment mechanism adds only what a class does not answer, and the port does
not replace system implementations. An application that puts the key in
`userInfo` on iOS 6 gets an error whose `-localizedDescription` ignores it: the
message is poorer, nothing fails, and nothing says so. The registry records this
as `ignored`.
