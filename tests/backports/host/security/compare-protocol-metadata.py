#!/usr/bin/env python3
"""The three sec_protocol_metadata functions on a port metadata object, differences NAMED.

    python3 compare-protocol-metadata.py <the binary's output>

The two enum getters answer 0, and 0 is NOT a member of either enum - the expectation here is 0 because
it is the only answer that is not a lie about a negotiation, and the ROW is where that cost is stated.
The psk accessor must answer false AND not run the handler: a handler that ran would hand the caller a
PSK and an identity that were never negotiated, and that is a different failure from the return value.
"""
import sys

VALUES = {"tls-version": 0, "tls-ciphersuite": 0, "psk-access": 0, "psk-handler-calls": 0,
          "alive-in-scope": 1, "deallocated-after-scope": 0}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-protocol-metadata.py: pass the binary's output")
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
        bad.append("port-class: the port's CharonSecProtocolMetadata was not found, so nothing was checked")
    if rows.get("is-metadata", [None])[0] != "1":
        bad.append("is-metadata: the object does not conform to OS_sec_protocol_metadata")
    for label, expect in VALUES.items():
        got = rows.get(label, [None])[0]
        if got is None:
            bad.append("%s: the case did not measure it" % label)
        elif got != str(expect):
            bad.append("%s: got %s and the port claims %d" % (label, got, expect))
    if rows.get("failures", [None])[0] != "0":
        bad.append("the case itself reported %s failures" % rows.get("failures", ["?"])[0])
    for line in bad:
        print("DIFFERS " + line)
    if bad:
        sys.exit(1)
    print("compared %d answers, the protocol conformance, and the ARC balance by deallocation"
          % len(VALUES))


if __name__ == "__main__":
    sys.exit(main())
