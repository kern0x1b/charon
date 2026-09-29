#!/usr/bin/env python3
"""The six held settings, differences NAMED.

    python3 compare-protocol-options-held.py <the binary's output>

`block-survives-dead-frame` is the row that matters and it is checked as ONE: the held block is CALLED
after the frame that created it has returned, so a port that stored the pointer rather than copying it
would be calling into a dead frame - and on a reused stack frame that is a silent wrong answer rather
than a crash, which is exactly the failure a "was it stored" check would miss.
"""
import sys

HELD = {"ciphersuites-held": 2, "groups-held": 1, "hint-set": 1, "held-block-present": 1,
        "block-survives-dead-frame": 1}
COMPARE = {"range-held-not-equal-yet": 0, "range-read-back-equal": 1, "range-differs": 0,
           "alive-in-scope": 1, "deallocated-after-scope": 0}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-protocol-options-held.py: pass the binary's output")
    rows, wrong = {}, []
    for line in open(sys.argv[1]):
        line = line.rstrip("\n")
        if line.startswith("WRONG\t"):
            wrong.append(line.split("\t", 1)[1])
        elif "\t" in line:
            p = line.split("\t")
            rows[p[0]] = p[1:]
    bad = list(wrong)
    if rows.get("port-class", [None])[0] != "found":
        bad.append("port-class: the port's CharonSecProtocolOptionsHeld was not found")
    for label, expect in list(HELD.items()) + list(COMPARE.items()):
        got = rows.get(label, [None])[0]
        if got is None:
            bad.append("%s: the case did not measure it" % label)
        elif got != str(expect):
            bad.append("%s: got %s and the port claims %d" % (label, got, expect))
    if rows.get("failures", [None])[0] != "0":
        bad.append("the case reported %s failures" % rows.get("failures", ["?"])[0])
    for line in bad:
        print("DIFFERS " + line)
    if bad:
        sys.exit(1)
    print("compared %d held settings, %d read back through the comparator, and the held block called "
          "after its frame was gone" % (len(HELD), len(COMPARE)))


if __name__ == "__main__":
    sys.exit(main())
