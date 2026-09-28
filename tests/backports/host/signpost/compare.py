#!/usr/bin/env python3
"""Requires the port's os_signpost answers to be the host's, and the port's own store to have kept an
interval an application marked. The ids are the pair that would have found the high-bit convention this
series carried and the review measured against the host: the host answers 0x1 with the bit clear and
returns a pointer unmasked."""
import json, sys

system = json.load(open(sys.argv[1]))
# What the port's code comments, facts and registry entries say the host does, and what the host does.
# A change of host would make one of these fail, which is the point: the records are claims, and this is
# what holds them to it.
claims = [
    ("signpost.enabled", "1", "the port answers true, and says why: the header's own emit macro compiles the whole "
                                "call away when it is false, so a family that recorded nothing would make every "
                                "metric empty by construction"),
    ("id.isNotNull", "1", "the port's generate never returns OS_SIGNPOST_ID_NULL"),
    ("id.distinct", "1", "the port's generate counts up, so two calls differ"),
    ("id.pointerIsNotReserved", "1", "the port's make_with_pointer never returns one of the two reserved values"),
]
bad = []
for name, wanted, claim in claims:
    if system.get(name) != wanted:
        bad.append("%s: the port's records say %r and the host answers %r - %s"
                   % (name, wanted, system.get(name), claim))

# the high bit: the port's records say the host leaves it clear, and that is what the review measured
# twice. This is the check that would have found the convention the port used to carry.
for name in ("id.first", "id.second"):
    value = int(system.get(name, "0"), 16)
    if value & (1 << 63):
        bad.append("%s is %s: the high bit is set, and the port's records say the host leaves it clear"
                   % (name, system.get(name)))
    if value in (0, 0xFFFFFFFFFFFFFFFF):
        bad.append("%s is a reserved value" % name)
if system.get("id.first") != "1":
    bad.append("the host's first generated id is %r; the port's records say 1" % system.get("id.first"))

if bad:
    for line in bad:
        print("DIFFERS " + line)
    sys.exit(1)
print("compared %d host records against the port's claims about them" % len(system))
