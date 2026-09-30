#!/usr/bin/env python3
"""check_protocol.py - the metadata the port emits for SRSensorReaderDelegate, counted.

    python3 check_protocol.py <the output of protocol-count>

Reads one line of the form the probe prints and holds it to what the port is supposed to ship: the
protocol found, TEN optional method descriptions and NONE required. Exits non-zero otherwise, naming what
it saw.

WHY THIS EXISTS, because the first version of this harness's header shipped a protocol with zero methods
and said nothing about it. Measured, on this machine, by taking @protocol(SRSensorReaderDelegate) into a
Protocol * and counting:

    forward declaration only   ->  found,  0 optional
    a declared body            ->  found, 10 optional,  0 required

A forward declaration emits the protocol object and leaves it empty, so an application asking
`[objc_getProtocol("SRSensorReaderDelegate") conformsToSelector:@selector(sensorReaderWillStartRecording:)]`
got a NO for a method its own class implements. The header now declares the ten members and the count is
this check's job.

There is also a measurement here that had to be got wrong twice, and the harness should not repeat it: the
first probe put `(void)@protocol(X)` in a `static` function that main never called, the linker
dead-stripped it, and the probe printed "protocol ABSENT" for both shapes. protocol-count.m calls the
function and prints the object it returns, so what it counts is in the image.
"""
import re
import sys

WANT_OPTIONAL = 10
WANT_REQUIRED = 0


def main():
    if len(sys.argv) != 2:
        sys.exit("check_protocol.py: pass the output of protocol-count")
    with open(sys.argv[1], encoding="utf-8", errors="replace") as handle:
        text = handle.read()

    found = re.search(r"protocol:? (found|ABSENT), (\d+) optional, (\d+) required", text)
    if not found:
        print("FAIL the probe printed no line this check can read: %r" % text.strip()[:120])
        print("sensorkit-protocol: 0 failures  <- SEE FAIL")
        return 1

    present, optional, required = found.group(1) == "found", int(found.group(2)), int(found.group(3))
    failures = []
    if not present:
        failures.append("the port emits no __OBJC_PROTOCOL_$_SRSensorReaderDelegate at all")
    if optional != WANT_OPTIONAL:
        failures.append("the protocol carries %d optional method descriptions and it must carry %d - an "
                        "empty protocol answers NO to conformsToSelector: for a method a conformer "
                        "implements" % (optional, WANT_OPTIONAL))
    if required != WANT_REQUIRED:
        failures.append("the protocol carries %d required method descriptions and it must carry %d, "
                        "because SRSensorReader.h:22 marks every one @optional" % (required, WANT_REQUIRED))

    for failure in failures:
        print("FAIL " + failure)
    print("sensorkit-protocol: %s, %d optional, %d required, %d failures%s"
          % ("present" if present else "ABSENT", optional, required, len(failures),
             "" if not failures else "  <- SEE FAIL"))
    return 1 if failures else 0


sys.exit(main())