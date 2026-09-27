# The objects of Network's C API, iOS 12 to 26

Every `nw_*` call that hands back an object or holds a setting, for a release that has no Network at
all. There is no release below iOS 9 whose own calls would reach these objects, so nothing here is a
substitute for the system's; the objects are the port's own, made out of the data a program gives
them, and every getter answers the release's own answer for what a program has (and has not) said.

**Source: the host's own Network.framework, asked the same question of the port's implementation
compiled beside it with its names changed, and the two answers compared** -
`tests/backports/host/network-objects`, 176 checks, the port's files compiled with every symbol they
define renamed (`-Dnw_x=charonhost_nw_x`, `-DCharonX=CharonHostCharonX`) and one program reaching
either side through one table of function pointers. The host is macOS 27.0 (build 26A428), whose
Network.framework carries the whole of the 26.2 API. Where a value had to come from a real release and
not from a header, it is said so below.

## What is built out of what

- Every `nw_*` type is a protocol of the SDK's own making (`OS_OBJECT_DECL` makes `nw_path_t` an
  `NSObject<OS_nw_path> *`), so each object here is an `NSObject` that adopts the protocol of the type
  it is. The classes and their state are in `CharonNW.h`, their implementations in
  `CharonNWObjects.m`, and the few pieces of C every file needs in `CharonNWSupport.c` - which is C so
  that nothing in it is exported, because a helper an Objective-C file defined would be a symbol the
  registry has to describe and a file that carries API of two releases would be split from under it.
- One file per family **and per release**, named for the release (`nw12-core.m`, `nw13-txtrecord.m`,
  `nw14-privacy.m`, `nw15-quic.m`, `nw154-framer.m`, `nw16-*.m`, `nw17-proxy.m`, `nw26-*.m`), because
  `modules/apple/backports.lua` raises on an object that exports the symbols of two introductions. What
  the files share is the header and the C file; a helper that lives in a file carrying API of one
  release is dropped from a band that keeps a later release, and a call of that band would then be
  undefined - which only the all-band build of `canon-install` would show.
- A setting is kept under the name the SDK's own setter for it uses, so the connection reads back
  exactly what the program set, and a setting nobody set reads as the default its getter documents.
- The settings that reach the socket are not decoration: the TCP options become `setsockopt` calls
  (`TCP_NODELAY`, `SO_KEEPALIVE` and its three times, the buffer sizes, the service class) and the path
  settings are what the path monitor is asked. That is the connection's own file.

## What the comparison found, and where the port follows its own header instead

These are the answers a program can see that the header alone would not have given, all measured
(tests/backports/host/network-objects):

- **An endpoint is valid only when its port names something.** A host with no port, or with a port that
  is neither a number nor a service in the system's own services file, is no endpoint at all - not an
  endpoint that answers zero. A host that is already an address is an *address* endpoint, and still
  answers the host it was made from as its own text; an address endpoint answers its address as text and
  its port as text, and `nw_endpoint_copy_address_string` is NULL where there is no address rather than
  an empty string.
- **A Bonjour service needs all three of what it is.** No name, no type or no domain is refused. A port
  of "http" is resolved through the system's own services file, so the endpoint keeps the number.
- **A URL is a URL when it has a scheme.** The host is what its authority names and nothing where the
  authority names nothing; the port is its own or, failing that, the one its scheme answers (80 for
  http, 443 for https, 21 for ftp); the brackets of an IPv6 literal are part of the text and not part
  of the host.
- **A final content context is finished.** Once `nw_content_context_set_is_final` has been called it
  reports the default priority and no expiration, whatever was set before it and whatever is set after,
  and it takes no antecedent. An antecedent is the context that was set, held, not a copy of it.
- **Two framer definitions of one name are different protocols.** A framer's definition is made afresh
  and belongs to the program that made it, so two of them are never equal - the built-in definitions,
  which the system hands out as one per process, are.
- **A TXT record of no bytes is no record**, and an empty record is the single zero byte that a service
  saying nothing publishes. A record made of bytes is a dictionary of the key-value pairs in it; a key
  with no `=` has no value at all, which is not the same as an empty value, and a key that is empty, that
  is longer than 255 bytes or that holds a byte outside printable US-ASCII is invalid - refused by
  every call that takes one, as RFC 6764 asks.
- **Options are not metadata.** `nw_protocol_metadata_is_tcp` of TCP *options* is false, and so is the
  rest: a predicate is about a message. `nw_tls_copy_sec_protocol_options` is the exception - it hands
  out the Security.framework object for any options of its own kind, while the QUIC pair asks first
  whether the object is QUIC's.
- **A stack is not a stack until it is used.** The default stack of `nw_parameters_create` holds the
  internet protocol and *no transport*: the transport is decided when a connection is made of it, which
  is a TCP connection because that is what a connection with no transport is. Every other factory
  hands back a stack with a transport, `NW_PARAMETERS_DISABLE_PROTOCOL` leaves that protocol out, and
  QUIC - which carries its own transport - shows no protocol at all.
- **The sentinels are compared by pointer**, so they are real objects: the two blocks the header names
  are defined here as the empty blocks they are documented to behave as, and a factory that is given a
  block of the caller's own runs it.
- **The QUIC defaults are the documented ones**: an idle timeout of 30000 ms, a maximum UDP payload of
  65535, and flow-control limits of `UINT64_MAX`, which is "no limit of our own". A message that is not
  QUIC's answers 0 for every one of QUIC's metadata getters and takes none of its setters.
- **The WebSocket metadata of a message with no close code says 1005**, which is the code for "no status
  received"; options of no version are still options.
- **`nw_data_transfer_report` is a snapshot.** Until the block of `nw_data_transfer_report_collect` has
  been given it, it is outstanding, its state is not `collected`, and every value answers 0 - which is
  what the header says a report that is not collected answers. The connection writes its counters into
  the report when it hands it out, so the numbers appear when it is collected and do not change after.

## Where the port answers for itself, and says so

- **`nw_content_context_create(NULL)` traps on the host** (measured: the process dies of an
  uncaught `NSInvalidArgumentException`), so there is no host answer to compare. The port refuses it
  with NULL, which is what the header says a factory does when it fails.
- **`nw_group_descriptor_add_endpoint` adds nothing on the host** and answers false for every endpoint
  tried - a name, an address, a URL, a Bonjour service, on a multicast group and on a multiplex one
  (measured; its enumeration still yields the group address and the remote endpoint). That is not what
  its own header says, which is "true if the endpoint was added, false if the endpoint was not of a
  valid type and therefore not added". The port follows the header: an endpoint that names a peer - a
  host or an address - is added and `true` is answered, and one that names no peer is refused with
  `false`.
- **The default of `nw_quic_get_max_datagram_frame_size` on the host is uninitialised memory** (two runs,
  two numbers), so there is no value of the system's to compare. The port answers 0, which is the
  documented way of saying that a connection sends no datagram frames at all.

## What the release has no answer for, and which answer the port gives

- **A constrained path** is Low Data Mode. The release has no such mode, so no path of it is ever
  constrained - the answer a device with the mode switched off gives is `false`. A program that sets the
  flag on its parameters still has it set, and the connection reads it as it reads every other path
  setting.
- **An unsatisfied reason** (iOS 14.2) is one of the system's own policies: a permission the user denied,
  a network the user turned off. This release's reachability says whether the network is there and
  never why it is not, so an unsatisfied path is unsatisfied for a reason the release does not name,
  which is what `nw_path_unsatisfied_reason_not_available` says.
- **Gateways** (iOS 13) are the routers a packet leaves by. The release's own ioctl that names the router
  of an interface without any privilege is `SIOCGIFDSTADDR`, and it answers for a point-to-point
  interface - which is what a cellular data connection on this release is. A Wi-Fi interface is not
  point-to-point and has no such answer, so nothing is enumerated for it; that gap and the ioctl are in
  `facts/Network/NWPath.md` with the measurement.
- **A link quality** (iOS 26) is a measurement the release has no way to make: the interface is up or it
  is not, and what a program can read by hand is not what this measures. Every path answers
  `nw_link_quality_unknown`, which is the first of the four values and is what the system answers where
  it has no measurement either.
- **An ultra-constrained path** (iOS 26) is a low-bandwidth link meant only for a device of its own. The
  release has none, so no path is one.
- **A radio type** (iOS 15) is behind an interface the system does not let a program ask about, so a
  path over Wi-Fi or over cellular has none to report, which is `nw_interface_radio_type_unknown`.
- **A privacy context, a resolver configuration and a proxy configuration** (iOS 14, 17) are carried as
  what a program said: the context has the description it was given, the resolver has its endpoint and
  its addresses, the proxy has its kind, its endpoint, its credentials, its domains and whether a
  failover is allowed. The release resolves names with the resolver the system gives it and has no
  per-connection proxy, so a connection is made to the peer its endpoint names - and says so in its
  establishment report rather than pretending to have gone through a proxy. `facts/Network/NWProxy.md`.

## What the port has no transport for, and what that means for these calls

Three of the protocols these objects configure have no transport in this port: **QUIC**, **WebSocket**
and any **proxy or relay**. What is here is the configuration and the description of those protocols -
what a program sets and what it reads back, which is real and is what the host's own Network answers
for the same calls - and what is *not* here is a connection that speaks them. A connection of QUIC or
WebSocket parameters is a connection over its transport with no layer of that protocol on it. The rows
are the option and metadata objects, which work; the transport is absent rather than faked, and
`facts/Network/NWQUIC.md`, `facts/Network/NWWebSocket.md` and `facts/Network/NWProxy.md` say so.

## The exported symbols

- `nw_retain` and `nw_release` are C functions here as well as the header's Objective-C macros, for a
  translation unit that is not Objective-C and for the two of them to be found where the SDK declares
  them. The macros are taken back in the file that defines them, or the definitions would be macros.
- `kNWErrorDomainPOSIX` is `NSPOSIXErrorDomain`, `kNWErrorDomainTLS` is `NSOSStatusErrorDomain`,
  `kNWErrorDomainDNS` is `kNWErrorDomainDNS` and `kNWErrorDomainWiFiAware` is `kNWErrorDomainWiFiAware` -
  each read out of the host's own Network with a program that prints what the symbol points at, not
  taken from the name and not from a comment.
- `_nw_data_transfer_report_all_paths` is `UINT32_MAX`, the value the host's own Network holds for it.
