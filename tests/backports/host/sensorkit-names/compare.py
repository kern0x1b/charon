#!/usr/bin/env python3
"""compare.py PORTFILE HOSTFILE NAMELIST - the port's values against the host's, name by name.

    python3 compare.py <port out> <host out> <names.txt>

Three ways it must be red, and all three are run by run.sh: a value that differs, a name one side did
not print, and an input with no HOST rows at all - a comparison of nothing is not a comparison, and the
summary line says how many pairs were compared so a run that compared nothing cannot look green.
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
    if len(sys.argv) != 4:
        sys.exit("compare.py: pass the port output, the host output and the name list")
    port, host, namelist = sys.argv[1], sys.argv[2], sys.argv[3]
    names = []
    for line in open(namelist):
        line = line.strip()
        if not line or line.startswith(("//", "static", "}")):
            if line.startswith("}"):
                break
            continue
        names.append(line.rstrip(",").strip('"'))
    p, h = rows(port, "PORT"), rows(host, "HOST")
    bad = []
    compared = 0
    for name in names:
        if name not in p:
            bad.append("%s: the port printed no row for it" % name)
        if name not in h:
            bad.append("%s: the host's framework printed no row for it" % name)
        if name in p and name in h:
            compared += 1
            if p[name] != h[name]:
                bad.append("%s: the port holds [%s] and the host holds [%s]" % (name, p[name], h[name]))
    for line in bad:
        print("DIFFERS " + line)
    print("sensorkit-names: %d names compared, %d differing%s"
          % (compared, len(bad), "" if compared else "  <- COMPARED NOTHING"))
    return 0 if (bad == [] and compared == len(names)) else 1


sys.exit(main())
