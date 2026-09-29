#!/usr/bin/env python3
"""The two C string setters, differences NAMED.

    python3 compare-protocol-options-strings.py <the binary's output>

The two `survives-dead-frame` rows are the point and they are checked by READING the held string after
the frame that made it has returned - the same shape as the held-block case, in the C form. A case that
only compared the pointer would pass a port that stored the caller's pointer, which is the failure.
"""
import sys

SURVIVED = {"server-name-survives-dead-frame": 1, "alpn-survives-dead-frame": 1}
VALUES = {"alpn-count": 3, "alpn-past-end": 0, "alpn-after-null": 3, "name-cleared": 0,
          "null-options": 1, "alive-in-scope": 1, "deallocated-after-scope": 0}
# the ALPN list is a LIST, and the order is the order it was offered in
LIST = {"alpn-0": "h2", "alpn-1": "http/1.1", "alpn-2": "spdy/2", "name-after-second": "second.invalid"}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-protocol-options-strings.py: pass the binary's output")
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
        bad.append("port-class: the port's CharonSecProtocolStrings was not found")
    for label, expect in list(SURVIVED.items()) + list(VALUES.items()):
        got = rows.get(label, [None])[0]
        if got is None:
            bad.append("%s: the case did not measure it" % label)
        elif got != str(expect):
            bad.append("%s: got %s and the port claims %d" % (label, got, expect))
    for label, expect in LIST.items():
        got = rows.get(label, [None])[0]
        if got is None:
            bad.append("%s: the case did not read it" % label)
        elif got != expect:
            bad.append("%s: read [%s] and the port claims [%s]" % (label, got, expect))
    if rows.get("failures", [None])[0] != "0":
        bad.append("the case reported %s failures" % rows.get("failures", ["?"])[0])
    for line in bad:
        print("DIFFERS " + line)
    if bad:
        sys.exit(1)
    print("compared %d survives, %d values and %d list entries, in the order they were offered"
          % (len(SURVIVED), len(VALUES), len(LIST)))


if __name__ == "__main__":
    sys.exit(main())
