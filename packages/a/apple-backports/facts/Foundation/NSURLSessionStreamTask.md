# The stream task, iOS 9.0, over the release's own stream pair

`NSURLSessionStreamTask` with its seven methods, the two factories that make one, the two `NSStream`
factories they are built on, and the four `NSURLSessionStreamDelegate` callbacks.

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
completion handlers, the secure connection, and the four delegate callbacks -- the read side closing,
the write side closing, a better route, and the streams being handed over. Each callback is called only
when the session's delegate answers to it, which is what the header's protocol is for.

`-init` and `+new` are **not** carried. The header deprecates them both with "please use
`-streamTaskWithHostName:port:` or other NSURLSession methods to create instances", and the reason is
the port's too: a stream task is a connection, and a connection is a host and a port.

`-stopSecureConnection` is carried and does nothing to a connection that has TLS, because TLS cannot be
taken off a connection once it is on -- which is the header's own reason for deprecating it.

## One divergence, written down

A stream task made here is **not** in the session's `-getTasksWithCompletionHandler:` list. The port's
session keeps that list in its own storage and `NSURLSession+StreamTask9.m` is a category beside it, so
that method answers the data, upload and download tasks and no stream task. The task is otherwise the
port's own: it opens the pair when it is resumed, reads and writes on the resuming thread's run loop,
and calls the delegate. Carrying the stream task inside the session's own implementation, so that
`-getTasksWithCompletionHandler:` and `-invalidateAndCancel` see it, is the change that closes this.

## A known open defect: this object mixes two releases

`xmake l tools/release-split.lua <objects>` over the compiled objects of this delivery says, with its
own words:

    release-split: 1 file(s) mix more than one release's symbols: NSURLSessionStreamTask9.o
    NSURLSessionStreamTask9.o  MIXED-RELEASES  9.0,none

The two are `_OBJC_CLASS_$_NSURLSessionStreamTask`, which a release exports from **9.0**, and
`_OBJC_CLASS_$_CharonStreamTaskState`, which **no release exports at all** because it is this port's
own. The registry is right about the first (`maximum: 8.4.1`, so the object leaves the band before
9.0) and the second has no entry because it is not an API.

The fix the tool wants is one object per release group, which for this file means moving
`CharonStreamTaskState` into an object of its own. Splitting it that way was attempted and the split
object did not compile (`unknown type name 'NSURLSessionStreamTaskState'` from the task file, with the
declaration visibly present), and the cause was not found before the round ended. So the defect is
recorded here instead of being quietly left: **the gate will name this file**, and the fix is to move
the state class to its own file and declare it through a local `CharonStreamTaskState.h`.

The other twenty objects of this delivery pass the same check: the run names one file and it is this
one.
