#!/usr/bin/env python3
"""The two SSLCipherSuite setters, differences NAMED.

    python3 compare-protocol-options-ciphersuite.py <the binary's output>

The two `not-translated` rows are the point: SSLCipherSuite values are wire values and
tls_ciphersuite_t values are IANA numbers for the same suites, and only the VALUE notices a translation.
The growth rows matter too - the list is grown with realloc, and a case that only appends two never
exercises the move.
"""
import sys

VALUES = {"count": 2, "first-as-given": 0x0001, "second-as-given": 0x002F, "past-end": 0,
          "group-as-given": 1, "list-unchanged-by-group": 2, "first-unchanged-by-group": 0x0001,
          "count-after-third": 3, "third-as-given": 0xC02F, "group-after-third": 1,
          "count-after-growth": 23, "last-after-growth": 0x0100 + 19,
          "null-options": 1, "alive-in-scope": 1, "deallocated-after-scope": 0}
NOT_TRANSLATED = {"first-not-translated": 1, "second-not-translated": 1}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-protocol-options-ciphersuite.py: pass the binary's output")
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
        bad.append("port-class: the port's CharonSecProtocolCiphersuite was not found")
    for label, expect in list(VALUES.items()) + list(NOT_TRANSLATED.items()):
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
    print("compared %d values, 2 not-translated rows, and a list grown past its first capacity"
          % len(VALUES))


if __name__ == "__main__":
    sys.exit(main())
