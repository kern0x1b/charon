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

## The object is split, because the release ladder says it has to be

`xmake l tools/release-split.lua <objects>` over the compiled objects of this delivery named

    release-split: 1 file(s) mix more than one release's symbols: NSURLSessionStreamTask9.o
    NSURLSessionStreamTask9.o  MIXED-RELEASES  9.0,none

because that object held the task's own class -- which a release exports from **9.0** -- and the state
class beside it, which **no release exports at all**. The state class is now in an object of its own
(`CharonStreamTaskState.m`, declared in `CharonStreamTaskState.h`), so each object holds one release
group, and the same command over the same objects now names no file.
