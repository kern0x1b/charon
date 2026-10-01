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
said CoreNFC is in no shared cache this package holds. It is.

**The command.** From the repository root, with no xmake project and no gate:

```
CHARON_ROOT="$PWD" xmake l tools/corpus/cache-census.lua NFC
```

`tools/corpus/cache-census.lua` reads each named release's cache with
`modules/apple/objc.lua`'s `inventory`, prints the images, classes and protocols
it carries that name the prefix, and prints a control in the same run: if no
rung read found a name, it prints `CONTROL FAILED` and the run certifies
nothing. Its output, in full, the three defaults being the two releases this
package deploys on and the first rung that carries CoreNFC. The two long lines
are cut here at their class and protocol names:

```
6.1.3     $HOME/.charon/dyld/6.1.3/dyld_shared_cache_armv7
         images 524, of which naming NFC 0
         classes 11378, of which NFC* 0
         protocols 1171, of which NFC* 0
4.3       $HOME/.charon/dyld/4.3/dyld_shared_cache_armv7
         images 354, of which naming NFC 0
         classes 7187, of which NFC* 0
         protocols 564, of which NFC* 0
11.0      $HOME/.charon/dyld/11.0/dyld_shared_cache_arm64
         images 1258, of which naming NFC 1
         classes 52768, of which NFC* 34 (NFCError NFCHardwareManager ... NFCurrency)
         protocols 8954, of which NFC* 11 (NFCHardwareManagerCallbacks ... NFContactlessUICCSessionInterface)
control: 45 name(s) beginning NFC found in this run, so a zero on another rung
is the release's and not the reader's
```

The 34 and the 11 are the control, and they are what makes the two zeros mean
anything: the same reader, the same run, the same prefix. `objc-inventory.lua`
answers the same question for one cache at a time and is the tool behind it.

| held cache | what it carries of CoreNFC |
| --- | --- |
| **6.1.3 armv7** (deployment) | 0 of 524 images name NFC; 0 of 11378 classes and 0 of 1171 protocols begin with `NFC` |
| **4.3 armv7** (deployment) | 0 of 354 images; 0 of 7187 classes and 0 of 564 protocols |
| 11.0 arm64 | 1 of 1258 images is `CoreNFC.framework`, **34** `NFC*` classes and 11 `NFC*` protocols |
| 16.0 arm64e | as 11.0, and the two delegate protocols among them |

Every count in the table is a line of the command above.

12.0's arm64 cache carries no CoreNFC either, which is that cache's own state
and not this port's; `tools/cache-index/first-rung.py` reads the same rungs and
the same answer (`NFCReaderSession` at 11.0, 16.0, 18.0 and at no other held
rung), by a different reader again - the whole symbol table rather than the
Objective-C metadata - which is why the two agree. The command, and its control:

```
python3 tools/cache-index/first-rung.py --self-test          # 8 of 8, the checks that mean the rest
python3 tools/cache-index/first-rung.py --rungs NFCReaderSession
python3 tools/cache-index/first-rung.py _NFCISO15693TagResponseErrorKey
```

The last two print `NFCReaderSession  11.0,16.0,18.0` and
`_NFCISO15693TagResponseErrorKey  11.0`. A C symbol needs its leading
underscore: the bare name answers `NONE` at every rung, which is the tool being
literal about a name no image holds under it.

16.0 and 18.0 are held as **arm64e** and at no other architecture, 11.0 and 12.0
as arm64; the census picks each release's architecture through
`dyld.held_ladder` and prints the cache it read, so the split is visible in the
output rather than something to remember.

The two delegate protocols, `NFCReaderSessionDelegate` and
`NFCNDEFReaderSessionDelegate`, are a second fact the caches give and the headers
do not: **neither is a protocol in 11.0's or 12.0's cache**, where
`NFCReaderSession` and `NFCTag` are both class and protocol, and both first
appear as protocols in 16.0's arm64e cache. `NFCReaderSession` is the name of a
class *and* of a protocol in 11.0 and 16.0. Read with

```
CHARON_ROOT="$PWD" xmake l tools/corpus/objc-inventory.lua \
    "$HOME/.charon/dyld/11.0/dyld_shared_cache_arm64" \
  | grep -E '^(class|protocol)[[:space:]]+(NFCReaderSession|NFCNDEFReaderSession|NFCReaderSessionDelegate|NFCNDEFReaderSessionDelegate)[[:space:]]'
```

which prints three lines and no fourth, the absence being the result:

```
class	NFCNDEFReaderSession
class	NFCReaderSession
protocol	NFCReaderSession
```

Neither delegate appears as a `protocol` line: the SDK header declares both, and
11.0's own binary carries no metadata for either.

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
first is never misled and an unchecked call raises. The run, and the command:

```
PROBES_BUILD="$PWD/.agent-work/runs/probes" FLEET_HEAVY_LANE=fast \
    $HOME/Git/projects/ios/coordination/heavy.sh sh tests/backports/host/probes/run.sh
```

which ends `0 of 64 checks failed` and writes the per-check log to the path it
prints. That same run has `+readingAvailable` answer NO on both classes, agrees
with the host's answer, and finds `NFCErrorDomain` to be `NFCError`. Implementing
`-beginSession` in the port's own source makes the run report
`FAIL beginSession is absent from a reader session` and 1 of 64, so the check
bites rather than passing by construction.

`ready` is the one member whose spelling differs from the cache: 11.0's
`NFCReaderSession` carries `-isReady` and no `-ready`, the property's own
getter. The row keeps the SDK's spelling.

### What the five members would have to answer, and why they are absent rather than stubs

The host's `NFCReaderSession` carries all five, and a stub that implemented them
could have been written from its own method list. It is not written, and the
reason is measured rather than a matter of taste: **every one of the five needs a
session, and the host's initializer answers `nil`** (the section above), so on
this hardware there is no object on which `-beginSession` could do anything.
`-beginSession` on a stub would be a method that begins nothing and reports
`ready` as never true; `ready` on a stub would answer a question about a radio
that does not exist. That is the trap the tree calls a fabricated seam, and it is
why these rows say the accessor is undeclared instead.

The member list below is what the port's own library does NOT answer, printed from
the host's class so the comparison is against a real one:

```
host NFCReaderSession carries: -isReady -sessionId -isInvalidated -delegate
  -sessionQueue -sessionType -invalidateSession -alertMessage -setAlertMessage:
  -beginSession ... (58 instance methods, 2 class methods: +featureAvailable: +readingAvailable)
responds: ready=0 isReady=1 delegate=1 setDelegate=0 sessionQueue=1 alertMessage=1 begin=1 invalidate=1
```

Two things in that are load-bearing for the rows:

- **`ready=0` and `isReady=1`** — the property's getter is `-isReady`, and the port
  declares neither, so the row's `effect` says the accessor is not declared and a
  caller that checks `respondsToSelector:` first is told the truth.
- **`setDelegate=0`** — the host has `-delegate` but **no** `-setDelegate:`, so the
  delegate is set at initialization and never afterwards. A port that added
  `-setDelegate:` would be adding API the framework does not have.

The command is `class_copyMethodList` over the host's class through Mac Catalyst,
which is the same reader the run above uses; the port's own half of each comparison
is the six `ok` lines the probes run prints.

`NSUserActivity.ndefMessagePayload` is absent for a different reason and is not
one of the session's own rows: `Foundation/NSUserActivity.m` of this package
**implements NSUserActivity itself**, and its declared surface has no
`ndefMessagePayload`, so the obstacle was the port's own owner and not a radio.
Two commands check both halves of that row:

```
grep -c ndefMessagePayload packages/a/apple-backports/Foundation/NSUserActivity.m   # 0
python3 tools/cache-index/first-rung.py ndefMessagePayload                          # 16.0
```

The first is 0, which is the owner; the second is the first held rung with the
name, and 12.0 - the `introduced` the row carries - is not among them.

## What a device without NFC does when a session is started anyway — measured, and the oracle is the host

**The paragraph this file carried here before 2026-10-01 was wrong.** It said this was
not measured, because there is no `NFCNDEFReaderSession` on the device or in any held
cache to ask. That is true of the *device* and false of the machine: **the host's
CoreNFC answers, and it is in exactly the state this port is in** — its
`+readingAvailable` is NO, which is the same answer the port gives and the same
answer an iPhone 4S gives. So the host answers what a session does when reading is
unavailable, which is the question.

```
xcrun clang -fobjc-arc -w -target arm64-apple-ios15.0-macabi \
    -isysroot "$(xcrun --show-sdk-path)" \
    -iframework "$(xcrun --show-sdk-path)/System/iOSSupport/System/Library/Frameworks" \
    s.m -framework CoreNFC -framework Foundation -o s && ./s
```

Its output, in full:

```
readingAvailable=0
creating a session anyway...
  initializer returned: nil
```

**The initializer answers `nil`; it does not raise, and it does not make an object
that is then not ready.** A delegate is never called, because there is no session to
call one on. Three further paths were asked, because an answer that held for one
call would not be enough to write a row on:

| asked | host answers |
| --- | --- |
| `-initWithDelegate:queue:invalidateAfterFirstRead:` with a real delegate and a nil queue | **nil** |
| the same with a `nil` delegate | **nil** |
| the same with a serial queue instead of nil | **nil** |
| `-[NFCISO15693ReaderSession initWithDelegate:queue:]` | **nil** |
| `+readingAvailable` on the subclass, and on the ISO15693 session | NO |

So a caller that starts a session anyway gets `nil` from every initializer, on every
session class, and no exception. That is the answer a device without the radio gives,
and it is why the initializer rows stay absent rather than becoming a stub that hands
back a session which could never become ready: a stub would answer *an object*, where
the system answers **nil**, and an application written against the real framework
checks for nil.

The initializer rows are honest about this rather than merely unimplemented: the
caller gets nil, which is the system's own answer for this hardware, and the row says
so.
