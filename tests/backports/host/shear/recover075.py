#!/usr/bin/env python3
"""Recover the HOST's (phase, base) per destination sample from its own bytes, at 0.75 on the vertical.

The four exact scales cannot separate the centre's algebraic arrangements, and none of ten of them changes the
count, so the question moves one level down: rather than guessing the expression, identify the row and the base
the host's bytes name. For one destination sample the answer is a function of (phase, base) alone - the
release's own Q14 row, the tap walk, the row's own sum - so every (phase, base) is tried and the ones that
reproduce the stored value are printed. A sample that no (phase, base) reproduces is a fact about the model,
not a rounding near miss, and is printed as NOTHING rather than hidden.

The address is `data + along*rowBytes + cross*pixelBytes`, so on the vertical the tap walk is the source's ROW
and the destination's `cross` is the source's COLUMN. The table and the destinations come from dump075.c, which
reads them out of the caller's own filter object and the caller's own shear.
"""
import math
import sys

PHASES = 64
WIDTH = 8
K0 = 3
RECIP = 1.3333333333333333
ROWS = {}
SRC = []


def load(path):
    cases = []
    cur = None
    for line in open(path):
        f = line.split()
        if f[0] == "FILTER":
            globals()["RECIP"] = float(f[2])
            globals()["PHASES"] = int(f[8])
            globals()["WIDTH"] = int(f[10])
            globals()["K0"] = int(f[12])
        elif f[0] == "ROW":
            ROWS[int(f[1])] = [int(x) for x in f[2:-1]]
        elif f[0] == "CASE":
            if cur is not None:
                cases.append(cur)
            cur = [int(f[1]), int(f[2]), int(f[3]), []]
        elif f[0] == "DEST" and cur is not None:
            cur[3].append([int(x) for x in f[1:]])
    if cur is not None:
        cases.append(cur)
    return cases


def val(ph, base, cross, extend):
    """One destination sample read at a named row and base: the release's own weights and the row's own sum."""
    w = ROWS[ph]
    total = sum(w)
    acc = 0
    for k in range(WIDTH):
        at = base + k - K0
        if at < 0 or at >= len(SRC):
            v = (SRC[0][cross] if at < 0 else SRC[len(SRC) - 1][cross]) if extend else 0.0
        else:
            v = SRC[at][cross]
        acc += w[k] * v
    if total == 0:
        return 0.0
    got = acc / total
    return math.floor(got + 0.5) if got >= 0 else math.ceil(got - 0.5)


def port_says(along, cross, translate, slope):
    """The row and base the port's own mapping and phase rule select: anchor DISTRIBUTED, fraction TRUNCATED.

    Both halves are what CharonShear.h and CharonResampling.h now do; the rounded variant is one line away in
    `rule075` and is what this column showed before the vertical was changed to truncate.
    """
    A = len(SRC)
    position = along + 0.5 + translate + slope * (cross + 0.5)
    centre = position * RECIP + A * (1.0 - RECIP) - 0.5
    whole = math.floor(centre)
    return int(math.floor((centre - whole) * PHASES)), whole


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "dump075.txt"
    cases = load(path)
    for line in open(path):
        f = line.split()
        if f[0] == "SRC":
            SRC.append([int(x) for x in f[1:]])
    translate = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
    slope = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    mode = int(sys.argv[4]) if len(sys.argv) > 4 else 0
    print("width %d K0 %d phases %d recip %.17g, %d shears in the table" % (WIDTH, K0, PHASES, RECIP, len(ROWS)))
    for t, sl, m, dests in cases:
        if t != 0 or sl != 0 or m != mode:
            continue
        print("=== translate %g slope %g mode %d (%s): the (phase, base) each sample answers"
              % (translate, slope, m, "extend" if m else "background"))
        for along in range(len(dests)):
            row = []
            for cross in range(len(dests[along])):
                hits = [(ph, b) for ph in range(PHASES) for b in range(-4, 8)
                        if val(ph, b, cross, bool(m)) == dests[along][cross]]
                pph, pb = port_says(along, cross, translate, slope)
                row.append("c%d %6d %s port(%d,%d)" % (cross, dests[along][cross],
                                                        ("," .join("(%d,%d)" % h for h in hits[:3]) or "NOTHING"),
                                                        pph, pb))
            print("  along %d  %s" % (along, "  ".join(row)))


if __name__ == "__main__":
    main()
