#!/usr/bin/env python3
"""Compare the two transcripts line by one: check.py apple.txt ours.txt

Every line is `name<TAB>value`. A value that starts with `str:` is a string and is compared
exactly; every other value is a number, compared with the tolerance the name's scalar asks for:
1e-12 relative for the `d.` half, 1e-6 for the `f.` half. `nan`, `inf` and `-inf` are compared as
the strings they print as. A name on one side and not the other is a difference, and so is a
repeated name.

Three values are not compared but *recorded*, in DIVERGENCES below: the port's answer is written
down beside the host's, with the reason, and both are then compared exactly against what this run
produced. A difference anywhere else still fails, and one of the three moving - in either column -
fails as well, so a recorded divergence is a measurement that cannot quietly become another one.
No tolerance is widened for them and none is widened anywhere.

Prints one `ok ` line per value, one `NAMED` line per recorded divergence with its reason, and one
`DIFFER` line per difference, and exits 1 if anything differs. The largest relative difference over
the values that were compared is printed last, so a commit message can quote a number this run
produced.
"""
import math
import sys

TOLERANCE = {"d": 1e-12, "f": 1e-6}

# The port's answers that are not the host's, each recorded with the host's beside it and the
# reason, and each compared exactly against what this run produced. Measured on 2026-10-04, and
# the decision these three are decided by is the coordinator's (coordination/wave-2026-10-03/
# QUEUE.md, the v-fin-spatial ruling): named, measured divergences, not a widened tolerance.
DIVERGENCES = {
    "d.rotation.eulerAngles.xyz.z": (
        "0.61327141523361206",
        "0.61327139037901746",
        "the last term of the extraction, read off a matrix the two sides print the same "
        "seventeen digits for; four parts in 1e8, and the other two terms of the same extraction "
        "agree to one ulp"),
    "d.rotation.eulerAngles.zxy.y": (
        "0.40688398480415344",
        "0.40688398209126875",
        "the last term of that order's extraction, on the same matrix, and six formulas computed "
        "on it - the Float-rounded ones included - reach no better than 4e-9 of the host's"),
    "f.description": (
        "str:(radians: 0.5235988)",
        "str:(radians: 0.52359873)",
        "the Float half's degrees to radians rounds three ulps from the host's, on operands both "
        "sides agree on: Float.pi prints 3.1415925 either way"),
}


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
    differences, worst, agreed, named = [], 0.0, 0, 0
    for name in order:
        if name in DIVERGENCES:
            host_value, port_value, reason = DIVERGENCES[name]
            if name not in ours:
                differences.append((name, host_value, "<no value>"))
            elif ours[name] != port_value or apple[name] != host_value:
                differences.append((name, apple[name], ours[name]))
            else:
                named += 1
            continue
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
    for name, (host_value, port_value, reason) in sorted(DIVERGENCES.items()):
        print("NAMED %s\thost=%s\tours=%s\t%s" % (name, host_value, port_value, reason))
    for name, theirs, mine in differences:
        print("DIFFER %s\thost=%s\tours=%s" % (name, theirs, mine))
    print("values: %d, agree: %d, named divergences: %d, differ: %d, largest relative difference: %g"
          % (len(order), agreed, named, len(differences), worst))
    sys.exit(1 if differences else 0)


main()