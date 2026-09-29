#!/usr/bin/env python3
"""What the flag reads back after each thing the caller did, and the broken step NAMED.

    python3 compare-network-fetch.py <the binary's output>

What is checked is the ROUND TRIP, because that is all an inert flag owes: what a caller sets is what a
caller reads back. Whether the release then acts on it is a different claim, and the fact file says the
release does not - 6.1.3 resolves a trust against the anchors it was given and never fetches.
"""
import sys

# label: (OSStatus, value, what the caller did)
EXPECTED = {
    "made-trust":  (0, None, "SecTrustCreateWithCertificates on the fixture"),
    "default":     (0, 0,    "read before anything was set: not allowed"),
    "set-true":    (0, None, "the setter's own status"),
    "after-true":  (0, 1,    "set true, so true must come back"),
    "after-false": (0, 0,    "set false, so false comes back - a flag, not a latch"),
    "null-trust":  (-50, None, "a NULL trust is errSecParam, not a crash"),
}


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-network-fetch.py: pass the binary's output")
    seen, wrong = {}, []
    for line in open(sys.argv[1]):
        line = line.rstrip("\n")
        if line.startswith("WRONG\t"):
            wrong.append(line.split("\t", 1)[1])
        elif "\t" in line:
            parts = line.split("\t")
            seen[parts[0]] = (int(parts[1]), int(parts[2]) if len(parts) > 2 else None)
    bad = list(wrong)
    for label, (want_status, want_value, why) in EXPECTED.items():
        got = seen.get(label)
        if got is None:
            bad.append("%s: the case did not reach it (%s)" % (label, why))
            continue
        if got[0] != want_status:
            bad.append("%s: status [%d] and the port claims [%d] (%s)" % (label, got[0], want_status, why))
        elif want_value is not None and got[1] != want_value:
            bad.append("%s: read back [%d] and the port claims [%d] (%s)"
                       % (label, got[1], want_value, why))
    for line in bad:
        print("DIFFERS " + line)
    if bad:
        sys.exit(1)
    print("compared %d steps of the round trip, and %d of them carry a value" % (len(EXPECTED), 3))


if __name__ == "__main__":
    sys.exit(main())
