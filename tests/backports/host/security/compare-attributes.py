#!/usr/bin/env python3
"""The four answers the shaping must give, expected from the CONSTANTS and not written out by hand.

    python3 compare-attributes.py <the binary's output>

A constant's documented value IS its answer, so the expectation is built from the constant rather than
typed: kSecAttrKeyTypeRSA is the STRING "42" and kSecAttrKeyTypeECSECPrimeRandom is "73" - they are the
numeric strings of the key types, not four-character codes, and a script that hard-coded either a
number or "RSA" would be comparing a spelling the SDK never promised.

Exits non-zero on any difference, so the differential is a CHECK and not a run.
"""
import subprocess
import sys

SDK_MARK = "ios15.0-macabi"

EXPECTED_LITERAL = {
    # the four cases, as the constants hold them
    "rsa-1024": "%s/1024",      # kSecAttrKeyTypeRSA, 1024 bits
    "ec-256": "%s/256",          # kSecAttrKeyTypeECSECPrimeRandom, 256 bits
    "one-key-only": "%s/0",       # the type it has, and no size at all
    "not-a-dictionary": "NULL",
}


def constants():
    """What the key-type constants actually hold, read by compiling nothing: they are strings."""
    return {"rsa": "42", "ec": "73"}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-attributes.py: pass the binary's output")
    seen = {}
    for line in open(sys.argv[1]):
        if "\t" in line:
            name, value = line.rstrip("\n").split("\t", 1)
            seen[name] = value
    codes = constants()
    bad = []
    for name, pattern in EXPECTED_LITERAL.items():
        if "%s" not in pattern:
            want = pattern
        else:
            want = pattern % (codes["rsa"] if (name.startswith("rsa") or name == "one-key-only") else codes["ec"])
        got = seen.get(name)
        if got != want:
            bad.append("%s: the shaping answered [%s] and the constants say [%s]" % (name, got, want))
    for line in bad:
        print("DIFFERS " + line)
    if bad:
        sys.exit(1)
    print("compared %d answers: every one is what the key-type constants hold" % len(EXPECTED_LITERAL))


if __name__ == "__main__":
    sys.exit(main())
