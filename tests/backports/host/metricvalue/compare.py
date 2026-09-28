#!/usr/bin/env python3
"""The two halves of the MetricKit value differential.

The host can answer one thing - what the system's own MetricKit writes for a value nothing measured -
and compare.py requires the port to answer it the same way. What the host cannot answer is a populated
value, so the filled-in half is checked against the port's own contract, with the key spelling stated
as a choice and the reason recorded in the file."""
import json, sys

system = json.load(open(sys.argv[1]))
port = json.load(open(sys.argv[2]))
bad = []

# what the host answers, and the port must answer it identically
for name in ("empty.keyCount", "empty.jsonIsObject"):
    if system.get(name) != port.get(name):
        bad.append("%s: the host's MetricKit wrote %r, the port wrote %r" % (name, system.get(name), port.get(name)))

# what only the port can answer, checked against the header's own property list
expect = {
    "filled.keyCount": "1",              # one property set: the others are nil and left out
    "filled.hasCumulativeCPUTime": "1",
    "filled.unsetIsAbsent": "0",         # a property nobody set is not in the dictionary
    "filled.jsonKeyCount": "1",
    "date.endAbsent": "0",               # and the same for a date
    "archive.sameRepresentation": "1",    # an archived value reads back to the same representation
}
for name, wanted in expect.items():
    if port.get(name) != wanted:
        bad.append("%s: expected %r, the port wrote %r" % (name, wanted, port.get(name)))
for name in ("filled.cumulativeCPUTime", "filled.jsonValue", "date.value", "archive.cumulativeCPUTime"):
    if not port.get(name) or port[name] == "(none)":
        bad.append("%s: nothing was recorded" % name)
# the JSON and the dictionary must agree, which is the contract the two representation methods share
if port.get("filled.cumulativeCPUTime") != port.get("filled.jsonValue"):
    bad.append("the dictionary wrote %r and the JSON %r for the same property"
               % (port.get("filled.cumulativeCPUTime"), port.get("filled.jsonValue")))
if port.get("filled.cumulativeCPUTime") != port.get("archive.cumulativeCPUTime"):
    bad.append("the archived value came back as %r, not %r"
               % (port.get("archive.cumulativeCPUTime"), port.get("filled.cumulativeCPUTime")))

# The KVC walk: every property the port declares and the SDK it builds against does not must be
# answered by an accessor on the port's own class, or the representation of that class raises. This is
# the check the M-Z review asked for after F1, and it is the one the gate cannot make: check_registry
# collects the classes a library carries and the selectors its CATEGORIES add, and a method missing from
# a class the port defines is not a missing symbol.
for name in sorted(k for k in port if k.startswith("kvc.")):
    if not name.endswith(".answers") and not name.endswith(".read"):
        continue
    if port.get(name) != "1":
        bad.append("%s: no accessor answers that name on the port's own class" % name)
for name in sorted(k for k in port if k.startswith("kvc.") and k.endswith(".class")):
    if port.get(name) != "1":
        bad.append("%s: the port's own class is not in the build" % name)

if bad:
    for line in bad:
        print("DIFFERS " + line)
    sys.exit(1)
print("compared %d records: the host's empty answer, and the port's own contract" % len(port))
