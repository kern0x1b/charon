# QUIC, the options and the metadata

`nw_quic_create_options` and its setters, `nw_parameters_create_quic`, and the metadata getters and
setters are the configuration and the description of a QUIC connection. The port has no QUIC transport,
so a connection of QUIC parameters is a connection over its transport with no QUIC layer on it; the
settings are kept and read back as the host's own Network answers them, and nothing pretends to speak
the protocol. Every answer, the defaults included, is in `NWObjects.md` and comes from
`tests/backports/host/network-objects`; the defaults that are worth writing down here are an idle
timeout of 30000 ms, a maximum UDP payload of 65535, and flow-control limits of `UINT64_MAX`, which is
"no limit of our own" - all three measured.

Two answers are the port's own: the default of `nw_quic_get_max_datagram_frame_size` is 0 because the
host's own is uninitialised memory (two runs, two numbers) and 0 is the documented way of saying that a
connection sends no datagram frames; and a message that is not QUIC's answers 0 for every one of these
getters and takes none of these setters, which is what the host does with them as well.
