#!/usr/bin/env python3
"""The fourteen accessors, differences NAMED - and the handler count is the one that matters most.

    python3 compare-protocol-metadata-accessors.py <the binary's output>

Every block-taking accessor must answer false AND leave the handler count at 0. A handler that ran would
hand the caller a certificate chain, an OCSP response, a signature algorithm or a distinguished name
that were never negotiated, and the caller would act on them. `handler-calls` is therefore checked as its
own row rather than folded into the four return values, because a single shared counter is what makes one
run tell you a handler fired.
"""
import sys

NULLS = ["negotiated-protocol", "server-name", "peer-public-key", "create-secret", "create-secret-ctx",
         "early-data", "chain-access", "ocsp-access", "sigalg-access", "dn-access", "handler-calls"]
# the two enums that HAVE a member meaning none, so 0 is documented and not a port-invented sentinel
ENUMS = {"protocol-version": 0, "ciphersuite": 0}
COMPARE = {"peers-same-object": 1, "peers-two-objects": 1, "peers-one-null": 0, "peers-both-null": 1,
           "challenge-same": 1, "challenge-one-null": 0,
           "alive-in-scope": 1, "deallocated-after-scope": 0}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-protocol-metadata-accessors.py: pass the binary's output")
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
        bad.append("port-class: the port's CharonSecProtocolMetadata was not found")
    for label, expect in [(l, 0) for l in NULLS] + list(ENUMS.items()) + list(COMPARE.items()):
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
    print("compared %d answers, the two enums that have a none-member, and the handler count"
          % (len(NULLS) + len(ENUMS) + len(COMPARE)))


if __name__ == "__main__":
    sys.exit(main())
