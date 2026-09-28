# The listener of Network

`nw_listener_create`, `nw_listener_create_with_port`, `nw_listener_create_with_connection` and the
rest of listener.h are a real socket: a stream bound to the port the program named (or to one the
system gives when the port is zero), listening, with `accept` on a dispatch source over the listener's
own queue, and the connection each accept produces a real `nw_connection_t` of this library over the
accepted socket. The states are the SDK's - `waiting`, `ready`, `failed` with the error that stopped it,
`cancelled` - and `nw_listener_get_port` answers 0 until the listener is ready.

The advertisement of a Bonjour service is `NSNetService`: the release's own DNS-SD, reached through the
API Apple documents for it, not a browse or a register of the port's own.

## What is measured, and what is not

`tests/backports/host/network-listener`, the port's listener and the host's own connection through it -
the host is the client because **the host's Network will not start a listener in this environment**:
asked for one, on a port of its choosing and on a port the test names, it answers `failed` with POSIX
`EINVAL`, while its connection works and sends and receives normally (the same measurement).

Measured, and the count is three of the seven, not five - the listener is made, it becomes `ready` on
the port it was asked for, and it reports that port. What does not pass is stated below rather than
folded into the total.

Green, four of them, and the fourth is the handover:

- the listener is made;
- it becomes `ready` on the port it was asked for, and reports that port;
- the host's own `NWConnection` reaches `ready` **through** the port's listener, which is the accept
  loop working against Apple's own implementation;
- the handover to a new-connection handler, and the port was right about it: `CHARON_TRACE_LISTENER` shows
  it calling the handler at `ready`, with the listener the test holds, the queue the test set, and the
  connection the test's own block then receives. What was wrong was the check - the test's handler
  filled a list and the check read a variable nothing ever wrote, so the check could not pass however the
  port behaved.

Red, three of them, and none of them folded into the total above:

- the bytes crossing **inbound**, which the connection the listener made does not deliver: the host's own
  `nw_connection_send` reports success, so the bytes are in the socket, and the port's read source does
  not hand them on. The direction the other way round is not reached, because the port's send waits on
  this one. That is the next thing to look at, in the port's read path for a connection whose socket came
  from an accept.

**Not yet measured, and red in that test:**

- the bytes crossing in either direction through a connection the listener made. The connection is
  handed over and reported `ready`, and neither the host's `nw_connection_send` nor the port's reaches
  the other side. The engine, its queue, its read and write sources and the same code path are all
  proven by `tests/backports/host/network-connection` (24 checks, both directions over the same
  loopback pair), so what is missing is in what a listener does to a connection before it hands it
  over - the queue it gives it and the state handler it installs on it - and not diagnosed here.
- the teardown: cancelling a listener that has adopted a connection faulted inside libdispatch in an
  earlier arrangement of the test (`dispatch_assert_queue` on the connection's own connect queue, with
  a queue value that is a small integer rather than a pointer). The two fixes that were made for the
  engine underneath - a connection whose socket came from an accept does not connect again, and a
  listener gives that connection its queue before starting it - are in the tree, and the teardown is
  no longer driven by the test while the byte crossing is still red.

So the listener's registry entries stand on the three green checks and the connection's on its own
differential; neither claims the whole surface.
