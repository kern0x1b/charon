#!/usr/bin/env python3
"""compare.py PORTFILE HOSTFILE - the port's answers against the host's, input by input.

    python3 compare.py <port out> <host out>

Prints one DIFFERS line per input the two sides disagree on, then a summary that says how many pairs
were compared. Exits 0 only when the two files hold the same answer for the same input and nothing is
missing from either, so a run that compared fewer pairs than the port printed cannot look green.

Unlike sensorkit-names' compare.py there is no separate name list here: the INPUT is the case, so the
inputs themselves are what must agree, and a case the host never printed is a case nobody compared.
"""
import sys


def rows(path, tag):
    out = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) == 3 and parts[0] == tag:
            out[parts[1]] = parts[2]
    return out


def main():
    if len(sys.argv) != 3:
        sys.exit("compare.py: pass the port output and the host output")
    port, host = sys.argv[1], sys.argv[2]
    p, h = rows(port, "PORT"), rows(host, "HOST")
    bad = []
    for name in sorted(set(p) | set(h)):
        if name not in p:
            bad.append("%r: the port printed no row for it" % name)
        elif name not in h:
            bad.append("%r: the host printed no row for it" % name)
        elif p[name] != h[name]:
            bad.append("%r: the port answers [%s] and the host answers [%s]" % (name, p[name], h[name]))
    for line in bad:
        print("DIFFERS " + line)
    compared = len(set(p) & set(h))
    print("sensorkit-tombstones: %d inputs compared, %d differing%s"
          % (compared, len(bad), "" if compared and not bad else "  <- SEE ABOVE"))
    return 0 if (not bad and compared == len(p) == len(h)) else 1


sys.exit(main())