# NFCReaderSession and NFCNDEFReaderSession, iOS 11.0

Introduced in iOS 11.0: the session an application opens to read a tag. What an
application asks before it opens one is whether the device can read tags at all,
`+readingAvailable`, and that is what is carried.

Source, and what was measured: the SDK 16.4 header `NFCReaderSession.h`
declares `+readingAvailable` as available from iOS 11.0, and its text says YES
if the device supports NFC tag reading. The host's CoreNFC through Mac Catalyst
answers NO for it on both classes, and gives `NFCErrorDomain` the value
`NFCError`; there `NFCNDEFReaderSession` is a subclass of `NFCReaderSession`.

**The release caches were read, and the previous statement here was wrong.** It
said CoreNFC is in no shared cache this package holds. It is, and
`modules/apple/objc.lua`'s `inventory` reads it there:

| held cache | what it carries of CoreNFC |
| --- | --- |
| **6.1.3 armv7** (deployment) | 0 of 524 images name CoreNFC; 0 of 11378 classes and 0 of 1171 protocols begin with `NFC` |
| **4.3 armv7** (deployment) | 0 of 354 images; 0 of 7187 classes and 0 of 564 protocols |
| 11.0 arm64 | the CoreNFC image, **34** `NFC*` classes and 11 `NFC*` protocols |
| 16.0 arm64e | as 11.0, and the two delegate protocols among them |

The 11.0 and 16.0 rows are the control that makes the two deployment rows mean
anything: the same reader that finds 34 `NFC*` classes in 11.0 finds none in
6.1.3, so the absence is the release's and not the reader's. 12.0's arm64 cache
carries no CoreNFC either, which is that cache's own state and not this port's;
`tools/cache-index/first-rung.py` reads the same three rungs and the same answer
(`NFCReaderSession` at 11.0, 16.0, 18.0 and at no other held rung).

16.0 and 18.0 are held as **arm64e** and at no other architecture, 11.0 and 12.0
as arm64; an answer read from either rests on that architecture's slice.

The two delegate protocols, `NFCReaderSessionDelegate` and
`NFCNDEFReaderSessionDelegate`, are a second fact the caches give and the headers
do not: **neither is a protocol in 11.0's or 12.0's cache**, where
`NFCReaderSession` and `NFCTag` are both class and protocol, and both first
appear as protocols in 16.0's arm64e cache. `NFCReaderSession` is the name of a
class *and* of a protocol in 11.0 and 16.0.

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
is ready - and the two delegate protocols. The deployment caches above hold no
CoreNFC at all, so there is no session for any of them to be an attribute of.
That each is honestly absent is measured, not asserted:
`tests/backports/host/probes/differential.m` builds the port's own
`Foundation/NFCReaderSession.m` for Mac Catalyst, and against the host's real
CoreNFC answers

    ok beginSession is absent from a reader session
    ok invalidateSession is absent from a reader session
    ok delegate is absent from a reader session
    ok sessionQueue is absent from a reader session
    ok alertMessage is absent from a reader session
    ok a session cannot be made

that is `instancesRespondToSelector:` answering NO for all five accessors and for
`-initWithDelegate:queue:invalidateAfterFirstRead:`, so a program that checks
first is never misled and an unchecked call raises. The same run has
`+readingAvailable` answer NO on both classes, agrees with the host's answer, and
finds `NFCErrorDomain` to be `NFCError`: 0 of 64 checks failed. Implementing
`-beginSession` in the port's own source makes the run report
`FAIL beginSession is absent from a reader session` and 1 of 64, so the check
bites rather than passing by construction.

`ready` is the one member whose spelling differs from the cache: 11.0's
`NFCReaderSession` carries `-isReady` and no `-ready`, the property's own
getter. The row keeps the SDK's spelling.

What a device without NFC does when an application starts a session anyway -
whether the initializer answers `nil` or the delegate hears
`NFCReaderErrorUnsupportedFeature` - is still not measured: there is no
`NFCNDEFReaderSession` to ask, on the device or in any held cache, so no oracle
answers it. The initializer stays absent until one does.
