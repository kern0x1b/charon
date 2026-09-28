# What it takes to close the eight, measured against the release

The eight rows that stay `absent` are the socket's and the TLS session's: the two header byte counts,
the two addresses, the two ports, the two negotiated TLS values. This is the work that closes six of
them, measured so that nothing here has to be re-derived.

## Every entry point is the release's own, and all eight of them are there

Measured with `tools/corpus/cache-value.lua` over the 6.1.3 armv7 cache
(`.agent-work/scope/tls-symbols.txt`):

| symbol | the image of 6.1.3 that exports it |
| --- | --- |
| `kCFStreamPropertySocketNativeHandle` | CoreFoundation |
| `kCFStreamPropertySSLContext` | CFNetwork |
| `SSLGetNegotiatedProtocolVersion` | Security |
| `SSLGetNegotiatedCipher` | Security |
| `SSLCreateContext`, `SSLSetIOFuncs`, `SSLHandshake` | Security |

So there is no wall on either half: the handle is a property of the release's own stream, and the
negotiated version and cipher are read out of the release's own TLS session through public
SecureTransport. The same measurement is what made the stream task itself possible
(`facts/Foundation/NSURLSessionStreamTask.md`).

## The work, in the order that can be verified cheapest first

1. **The socket half, four rows, no certificate needed.** In `NSURLSessionStreamTask9.m`, once
   `-[NSURLSessionStreamTask charon_open]` has opened the pair, read
   `kCFStreamPropertySocketNativeHandle` off the *input* stream (`CFReadStreamCopyProperty` /
   `kCFStreamGetProperty`) and call `getsockname` and `getpeername` on the descriptor. Four rows
   become answerable and the test is cheap: a plain TCP listener the test opens, one stream task to it,
   and the port's answers against the host's own stream task's for the same connection.
2. **The delivery, which is the part that is real work.** Those numbers reach an application through
   `-[NSURLSessionTaskDelegate URLSession:task:didFinishCollectingMetrics:]`, and a stream task runs no
   loader, so nothing would call that method for it. The port's session already has the call site for
   a data task; a stream task needs the session to build an `NSURLSessionTaskMetrics` with **one**
   transaction when the task finishes -- both halves closed, or the task cancelled or invalidated -- and
   hand it to the delegate on the delegate queue, the way a data task's metrics arrive.
3. **The TLS half, two rows, needs a certificate in the test.** `-startSecureConnection` is what makes
   the release's stream carry an `SSLContext`; the two values are then `SSLGetNegotiatedProtocolVersion`
   and `SSLGetNegotiatedCipher` on it. A host test for this needs a TLS listener the test owns, which
   means a certificate, and a comparison against the host's own stream task over the same TLS
   connection.
4. **The two header byte counts stay `absent`, and the reason is the true one.** A stream task is a raw
   TCP connection: it sends no request and receives no response, so there is no HTTP header to count and
   the honest answer is 0 for a stream. The wall is not the socket -- it is that the *data* task's
   transaction is the release's connection, whose header bytes reach the release's parser and stop there.
   Those two rows are therefore a different row each from the six above, and they stay as they are.
