#!/usr/bin/env python3
"""make_fixture.py - the second oracle fixture, derived from the first and never hand-edited.

    python3 make_fixture.py        # host-values-one-different.tsv from host-values-real.tsv

The control the host kind needs is a run in which the port is wrong in exactly one place, so that the
row for that unit falls to the named failure and every other unit is still `host`. This flips one row -
NSUnitTemperature's °F base conversion at v = 0 - by moving its port bits one bit off the host's and
marking the verdict `!=`, and copies everything else verbatim. Named rather than positional, so the
fixture it writes does not move when the run's sample list does, and re-running it writes the same file
byte for byte.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REAL = os.path.join(HERE, "host-values-real.tsv")
OTHER = os.path.join(HERE, "host-values-one-different.tsv")
FLIPPED = ("NSUnitTemperature", "°F", "base", "0")


def main():
    lines = open(REAL, encoding="utf-8").read().split("\n")
    out, done = [], 0
    for line in lines:
        if line.startswith("#"):
            out.append(line)
            continue
        fields = line.split("\t")
        if len(fields) == 8 and tuple(fields[:4]) == FLIPPED:
            fields[6] = "%016x" % (int(fields[5], 16) ^ 1)
            fields[7] = "!="
            out.append("\t".join(fields))
            done += 1
            continue
        out.append(line)
    if done != 1:
        print("make_fixture: %d rows matched %r, expected exactly 1" % (done, FLIPPED), file=sys.stderr)
        return 1
    header = ("# derived from host-values-real.tsv by make_fixture.py: one row's port bits moved one bit and its "
              "verdict set to !=, so the control has a unit that is not the host's\n")
    open(OTHER, "w", encoding="utf-8").write(header + "\n".join(out))
    print("wrote %s from %s, one row flipped" % (os.path.basename(OTHER), os.path.basename(REAL)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
