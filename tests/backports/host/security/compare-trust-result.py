#!/usr/bin/env python3
"""The port's verdict against the HOST'S OWN SecTrustGetTrustResult, difference NAMED.

    python3 compare-trust-result.py <the binary's output>

The host's copy is reached by dlopen of the system framework and dlsym off that handle: this case
defines the same name, so calling the name would compare the port with itself. The verdict is compared as
a PAIR - status AND result - because a port that returns the right status with the wrong result, or the
other way round, is a different failure from either alone.
"""
import sys


def main():
    if len(sys.argv) < 2:
        sys.exit("compare-trust-result.py: pass the binary's output")
    rows, wrong = {}, []
    for line in open(sys.argv[1]):
        line = line.rstrip("\n")
        if line.startswith("WRONG\t"):
            wrong.append(line.split("\t", 1)[1])
        elif "\t" in line:
            p = line.split("\t")
            rows[p[0]] = p[1:]
    bad = list(wrong)
    if rows.get("host-symbols", [None])[0] != "both":
        bad.append("host-symbols: the host's own function was not found, so nothing was compared")
    v = rows.get("verdict", [])
    if len(v) < 4:
        bad.append("verdict: the case did not reach it")
    elif v[0] != v[1] or v[2] != v[3]:
        bad.append("verdict: port status %s result %s, and the host says status %s result %s"
                   % (v[0], v[2], v[1], v[3]))
    for label in ("null-out", "null-trust"):
        got = rows.get(label, [])
        if len(got) < 2:
            bad.append("%s: the case did not ask" % label)
        elif got[0] != got[1] or got[0] != "-50":
            bad.append("%s: port [%s] host [%s], and both claim errSecParam (-50)" % (label, got[0], got[1]))
    for line in bad:
        print("DIFFERS " + line)
    if bad:
        sys.exit(1)
    print("compared the verdict as a status/result pair, and 2 refusals, against the host's own function")


if __name__ == "__main__":
    sys.exit(main())
