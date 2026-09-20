# NFCReaderSession and NFCNDEFReaderSession, iOS 11.0

Introduced in iOS 11.0: the session an application opens to read a tag. What an
application asks before it opens one is whether the device can read tags at all,
`+readingAvailable`, and that is what is carried.

Source, and what was and was not measured: this is **documented contract** and a
measurement on the host, not a reading of the release. CoreNFC is in no shared
cache this package holds - not the iPod touch of iOS 11.0 and not the arm64 cache
of 12.0 - so no code of the release was read. The SDK 16.4 header
`NFCReaderSession.h` declares `+readingAvailable` as available from iOS 11.0,
and its text says YES if the device supports NFC tag reading. The host's CoreNFC
through Mac Catalyst answers NO for it on both classes, and gives
`NFCErrorDomain` the value `NFCError`; there `NFCNDEFReaderSession` is a
subclass of `NFCReaderSession`.

## What is carried

- `+[NFCReaderSession readingAvailable]` and, by inheritance,
  `+[NFCNDEFReaderSession readingAvailable]` answer **NO**. The iPhone 4S and the
  iPad 2 have no NFC hardware, so the answer is the one a device without it
  gives, and an application that asks first never starts a session.
- `NFCErrorDomain` is `NFCError`.
- `NFCReaderSession` adopts the protocol of the same name, and `NFCNDEFReaderSession`
  is its subclass, as on the host.

## What is absent, and why

The session itself - its designated initializer, `-beginSession`,
`-invalidateSession`, the delegate, the queue, the alert message and whether it
is ready - the message and the payload of a tag, and the two delegate protocols.
The release has no NFC hardware and no reader daemon to open a session with.
`respondsToSelector:` answers no and an unchecked call raises.

What a device without NFC does when an application starts a session anyway -
whether the initializer answers `nil` or the delegate hears
`NFCReaderErrorUnsupportedFeature` - has not been measured, and this package does
not guess at it: the initializer is absent until it is.
