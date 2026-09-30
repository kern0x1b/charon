#!/usr/bin/env python3
"""swap_stop.py SOURCE OUT - the object half's own plant: -stopRecording claims it stopped.

    python3 swap_stop.py <the port's SRSensorReader.m> <where to write the copy>

Rewrites the one send inside -stopRecording so the reader tells its delegate recording stopped, which is
one of the six methods nothing in this port should ever send. Exits non-zero when the line it anchors to
is not there, so a plant that stops applying is refused rather than quietly passing.

It is its own file rather than a heredoc in run.sh because the same rewrite is wanted twice - once for
the source check's plant and once for the object's - and one definition of a mutation is worth more than
two spellings of it.
"""
import sys

NEEDLE = ("          [delegate sensorReader:self stopRecordingFailedWithError:"
          "[SRSensorReader storeUnavailableError]];")
REPLACEMENT = "          [delegate sensorReaderDidStopRecording:self];"

# run.sh indents the send by eight spaces; match on the tail so the anchor survives a re-indent.
NEEDLE_TAIL = "sensorReader:self stopRecordingFailedWithError:"


def main():
    if len(sys.argv) != 3:
        sys.exit("swap_stop.py: pass the source and where to write the copy")
    src, out = sys.argv[1], sys.argv[2]
    with open(src, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().split("\n")
    hit = 0
    for index, line in enumerate(lines):
        if NEEDLE_TAIL in line and "[delegate" in line:
            lines[index] = "        " + REPLACEMENT.strip()
            hit += 1
    if hit != 1:
        sys.exit("swap_stop.py: the send to rewrite was found %d times, and it must be exactly 1" % hit)
    with open(out, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    return 0


sys.exit(main())