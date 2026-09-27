/*
 * Network's endpoint, secure-UDP parameters and connection over the BSD sockets iOS 6 has.
 *
 * A connection here is a real socket. nw_connection_start resolves the host endpoint with
 * getaddrinfo, opens a datagram socket, and connects it to the first address that answers; the path
 * is the one the release's own reachability reports, which is what a program on a release with no
 * Network has to ask instead (Foundation's path monitor, over SCNetworkReachability and the
 * device's interfaces). The connection reports the path through its path-changed handler and
 * viability through its viability-changed handler, both on the queue it was given.
 *
 * What viability means here, exactly: for a datagram socket connect() sends nothing - it binds the
 * default peer - and returns as soon as the kernel has a route. So viable means the kernel has a
 * route to that address and the device's own interfaces are up. It does not mean the peer answered,
 * because nothing has been sent to it: a UDP peer cannot be probed without sending it a packet, and
 * a connectivity monitor must not send one.
 *
 * Absent rather than faked: the stream parameters factories (there is no stream transport here, and
 * a non-blocking connect on a queue this port also runs other work on would be one), and the
 * connection's data calls (nw_connection_send, nw_connection_receive and everything above them). A
 * program that asks for one of those does not link. A connectivity monitor, which is the whole of
 * what this file exists for, needs none of them.
 */

#import <Foundation/Foundation.h>
#import <Network/Network.h>
#import "CharonNW.h"

#include <netdb.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>

@interface CharonNWConnection : NSObject <OS_nw_connection>
@end

@implementation CharonNWConnection {
@public
    CharonNWEndpoint *_endpoint;
    CharonNWParameters *_parameters;
    dispatch_queue_t _queue;
    nw_connection_path_event_handler_t _path;
    nw_connection_boolean_event_handler_t _viability;
    nw_path_monitor_t _monitor;
    BOOL _started, _cancelled, _viable, _viableKnown;
    int _socket;
}
@end

/* Open a datagram socket connected to the endpoint, or NO. getaddrinfo's order is the resolver's own
   preference, so the first address that takes a connect is the one the system would have picked. */
static BOOL CharonNWConnectHost(CharonNWEndpoint *endpoint, int *out)
{
    struct addrinfo hints;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_protocol = IPPROTO_UDP;
    struct addrinfo *list = NULL;
    const char *port = endpoint->_port.length ? endpoint->_port.UTF8String : NULL;
    if (getaddrinfo(endpoint->_hostname.UTF8String, port, &hints, &list) != 0 || !list)
        return NO;
    int opened = -1;
    for (struct addrinfo *entry = list; entry; entry = entry->ai_next) {
        int handle = socket(entry->ai_family, entry->ai_socktype, entry->ai_protocol);
        if (handle < 0)
            continue;
        if (connect(handle, entry->ai_addr, entry->ai_addrlen) == 0) {
            opened = handle;
            break;
        }
        close(handle);
    }
    freeaddrinfo(list);
    *out = opened;
    return opened >= 0;
}

static void CharonNWReport(CharonNWConnection *connection, nw_path_t path, BOOL reachable)
{
    BOOL viable = reachable && path && nw_path_get_status(path) == nw_path_status_satisfied;
    dispatch_async(connection->_queue, ^{
        if (connection->_cancelled)
            return;
        if (connection->_path)
            connection->_path(path);
        if (connection->_viability && (!connection->_viableKnown || connection->_viable != viable)) {
            connection->_viable = viable;
            connection->_viableKnown = YES;
            connection->_viability(viable);
        }
    });
}

nw_connection_t nw_connection_create(nw_endpoint_t endpoint, nw_parameters_t parameters)
{
    if (!endpoint || !parameters)
        return nil;
    CharonNWConnection *connection = [[CharonNWConnection alloc] init];
    connection->_endpoint = (CharonNWEndpoint *)endpoint;
    connection->_parameters = (CharonNWParameters *)parameters;
    connection->_socket = -1;
    return connection;
}

nw_endpoint_t nw_connection_copy_endpoint(nw_connection_t connection)
{
    return connection ? ((CharonNWConnection *)connection)->_endpoint : nil;
}

nw_parameters_t nw_connection_copy_parameters(nw_connection_t connection)
{
    return connection ? ((CharonNWConnection *)connection)->_parameters : nil;
}

void nw_connection_set_queue(nw_connection_t connection, dispatch_queue_t queue)
{
    if (connection)
        ((CharonNWConnection *)connection)->_queue = queue;
}

void nw_connection_set_path_changed_handler(nw_connection_t connection, nw_connection_path_event_handler_t handler)
{
    if (connection)
        ((CharonNWConnection *)connection)->_path = [handler copy];
}

void nw_connection_set_viability_changed_handler(nw_connection_t connection, nw_connection_boolean_event_handler_t handler)
{
    if (connection)
        ((CharonNWConnection *)connection)->_viability = [handler copy];
}

void nw_connection_start(nw_connection_t connection)
{
    if (!connection)
        return;
    CharonNWConnection *self = (CharonNWConnection *)connection;
    @synchronized(self) {
        /* The SDK requires the queue before the start, and a second start is not a new attempt. */
        if (self->_started || self->_cancelled || !self->_queue)
            return;
        self->_started = YES;
    }
    dispatch_async(self->_queue, ^{
        if (self->_cancelled)
            return;
        int handle = -1;
        CharonNWConnectHost(self->_endpoint, &handle);
        self->_socket = handle;
        /* The path is the release's own reachability, reported again whenever it changes. */
        nw_path_monitor_t monitor = nw_path_monitor_create();
        self->_monitor = monitor;
        nw_path_monitor_set_queue(monitor, self->_queue);
        nw_path_monitor_set_update_handler(monitor, ^(nw_path_t path) {
            if (self->_cancelled)
                return;
            CharonNWReport(self, path, handle >= 0);
        });
        nw_path_monitor_start(monitor);
    });
}

void nw_connection_cancel(nw_connection_t connection)
{
    if (!connection)
        return;
    CharonNWConnection *self = (CharonNWConnection *)connection;
    nw_path_monitor_t monitor;
    @synchronized(self) {
        if (self->_cancelled)
            return;
        self->_cancelled = YES;
        monitor = self->_monitor;
        self->_monitor = nil;
    }
    if (monitor)
        nw_path_monitor_cancel(monitor);
    if (self->_socket >= 0) {
        close(self->_socket);
        self->_socket = -1;
    }
}
