#!/usr/bin/env python3
"""The eight boolean flags, and that they are EIGHT SEPARATE SETTINGS.

    python3 compare-protocol-options-flags.py <the binary's output>

The case sets each flag ALONE against seven unset and reads all eight back, so a shared "flags" word
fails immediately and names the pair. A run that merely set all eight and read them back would pass a
single bit shared between two of them, which is why the alone-pass exists.
"""
import sys

NAMES = ["tickets", "fallback", "resumption", "falsestart", "ocsp", "sct", "reneg", "peerauth"]
ALONE = 8 * 8          # each of the eight, read against all eight
ALL_SET = {("all-set-" + n): 1 for n in NAMES}
CLEARED = {"cleared-ocsp": 0, "neighbour-sct": 1, "neighbour-tickets": 1, "deallocated": 0}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-protocol-options-flags.py: pass the binary's output")
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
        bad.append("port-class: the port's CharonSecProtocolFlags was not found")
    # the alone-pass reports through WRONG lines only; if none appeared, all 64 reads agreed
    if len(wrong) == 0 and len(rows) < len(ALL_SET) + len(CLEARED):
        bad.append("the case printed only %d rows, so the alone-pass did not run" % len(rows))
    for label, expect in list(ALL_SET.items()) + list(CLEARED.items()):
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
    print("compared %d alone-reads, %d flags set together, and 3 neighbours of a cleared one"
          % (ALONE, len(ALL_SET)))


if __name__ == "__main__":
    sys.exit(main())
