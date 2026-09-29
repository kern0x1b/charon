#!/usr/bin/env python3
"""A check per constant: the port's value must be the host's, character for character.

This is the check that would catch a value written from a rule instead of from a measurement. A
kSecKeyAlgorithm name says which algorithm it names; only the host says what string a key signature
answers with.
"""
import json
import sys

system = json.load(open(sys.argv[1]))
port = json.load(open(sys.argv[2]))
bad = []
for name, host_value in sorted(system.items()):
    if port.get(name) != host_value:
        bad.append("%s: the host has [%s] and the port has [%s]" % (name, host_value, port.get(name)))
for line in bad:
    print("DIFFERS " + line)
if bad:
    sys.exit(1)
print("compared %d constants: every one is the host's value" % len(system))
