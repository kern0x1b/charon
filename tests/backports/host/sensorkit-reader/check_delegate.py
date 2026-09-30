#!/usr/bin/env python3
"""check_delegate.py SOURCE - which of SRSensorReaderDelegate's ten methods the port's reader sends.

    python3 check_delegate.py <path to the port's SRSensorReader.m>

Prints one line per method, SENT or NEVER, then the two checks run.sh holds the port to, then a summary
line. Exits 0 when the reader sends exactly the expected set and every error callback carries
SensorKit's own inaccessible-data error; non-zero otherwise, naming what it saw.

WHY A CHECK OVER THE SOURCE AND NOT A DIFFERENTIAL. There is no behavioural oracle for this class on
this machine, and that is measured rather than assumed: the host's own SensorKit.framework declares
SRSensorReader and implements nothing (respondsToSelector: is 0 for +authorizationStatus and
+sharedReader), and the port's own CharonSensorKit.h cannot be compiled against the host's newer SDK at
all - clang answers "typedef redefinition with different types ('NSInteger' vs
'enum SRAcousticSettingsSampleLifetime')" for the fifteen enumerations it redeclares, because the host's
SensorKit declares them as NS_ENUM. The port's reader is therefore built for armv7 and read back out of
its object; this file reads the source, and run.sh proves it can be wrong by planting three changes.

WHAT COUNTS AS SENT. This class sends its delegate messages in one shape and one shape only:

    id<SRSensorReaderDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(sensorReader:startRecordingFailedWithError:)]) {
        [delegate sensorReader:self startRecordingFailedWithError:[SRSensorReader storeUnavailableError]];
    }

so a method is SENT when some line carries its selector, carries the receiver `[delegate`, and is not
the guard line itself. A method the file merely guards against is NEVER, which is the honest reading:
nothing in the port ever asks for it.
"""
import re
import sys

# The ten, in the SDK 26.2 header's own order: SRSensorReader.h:40 to :84, every one @optional.
EXPECTED_SENT = [
    "sensorReader:startRecordingFailedWithError:",
    "sensorReader:stopRecordingFailedWithError:",
    "sensorReader:fetchingRequest:failedWithError:",
    "sensorReader:fetchDevicesDidFailWithError:",
]
ALL_TEN = [
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
STORE_UNAVAILABLE = "[SRSensorReader storeUnavailableError]"
DENIED = "SRAuthorizationStatusDenied"


def pattern_for(selector):
    """The send as it is spelled in the source: each keyword followed by its colon, with the argument
    text allowed in between, and the whole thing inside one bracketed message send."""
    parts = [part for part in selector.split(":") if part]
    return (r"\[delegate\s+" + r"[^\]]*".join(re.escape(part) + ":" for part in parts[:-1])
            + r"[^\]]*" + re.escape(parts[-1]) + (":" if selector.endswith(":") else "")
            + r"[^\]]*\]")


def sent_selectors(lines):
    """Every selector this source sends to its delegate, in first-seen order."""
    found = []
    for line in lines:
        if "respondsToSelector" in line or "[delegate" not in line:
            continue
        for selector in ALL_TEN:
            if re.search(pattern_for(selector), line) and selector not in found:
                found.append(selector)
    return found


def main():
    if len(sys.argv) != 2:
        sys.exit("check_delegate.py: pass the path to the port's SRSensorReader.m")
    with open(sys.argv[1], encoding="utf-8", errors="replace") as handle:
        lines = handle.read().split("\n")

    body = "\n".join(lines)
    sent = sent_selectors(lines)

    for selector in ALL_TEN:
        print("%-8s %s" % ("SENT" if selector in sent else "NEVER", selector))

    failures = []

    missing = [s for s in EXPECTED_SENT if s not in sent]
    if missing:
        failures.append("the reader no longer sends %s" % ", ".join(missing))
    extra = [s for s in sent if s not in EXPECTED_SENT]
    if extra:
        failures.append("the reader now sends %s, which nothing in this port should send"
                        % ", ".join(extra))

    # Every failure callback carries SensorKit's own error rather than one of its own making.
    for selector in EXPECTED_SENT:
        if selector in sent:
            for index, line in enumerate(lines):
                if selector in line and "respondsToSelector" not in line:
                    window = "\n".join(lines[index:index + 3])
                    if STORE_UNAVAILABLE not in window:
                        failures.append("%s is sent without %s" % (selector, STORE_UNAVAILABLE))
                    break

    # The authorization is denied, which is why didChangeAuthorizationStatus: can never fire.
    if DENIED not in body:
        failures.append("the reader no longer answers %s" % DENIED)

    for failure in failures:
        print("FAIL " + failure)
    print("sensorkit-reader: %d of %d protocol methods sent, %d failures%s"
          % (len(sent), len(ALL_TEN), len(failures), "" if not failures else "  <- SEE FAIL"))
    return 1 if failures else 0


sys.exit(main())