#!/usr/bin/env python3
"""The two dispatch_data setters, differences NAMED.

    python3 compare-protocol-options-data.py <the binary's output>

The three byte-valued rows are the point, and the BYTES are compared rather than the pointer: a case that
compared addresses would pass a port holding a freed object, because the address is still readable. The
values are made in a scope that ENDS before they are read, so the caller's own strong reference is gone
and only the port's can keep them alive.
"""
import sys

BYTES = {
    "dh-after-scope": "a finite-field group the caller chose",
    "psk-after-scope": "the pre-shared key bytes",
    "identity-after-scope": "the identity that names it",
}
VALUES = {"pair-present": 1, "psk-count": 1, "after-half-pair": 1, "past-end": 0,
          "null-options": 1, "alive-in-scope": 1, "deallocated-after-scope": 0}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-protocol-options-data.py: pass the binary's output")
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
        bad.append("port-class: the port's CharonSecProtocolData was not found")
    for label, expect in BYTES.items():
        got = rows.get(label, [None])[0]
        if got is None:
            bad.append("%s: the case did not read it" % label)
        elif got != expect:
            bad.append("%s: read [%s] and the port claims [%s]" % (label, got, expect))
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
    print("compared 3 byte values read after their scope ended, a whole pair, and a refused half pair")


if __name__ == "__main__":
    sys.exit(main())
