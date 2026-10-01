# The stream task, iOS 9.0, over the release's own stream pair

`NSURLSessionStreamTask` with its seven methods, the two factories that make one, the two `NSStream`
factories they are built on, and three of the four `NSURLSessionStreamDelegate` callbacks -- the fourth
is declared and never sent, and the section below says why and what was measured about it.

## The connection is the release's own, not ours

`+[NSStream getStreamsToHostWithName:port:inputStream:outputStream:]` is
`CFStreamCreatePairWithSocketToHost` and the two halves are bridged into the two stream classes, which
is what iOS 8's own header documents. Measured on the release with
`tools/corpus/cache-value.lua` over the 6.1.3 armv7 cache:

| symbol | the image of 6.1.3 that exports it |
| --- | --- |
| `CFStreamCreatePairWithSocketToHost` | CoreFoundation |
| `CFStreamCreatePairWithSocket` | CoreFoundation |
| `CFStreamCreateBoundPair` | CoreFoundation |
| `CFReadStreamSetProperty`, `CFWriteStreamSetProperty` | CoreFoundation |
| `kCFStreamPropertySocketNativeHandle` | CoreFoundation |
| `kCFStreamPropertySSLContext` | CFNetwork |

Every one of them is public and declared in the SDK's own `CFStream.h` (the SSL context is CFNetwork's,
and CFNetwork.framework is in the iOS SDK). So the resolution, the socket, the buffering, the timeouts
and the native handle are the system's; nothing here reimplements a stream.

`+[NSStream getBoundStreamsWithBufferSize:inputStream:outputStream:]` is guarded to macOS by the 26.2
header and is named by the iOS surface, so it is carried: the release exports the function, and a pair
bound to a port is what the method promises.

## What the task adds

The task's own bookkeeping: the two streams, the half-closes, the read and the write with their
completion handlers, the secure connection, and three of the four delegate callbacks -- the read side
closing, the write side closing, and the streams being handed over. Each is sent only when the session's
delegate answers to that selector, which is what the header's `@optional` protocol is for, and each goes
on the session's delegate queue where the session has one.

`-init` is carried and `+new` is not. The header **deprecates** both with "please use
`-streamTaskWithHostName:port:` or other NSURLSession methods to create instances", and a deprecation
is a warning rather than a refusal: the port answers `-init`, which is what the release's own
`-[NSURLSessionTask init]` does, and `NSURLSessionStreamTask9.m` calls it from its own factory. The
registry says the same thing — `-[NSURLSessionStreamTask init]` is `implemented` with that reason, and
`+[NSURLSessionStreamTask new]` is `absent` because the port does not define a `+new` that bypasses
the factory. What an application should do is what the header says: ask the session for the task.

`-stopSecureConnection` is carried and does nothing to a connection that has TLS, because TLS cannot be
taken off a connection once it is on -- which is the header's own reason for deprecating it.

## The four delegate callbacks: what the release carries, and which three are sent

The four rows are `absent` for the three that are sent and `inert` for the one that is not, and the two
are different claims, so they are measured separately.

**What the release carries.** From the repository root, with no xmake project and no gate:

```
CHARON_ROOT="$PWD" xmake l tools/corpus/cache-census.lua NSURLSessionStream 6.1.3 4.3 11.0
```

Its output, in full:

```
6.1.3     $HOME/.charon/dyld/6.1.3/dyld_shared_cache_armv7
         images 524, of which naming NSURLSessionStream 0
         classes 11378, of which NSURLSessionStream* 0
         protocols 1171, of which NSURLSessionStream* 0
4.3       $HOME/.charon/dyld/4.3/dyld_shared_cache_armv7
         images 354, of which naming NSURLSessionStream 0
         classes 7187, of which NSURLSessionStream* 0
         protocols 564, of which NSURLSessionStream* 0
11.0      $HOME/.charon/dyld/11.0/dyld_shared_cache_arm64
         images 1258, of which naming NSURLSessionStream 0
         classes 52768, of which NSURLSessionStream* 2 (NSURLSessionStreamTask NSURLSessionStreamTaskTester)
         protocols 8954, of which NSURLSessionStream* 1 (NSURLSessionStreamDelegate)
control: 3 name(s) beginning NSURLSessionStream found in this run, so a zero on another rung
is the release's and not the reader's
```

The two zeros are the two releases this package deploys on, and the control is in the same run: the
same reader, the same prefix, 11.0 answering with the class, the tester class and the protocol. So
6.1.3 and 4.3 carry neither the class nor the protocol, and the four selectors go with them:

```
python3 tools/cache-index/first-rung.py NSURLSessionStreamDelegate \
    'URLSession:streamTask:didBecomeInputStream:outputStream:' 'URLSession:readClosedForStreamTask:' \
    'URLSession:writeClosedForStreamTask:' 'URLSession:betterRouteDiscoveredForStreamTask:'
NSURLSessionStreamDelegate	11.0
URLSession:streamTask:didBecomeInputStream:outputStream:	9.0
URLSession:readClosedForStreamTask:	9.0
URLSession:writeClosedForStreamTask:	9.0
URLSession:betterRouteDiscoveredForStreamTask:	9.0
```

That is presence, not a version: the four selectors are in 9.0's cache, and nothing before it carries
them. The SDK 26.2 surface (`coordination/corpus/sdk-26.2-surface.tsv`, lines 12576-12579) declares all
four at 9.0, which is the registry's own `introduced`.

**What the port sends.** Three of the four, and each one only when the delegate answers to that selector.
The two streams go over when the task is resumed and again when `-captureStreams` hands them over; the
read side is reported once, when the peer's end arrives -- the header's own case, the read side closing
and not this object being told to -- or when the application closes that half; the write side goes over
when `-closeWrite` closes it. The arguments are the ones the header's signatures name, at the indices
those signatures give them, on the session's delegate queue.

**The fourth is never sent, and this page used to say otherwise.** The port's library declares the
protocol, so the selector is in its image and `NSProtocolFromString` answers the name, and no call site
anywhere in the tree sends it. That is what `inert` says, and it is not the same claim as the other
three: the release *can* be asked about a route, and the row before said it could not, which was wrong.
Measured:

```
python3 tools/cache-index/first-rung.py _SCNetworkReachabilityCreateWithName _SCNetworkReachabilitySetCallback
_SCNetworkReachabilityCreateWithName	3.0
_SCNetworkReachabilitySetCallback	3.0
```

SystemConfiguration's reachability is in 6.1.3, and this same library already reads it -- `NSURLSession.m`
watches a task's host while that task waits for connectivity (`charon_task_when_connected`). What those
flags answer is whether the host is reachable and over which kind of interface. The header's message
says the *system* has determined that a better route to the host exists, and gives "a wi-fi interface
becoming available" as its example; a change in the flags is this port's own inference from a
reachability answer, and the header's own warning that a new task may still fail is what such a report
invites a caller to get wrong. So the message is not sent, and the decision is written down at the end
of `-startSecureConnection` in `Foundation/NSURLSessionStreamTask9.m`.

**What was not measured.** The three sends were not run on a device. `tests/backports/device/
foundation15batch.m`, which the four rows cited as the device call test until this revision, holds no
stream case at all -- it is `grep -c stream` zero -- so there is no device measurement of these four
messages and none is claimed. What is measured is the release side above, and the object: it compiles
for armv7 and `tools/release-split.lua` walks it clean.


## One divergence, written down

A stream task made here is **not** in the session's `-getTasksWithCompletionHandler:` list. The port's
session keeps that list in its own storage and `NSURLSession+StreamTask9.m` is a category beside it, so
that method answers the data, upload and download tasks and no stream task. The task is otherwise the
port's own: it opens the pair when it is resumed, reads and writes on the resuming thread's run loop,
and calls the delegate. Carrying the stream task inside the session's own implementation, so that
`-getTasksWithCompletionHandler:` and `-invalidateAndCancel` see it, is the change that closes this.

## The object is split, because the release ladder says it has to be

`xmake l tools/release-split.lua <objects>` over the compiled objects of this delivery named

    release-split: 1 file(s) mix more than one release's symbols: NSURLSessionStreamTask9.o
    NSURLSessionStreamTask9.o  MIXED-RELEASES  9.0,none

because that object held the task's own class -- which a release exports from **9.0** -- and the state
class beside it, which **no release exports at all**. The state class is now in an object of its own
(`CharonStreamTaskState.m`, declared in `CharonStreamTaskState.h`), so each object holds one release
group, and the same command over the same objects now names no file.

Run over the object this file's own changes produced, compiled with the tree's clang for
`armv7-apple-ios6.0` against the iPhoneOS 16.4 SDK, it prints the two symbols and one release:

```
xmake l tools/release-split.lua <objects> <out> <iPhoneOS16.4.sdk>
release-split: clean, every object file's symbols first-appear in one release (1 files, 2 symbols, 50 releases checked)
NSURLSessionStreamTask9.o	_OBJC_CLASS_$_NSURLSessionStreamTask	9.0
NSURLSessionStreamTask9.o	_OBJC_METACLASS_$_NSURLSessionStreamTask	9.0
```

One `.m` for release 9, and the API it defines is exactly that release's class. What the tool cannot
see, and what a reader has to check by hand here, is the methods: an Objective-C method implementation
is not an exported symbol, so the four callbacks, the seven task methods and the two factories are all
invisible to it, and this file is the record that they are one release's API together.

