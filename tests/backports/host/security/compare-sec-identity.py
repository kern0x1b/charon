#!/usr/bin/env python3
"""The six rows, on a STAND-IN ref, differences NAMED.

    python3 compare-sec-identity.py <the binary's output>

The stand-in is an ephemeral in-memory CFDataRef handed to the wrapper where a SecIdentityRef would go,
because no real SecIdentityRef can be made on this Mac: every SecIdentity.h factory is __IPHONE_NA on
iOS and SecIdentityCreate is not declared at all. NOTHING HERE MEASURES A REAL IDENTITY - that is a guest
measurement and is owed. What is measured is the wrapper's OWNERSHIP, which is the part that can be wrong.
No keychain is touched anywhere in this case.
"""
import sys

# copy-ref-retains is the COUNTED +1, not an inference from pointer equality: a mutation that drops the
# CFRetain in sec_identity_copy_ref leaves every other row here untouched, so without it that mutation
# is invisible to this case.
VALUES = {"copy-ref-same": 1, "copy-ref-retains": 1, "create-present": 1, "certificates-copied": 1,
           "copy-survives-source-change": 1, "access-true": 1, "handler-runs-per-certificate": 1,
           "access-empty-true": 1, "handler-runs-on-empty": 0, "copy_ref-of-nil": 0,
           "local-identity-holds": 1, "local-identity-present": 1}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-sec-identity.py: pass the binary's output")
    rows, wrong = {}, []
    for line in open(sys.argv[1]):
        line = line.rstrip("\n")
        if line.startswith("WRONG\t"):
            wrong.append(line.split("\t", 1)[1])
        elif "\t" in line:
            p = line.split("\t")
            rows[p[0]] = p[1:]
    bad = list(wrong)
    # holder-class prints found/MISSING rather than a number
    if rows.get("holder-class", [None])[0] != "found":
        bad.append("holder-class: the port's options holder was not found")
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
    print("compared %d ownership assertions on a STAND-IN ref; no keychain was touched" % len(VALUES))


if __name__ == "__main__":
    sys.exit(main())
