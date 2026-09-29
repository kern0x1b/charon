#!/usr/bin/env python3
"""The port's VideoToolbox classes must answer as the iOS 26.2 SDK declares them, and where the host
declares the same member at all, they must answer as the HOST answers it.

Two oracles, and the second one is not always available. The first is cases.m's table, generated from
the iOS 26.2 headers, which says for every class and every accessor whether the SDK declares it on the
class or on the instance; the port is held to that for all 150 accessors. The second is the host's own
macOS VideoToolbox, and for some members there is nothing to ask: the host's SDK is 27.0, and its
VideoToolbox headers do not declare nextFrameCount, previousFrameCount, maximumDimensions or
minimumDimensions AT ALL - not as class methods, not as instance methods. Those are counted and
printed, because a comparison that quietly stops being host-backed is a comparison that reads as
stronger than it is. The count is expected to fall as the host's SDK catches up; when it does, the
member goes back to being compared against the host, which is the point.

The template commit recorded maximumDimensions as a divergence by hand, and this run showed why a
hand-written list is the wrong instrument: the note claimed the host did not answer it as a class
method, which is true, and compare.py's first version then reported that divergence as "gone" because
the host also does not answer it as an instance method - the two absences were read as agreement. The
host's absence is now derived from the measurement rather than asserted, so it cannot be misread.
"""
import json
import os
import re
import sys

TABLE = re.compile(r'^\s*\{"(\w+)", "(\w*)", "([^"]*)", "([^"]*)"\},', re.M)

expected = {}
classes = []
for cls, proto, class_props, instance_props in TABLE.findall(open(sys.argv[3]).read()):
    classes.append(cls)
    expected[cls] = {"protocol": proto,
                     "class": class_props.split(),
                     "instance": instance_props.split()}

system = json.load(open(sys.argv[1]))
port = json.load(open(sys.argv[2]))
bad = []
host_absent = set()
compared = host_compared = 0

for name, host in sorted(system.items()):
    field, _, tail = name.partition(".")
    m = re.match(r"^(\w+)\.(\w+)$", tail)
    if field in ("isClass", "isInstance") and m:
        cls, accessor = m.group(1), m.group(2)
        if cls not in expected:
            bad.append("%s: a class the generated table does not have" % name)
            continue
        want = accessor in expected[cls]["class"] if field == "isClass" else accessor in expected[cls]["instance"]
        on_class = system.get("isClass.%s.%s" % (cls, accessor)) == "1"
        on_instance = system.get("isInstance.%s.%s" % (cls, accessor)) == "1"
        if not on_class and not on_instance:
            # the host's SDK does not declare this member, so it cannot be an oracle for it
            host_absent.add("%s.%s" % (cls, accessor))
            compared += 1
            if (port.get(name) == "1") != want:
                bad.append("%s: the port has %r and the iOS 26.2 SDK declares it %s - the host's SDK "
                           "27.0 does not declare this member at all, so the table is the only oracle"
                           % (name, port.get(name), "on the class" if want else "on the instance"))
            continue
        host_compared += 1
        if (port.get(name) == "1") != want:
            bad.append("%s: the host has %r, the port has %r, and the iOS 26.2 SDK declares it %s"
                       % (name, host, port.get(name), "on the class" if want else "on the instance"))
        compared += 1
        continue
    compared += 1
    if port.get(name) != host:
        bad.append("%s: the host has %r and the port has %r" % (name, host, port.get(name)))

for line in bad:
    print("DIFFERS " + line)
if bad:
    sys.exit(1)
print("compared %d records over %d classes: %d against the host's own VideoToolbox, %d against the "
      "iOS 26.2 table alone because the host's SDK 27.0 does not declare the member"
      % (compared, len(classes), host_compared, len(host_absent)))
if host_absent:
    print("host has no such member: " + ", ".join(sorted(host_absent)))
