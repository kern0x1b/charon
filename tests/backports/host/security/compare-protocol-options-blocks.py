#!/usr/bin/env python3
"""The three block setters, differences NAMED - and that they are THREE settings.

    python3 compare-protocol-options-blocks.py <the binary's output>

Each block is set ALONE and the other two are read back, because a port that stored them in one slot
would report a challenge block as set after a key-update block was set, and a port that passed them all
at once would never show it.
"""
import sys

VALUES = {"key-update-alone": 1, "challenge-still-unset": 0, "verify-still-unset": 0,
          "all-three-set": 3, "p-has-verify": 1, "p-has-no-key-update": 0, "p-has-no-challenge": 0,
          "after-null-verify": 0, "neighbors-untouched": 2, "null-options": 1,
          "alive-in-scope": 1, "deallocated-after-scope": 0}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-protocol-options-blocks.py: pass the binary's output")
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
        bad.append("port-class: the port's CharonSecProtocolBlocks was not found")
    for label, expect in VALUES.items():
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
    print("compared %d values, each block set alone with its two neighbours read back" % len(VALUES))


if __name__ == "__main__":
    sys.exit(main())
