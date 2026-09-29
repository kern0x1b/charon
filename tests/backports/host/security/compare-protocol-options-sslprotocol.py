#!/usr/bin/env python3
"""The two SSLProtocol setters, differences NAMED - and the two `not-translated` rows are the point.

    python3 compare-protocol-options-sslprotocol.py <the binary's output>

kTLSProtocol1 is 4 and tls_protocol_version_TLSv10 is 0x0301 for the same protocol, so a port that
translated between the two enums would read back 769 where the caller set 4. `min-not-translated` and
`max-not-translated` are checked as their OWN rows, because a length or a status would not notice a
translation - only the value does.
"""
import sys

VALUES = {"min-as-given": 4, "max-as-given": 8, "has-range": 1, "max-alone": 7, "min-untouched": 4,
          "empty-has-no-range": 0, "null-options": 1, "alive-in-scope": 1, "deallocated-after-scope": 0}
NOT_TRANSLATED = {"min-not-translated": 1, "max-not-translated": 1}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-protocol-options-sslprotocol.py: pass the binary's output")
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
        bad.append("port-class: the port's CharonSecProtocolSSLProtocol was not found")
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
    print("compared %d values and 2 not-translated rows: the caller's own numbers come back"
          % len(VALUES))


if __name__ == "__main__":
    sys.exit(main())
