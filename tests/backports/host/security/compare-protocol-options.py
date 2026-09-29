#!/usr/bin/env python3
"""The four defaults and the comparator, differences NAMED.

    python3 compare-protocol-options.py <the binary's output>

The four expected values are THE RELEASE'S STACK RANGE, written as the numbers themselves so a reader
can check them against the header's enum: TLSv10 0x0301, TLSv12 0x0303, DTLSv10 0xfeff. The two `no-*`
rows are the negative claims that matter most - the port must NEVER answer TLSv13 (0x0304) or DTLSv12
(0xfefd), because a caller asking what it would get by default must not be told about a version 6.1.3
cannot negotiate.
"""
import sys

DEFAULTS = {"default-min-tls": 0x0301, "default-max-tls": 0x0303,
             "default-min-dtls": 0xfeff, "default-max-dtls": 0xfeff}
# label: the value the comparison must give
COMPARE = {"both-empty-equal": 1, "same-range-equal": 1, "different-range": 0,
           "same-object": 1, "null-a": 0, "null-both": 1,
           "alive-in-scope": 1, "deallocated-after-scope": 0}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-protocol-options.py: pass the binary's output")
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
        bad.append("port-class: the port's CharonSecProtocolOptions was not found")
    for label, expect in list(DEFAULTS.items()) + list(COMPARE.items()):
        got = rows.get(label, [None])[0]
        if got is None:
            bad.append("%s: the case did not measure it" % label)
        elif got != str(expect):
            bad.append("%s: got %s and the port claims %d" % (label, got, expect))
    for label, why in (("no-tls13", "TLSv13 0x0304, which 6.1.3 cannot negotiate"),
                       ("no-dtls12", "DTLSv12 0xfefd, which 6.1.3 cannot negotiate")):
        if rows.get(label, [None])[0] != "1":
            bad.append("%s: a default answered %s" % (label, why))
    if rows.get("failures", [None])[0] != "0":
        bad.append("the case reported %s failures" % rows.get("failures", ["?"])[0])
    for line in bad:
        print("DIFFERS " + line)
    if bad:
        sys.exit(1)
    print("compared %d defaults, %d comparisons and 2 version 6.1.3 cannot honour"
          % (len(DEFAULTS), len(COMPARE)))


if __name__ == "__main__":
    sys.exit(main())
