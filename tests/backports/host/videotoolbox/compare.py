#!/usr/bin/env python3
"""A check per constant: the port's value must be the host's, character for character.

This is the check that would catch a value written from a rule instead of from a measurement. The
reason it exists is measured too: none of the 135 is the constant's own name, so "a string constant is
its own name" - the form this package uses for MXErrorDomain and PKPushTypeVoIP, both measured right -
would be wrong in every one of them."""
import json, sys

system = json.load(open(sys.argv[1]))
port = json.load(open(sys.argv[2]))
bad = []
for name, host_value in sorted(system.items()):
    if port.get(name) != host_value:
        bad.append("%s: the host has [%s] and the port has [%s]" % (name, host_value, port.get(name)))
if bad:
    for line in bad[:20]:
        print("DIFFERS " + line)
    print("DIFFERS ... and %d more" % (len(bad) - 20) if len(bad) > 20 else "", end="")
    sys.exit(1)
print("compared %d constants: every one is the host's value" % len(system))
