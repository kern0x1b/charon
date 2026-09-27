/*
 * The one name the port's own TLS needs that the host's Network does not have.
 *
 * The port calls SSLContextCreate with two arguments - the allocator and the side - because that is
 * the call the 6.1.3 cache exports (measured; facts/Network/NWConnection.md). The host's framework has
 * the name from iOS 7 on, SSLCreateContext, which takes the connection type as a third argument, and a
 * connection's TLS is a stream. So the host's call is here under the port's name: the same call, for
 * this build only, so that the port's own file links against the host's framework unaltered.
 */

#include <Security/Security.h>
#include <Security/SecureTransport.h>

SSLContextRef SSLContextCreate(CFAllocatorRef allocator, SSLProtocolSide side);

SSLContextRef SSLContextCreate(CFAllocatorRef allocator, SSLProtocolSide side)
{
    return SSLCreateContext(allocator, side, kSSLStreamType);
}
