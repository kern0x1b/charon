#!/usr/bin/env python3
"""The padding each algorithm must map to, and the broken pair NAMED on a difference.

    python3 compare-padding.py <the binary's output>

The expectation is the SDK's OWN enumerator, read by the case at run time and compared here against the
same enumerator - so the numbers are the header's and not a spelling copied out of a document. The case
also prints a WRONG line of its own, and a run that produced one of those is a failure whatever this
script says.
"""
import sys


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-padding.py: pass the binary's output")
    seen, wrong = {}, []
    for line in open(sys.argv[1]):
        line = line.rstrip("\n")
        if line.startswith("WRONG\t"):
            wrong.append(line.split("\t", 1)[1])
        elif "\t" in line:
            name, value = line.split("\t", 1)
            seen[name] = value
    expected = {
        "pkcs1-sha1": 32770,     # 0x8002
        "pkcs1-sha224": 32771,    # 0x8003
        "pkcs1-sha256": 32772,    # 0x8004
        "pkcs1-sha384": 32773,    # 0x8005
        "pkcs1-sha512": 32774,    # 0x8006
        "ecdsa-sha256": 0,        # kSecPaddingNone: the release cannot carry it
    }
    bad = list(wrong)
    for name, want in expected.items():
        got = seen.get(name)
        if got is None or got != str(want):
            bad.append("%s: answered [%s] and the header's enumerator is %d" % (name, got, want))
    for line in bad:
        print("DIFFERS " + line)
    if bad:
        sys.exit(1)
    print("compared %d algorithm/padding pairs: every one is the header's own enumerator" % len(expected))


if __name__ == "__main__":
    sys.exit(main())
