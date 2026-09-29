#!/usr/bin/env python3
"""The four slice rows on real refs, differences NAMED.

    python3 compare-sec-object-wrappers.py <the binary's output>

The expectation is the RETAIN BALANCE written out - 1, 2, 3, 2, 1 - rather than recomputed from the code,
because the numbers are the claim: a wrapper that retained nothing reads 1/2/1 and a copy_ref that forgot
its CFRetain reads 2/2/2, and only a balance with a step for each is able to tell them apart. The
`released` rows are the other half: a wrapper that retained twice or never released leaves the weak
reference non-nil, and one that over-released would crash in copy_ref rather than answer quietly.
"""
import sys

BALANCE = {"fixture-retain": 1, "after-create": 2, "after-copy": 3,
           "after-copy-release": 2, "after-wrapper-scope": 1}
TRUST = {"trust-retain-before": 1, "trust-after-create": 2, "trust-after-copy": 3}
RELEASED = {"certificate-released": 0, "trust-released": 0}
SAME = ("copy-ref-same", "trust-copy-ref-same")
NULLS = ("copy-ref-null", "copy-ref-trust-null")


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-sec-object-wrappers.py: pass the binary's output")
    rows, wrong = {}, []
    for line in open(sys.argv[1]):
        line = line.rstrip("\n")
        if line.startswith("WRONG\t"):
            wrong.append(line.split("\t", 1)[1])
        elif "\t" in line:
            p = line.split("\t")
            rows[p[0]] = p[1:]
    bad = list(wrong)
    for label, expect in list(BALANCE.items()) + list(TRUST.items()) + list(RELEASED.items()):
        got = rows.get(label, [None])[0]
        if got is None:
            bad.append("%s: the case did not measure it" % label)
        elif got != str(expect):
            bad.append("%s: got %s and the balance says %d" % (label, got, expect))
    for label in SAME:
        if rows.get(label, [None])[0] != "1":
            bad.append("%s: the port did not answer the ref it was given, by pointer equality" % label)
    for label in NULLS:
        if rows.get(label, [None])[0] != "NULL":
            bad.append("%s: a NULL argument must be refused, not crash" % label)
    if rows.get("failures", [None])[0] != "0":
        bad.append("the case reported %s failures" % rows.get("failures", ["?"])[0])
    for line in bad:
        print("DIFFERS " + line)
    if bad:
        sys.exit(1)
    print("compared %d certificate retain counts, %d trust ones, 2 releases, 2 identities and 2 refusals"
          % (len(BALANCE), len(TRUST)))


if __name__ == "__main__":
    sys.exit(main())
