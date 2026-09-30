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

What a device without NFC does when an application starts a session anyway -
whether the initializer answers `nil` or the delegate hears
`NFCReaderErrorUnsupportedFeature` - is still not measured: there is no
`NFCNDEFReaderSession` to ask, on the device or in any held cache, so no oracle
answers it. The initializer stays absent until one does.
