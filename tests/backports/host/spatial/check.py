#!/usr/bin/env python3
"""Compare the two transcripts line by line: check.py apple.txt ours.txt

Every line is `name<TAB>value`. A value that starts with `str:` is a string and is compared
exactly; every other value is a number, compared with the tolerance the name's scalar asks for:
1e-12 relative for the `d.` half, 1e-6 for the `f.` half. `nan`, `inf` and `-inf` are compared as
the strings they print as. A name on one side and not the other is a difference, and so is a
repeated name.

Prints one `ok ` line per value and one `DIFFER` line per difference, and exits 1 if anything
differs. The largest relative difference is printed last, so a commit message can quote a number
this run produced.
"""
import math
import sys

TOLERANCE = {"d": 1e-12, "f": 1e-6}


def read(path):
    values, order = {}, []
    with open(path) as handle:
        for number, line in enumerate(handle, 1):
            line = line.rstrip("\n")
            if not line:
                continue
            assert "\t" in line, "%s:%d is not `name<TAB>value`: %r" % (path, number, line)
            name, value = line.split("\t", 1)
            assert name not in values, "%s:%d repeats the name %s" % (path, number, name)
            values[name] = value
            order.append(name)
    return values, order


def close(apple, ours, tolerance):
    if apple in ("nan", "inf", "-inf") or ours in ("nan", "inf", "-inf"):
        return apple == ours
    a, b = float(apple), float(ours)
    if math.isnan(a) or math.isnan(b):
        return math.isnan(a) and math.isnan(b)
    if a == b:
        return True
    return abs(a - b) <= tolerance * max(abs(a), abs(b))


def main():
    apple, order = read(sys.argv[1])
    ours, _ = read(sys.argv[2])
    differences, worst, agreed = [], 0.0, 0
    for name in order:
        if name not in ours:
            differences.append((name, apple[name], "<no value>"))
            continue
        mine = ours[name]
        if apple[name].startswith("str:") or mine.startswith("str:"):
            if apple[name] == mine:
                agreed += 1
            else:
                differences.append((name, apple[name], mine))
            continue
        tolerance = TOLERANCE.get(name.split(".", 1)[0], 1e-12)
        if close(apple[name], mine, tolerance):
            agreed += 1
            a, b = float(apple[name]), float(mine)
            if a != b:
                worst = max(worst, abs(a - b) / max(abs(a), abs(b)))
        else:
            differences.append((name, apple[name], mine))
    for name, theirs, mine in differences:
        print("DIFFER %s\thost=%s\tours=%s" % (name, theirs, mine))
    print("values: %d, agree: %d, differ: %d, largest relative difference: %g"
          % (len(order), agreed, len(differences), worst))
    sys.exit(1 if differences else 0)


main()