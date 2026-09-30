#!/usr/bin/env python3
"""objc_selectors.py OBJECT - the selectors a compiled object carries, filtered to SensorKit's.

    python3 objc_selectors.py <path to a .o>

Prints one line per selector of the SRSensorReaderDelegate protocol the object's __TEXT,__objc_methname
section holds, sorted, then a summary line. Exits 0 when the set is the expected four, non-zero
otherwise, naming what it saw.

WHY THIS EXISTS BESIDE check_delegate.py. check_delegate.py reads the port's source and says which
messages the reader sends; this reads the COMPILED object and says which of the protocol's selectors the
armv7 binary carries. They are different claims and the second is the one a device would exercise: an
object's __objc_methname is what the linker binds @selector() references against, so a selector in
this section is one the reader can actually send. A reader that mentioned a selector only in a comment,
or only in a string, is in neither.

The filter is the protocol's own ten, read out of the SDK 26.2 header (SRSensorReader.h:40 to :84).
"""
import re
import subprocess
import sys

TEN = [
    "sensorReader:fetchingRequest:didFetchResult:",
    "sensorReader:didCompleteFetch:",
    "sensorReader:fetchingRequest:failedWithError:",
    "sensorReader:didChangeAuthorizationStatus:",
    "sensorReaderWillStartRecording:",
    "sensorReader:startRecordingFailedWithError:",
    "sensorReaderDidStopRecording:",
    "sensorReader:stopRecordingFailedWithError:",
    "sensorReader:didFetchDevices:",
    "sensorReader:fetchDevicesDidFailWithError:",
]
EXPECTED = [
    "sensorReader:startRecordingFailedWithError:",
    "sensorReader:stopRecordingFailedWithError:",
    "sensorReader:fetchingRequest:failedWithError:",
    "sensorReader:fetchDevicesDidFailWithError:",
]


def methnames(obj):
    out = subprocess.run(["otool", "-v", "-s", "__TEXT", "__objc_methname", obj],
                         check=True, capture_output=True, text=True).stdout
    found = set()
    for line in out.split("\n"):
        # the section header line and the "N bytes" line are not entries; every entry is an address and a
        # selector, and the selector may hold any punctuation but no whitespace
        match = re.match(r"^[0-9a-f]{6,}  (\S+)$", line)
        if match:
            found.add(match.group(1))
    return found


def main():
    if len(sys.argv) != 2:
        sys.exit("objc_selectors.py: pass the path to a compiled object")
    held = sorted(methnames(sys.argv[1]) & set(TEN))

    for selector in TEN:
        print("%-8s %s" % ("IN" if selector in held else "OUT", selector))

    failures = []
    missing = [s for s in EXPECTED if s not in held]
    if missing:
        failures.append("the object does not carry %s" % ", ".join(missing))
    extra = [s for s in held if s not in EXPECTED]
    if extra:
        failures.append("the object also carries %s, which the port's reader must never send"
                        % ", ".join(extra))

    for failure in failures:
        print("FAIL " + failure)
    print("sensorkit-reader-object: %d of %d protocol selectors in the object, %d failures%s"
          % (len(held), len(TEN), len(failures), "" if not failures else "  <- SEE FAIL"))
    return 1 if failures else 0


sys.exit(main())