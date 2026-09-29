#!/usr/bin/env python3
"""Requires the port's four time functions to satisfy the relations the header states, and requires the
host's own to satisfy them too - the host is the only oracle SensorKit has, and the port's numbers are
its own anchor, so what can be compared is the relation and not the value."""
import json, sys

system = json.load(open(sys.argv[1]))
port = json.load(open(sys.argv[2]))
bad = []
for who, prefix, records in (("the host's", "system", system), ("the port's", "port", port)):
    for relation in ("neverBackwards", "thirdReadingAdvances", "notNull", "agreesWithCFAbsoluteTime",
                     "roundTripWithinAMicrosecond", "fromContinuousNonZero"):
        key = "%s.%s" % (prefix, relation)
        if records.get(key) != "1":
            bad.append("%s does not satisfy %s (%r)" % (who, relation, records.get(key)))
# The NSDate category's three relations, asked of BOTH builds: the host is the only oracle SensorKit
# has, and the port's numbers are its own anchor, so what can be compared is the relation.
#
# IT WAS WRITTEN ONCE WITH AN EXPECTED DIFFERENCE - that the host's own build would not have the class
# method - and the run said otherwise, because the probe behind that belief used class_getInstanceMethod,
# which finds an INSTANCE method: the class method lives on the metaclass, so the probe answered "no" for
# a method the host has. The host answers yes to all three, and both sides are held to the same three
# relations.
for who, prefix, records in (("the host's", "system", system), ("the port's", "port", port)):
    for relation in ("categoryInitPresent", "categoryGetterPresent", "categoryClassMethodPresent",
                     "categoryRoundTrip", "categoryAgreesWithClock", "categoryNeverBackwards"):
        key = "%s.%s" % (prefix, relation)
        if records.get(key) != "1":
            bad.append("%s does not satisfy %s (%r)" % (who, relation, records.get(key)))

# the two anchors are different, and must be: the port's is its own mach_absolute_time pair, and the
# host's is Apple's. What must be the same is each one's own round trip, which the relations above say.
print("compared %d records: the host's relations and the port's" % len(port))
if bad:
    for line in bad:
        print("DIFFERS " + line)
    sys.exit(1)
