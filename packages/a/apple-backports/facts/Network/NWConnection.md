# The connection of Network, iOS 12

`nw_connection_t` is a real socket: the host is resolved with `getaddrinfo`, a datagram socket is opened, and it is
connected to the first address that answers. `nw_path_monitor_*`, `nw_path_*` and `nw_interface_*` are carried by the
Foundation library (`facts/Network/NWPathMonitor.md`), and this connection reports its path through them, so a
program that only asks "is that peer reachable from here" needs nothing of Network beyond this file.

This is the surface the Matter framework's device browser needs: `src/darwin/Framework/CHIP/MTRDeviceConnectivityMonitor.mm`
of connectedhomeip v1.6.1.0 calls `nw_endpoint_create_host`, `nw_parameters_create_secure_udp`,
`nw_connection_create`, `nw_connection_set_queue`, `nw_connection_set_path_changed_handler`,
`nw_connection_set_viability_changed_handler`, `nw_connection_start` and `nw_connection_cancel`, and nothing else of
Network.

## What it does

- `nw_endpoint_create_host` keeps the host and the port as they were given; the endpoint answers its type
  (`nw_endpoint_type_host`), its host and its port. A NULL or empty host is refused, as a NULL endpoint is.
- `nw_parameters_create_secure_udp` runs the caller's configure block exactly once, with the options it was handed,
  and gives back parameters for a datagram connection.
- `nw_connection_create` refuses a NULL endpoint or NULL parameters, as the header says it does.
- `nw_connection_set_queue` names the queue every handler of this connection is called on. A connection started
  without one does nothing, which is what the header says must not be done; a second `nw_connection_start` is not a
  new attempt.
- `nw_connection_start` opens and connects the socket on that queue, then starts a path monitor. The path-changed
  handler is called with the path when the connection starts and whenever the path changes. The viability-changed
  handler is called with `true` when the connection first becomes viable, and again on every change of it.
- `nw_connection_cancel` closes the socket, cancels the path monitor, and asks twice is the same as asking once; no
  handler is called after it.

## What viability means here, exactly

For a datagram socket `connect()` sends nothing: it binds the default peer, and the kernel returns `ENETUNREACH`
exactly when it has no route to give. So **viable means the kernel has a route to that address and the release's own
reachability says the path is satisfied**. It does not mean the peer answered, because nothing has been sent to it: a
UDP peer cannot be probed without sending it a packet, and a connectivity monitor must not send one.

## The two sentinel blocks

`parameters.h` declares `_nw_parameters_configure_protocol_default_configuration` and
`_nw_parameters_configure_protocol_disable` as `extern` blocks, and every factory that takes them compares them by
pointer. A release with no Network binds both as the null, and then the two would compare equal to each other and to a
caller who passed nothing. Each is defined here as the empty block it is documented to behave as, so the pointer a
caller passes is a real one and the comparison means what it says.

## Not carried, and why

- The stream parameters factories (`nw_parameters_create_secure_tcp`, `nw_parameters_create_tcp`, and the rest of
  `parameters.h`): there is no stream transport here, and a connection that only reported a path over a socket that
  cannot carry a stream would be a wall standing in for one.
- The connection's data calls: `nw_connection_send`, `nw_connection_receive`, `nw_connection_send_completion`, and the
  state, metadata, better-path and multipath handlers above them. A program that names one does not link, which is the
  honest answer for a call this file does not make real.
- Listeners, browsers, endpoints of a service or a Unix path, groups, the content and framer contexts, and every
  `nw_protocol_options` call: none of them is carried. Network has 1 649 rows in the SDK 26.2 surface; this file and
  the path monitor carry the 35 of them the port's own code reaches.
