#!/usr/bin/env python3
"""Is the hue word a partition of the hue angle?

Nearest prototype in four spaces gives 37-40%, so that is not the rule. The 28 words include the
neighbouring pairs - blue green, spring green, pink magenta, magenta pink, red pink, red orange,
yellow orange - which is what a hue circle divided into named sectors looks like. This asks whether the
answer is a contiguous interval of the hue angle, and how well a one-dimensional partition of that angle
predicts it.

    Usage: fit-angle.py <fit.tsv>
"""

import collections
import math
import sys

MODIFIERS = ("very", "light", "dark", "pastel", "grayish", "vibrant", "bright")


def split(name):
    words = name.split()
    while words and words[0] in MODIFIERS:
        words.pop(0)
    return " ".join(words) or name


def oklab(r, g, b):
    out = []
    for value in (r / 255.0, g / 255.0, b / 255.0):
        out.append(value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4)
    x, y, z = out
    l = 0.4122214708 * x + 0.5363325363 * y + 0.0514459929 * z
    m = 0.2119034982 * x + 0.6806995451 * y + 0.1073969566 * z
    s = 0.0883024619 * x + 0.2817188376 * y + 0.6299787005 * z
    cube = lambda v: (v ** (1 / 3) if v > 0 else -((-v) ** (1 / 3)))
    l_, m_, s_ = cube(l), cube(m), cube(s)
    return (0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)


def angle(r, g, b):
    """The hue angle in OKLab, with the chroma it was read at."""
    L, a, bb = oklab(r, g, b)
    return math.atan2(bb, a) % (2 * math.pi), math.hypot(a, bb), L


def main():
    points = {}
    for line in open(sys.argv[1]):
        if line.startswith("#"):
            continue
        _, r, g, b, name = line.rstrip("\n").split("\t")
        points[(int(r), int(g), int(b))] = split(name)
    print("distinct colours: %d" % len(points))

    # The neutral names are not a hue at all: they are what a colour with almost no chroma answers.
    neutral = {"gray", "black", "white"}
    chromatic = [(angle(r, g, b), hue) for (r, g, b), hue in points.items() if hue not in neutral]
    print("chromatic points: %d   neutral: %d" % (len(chromatic), len(points) - len(chromatic)))

    # Sort by angle and look for runs: a partition of the angle is a set of contiguous intervals.
    chromatic.sort(key=lambda pair: pair[0][0])
    runs = []
    for values, hue in chromatic:
        if runs and runs[-1][0] == hue:
            runs[-1][2] = values[0]
            runs[-1][3] += 1
        else:
            runs.append([hue, values[0], values[0], 1])
    print("contiguous runs of the angle, in angle order: %d" % len(runs))
    for hue, low, high, count in runs:
        print("  %-16s %6.3f .. %6.3f  %6d" % (hue, low, high, count))

    # How many points does a one-dimensional partition explain? Take the angle midpoints between
    # consecutive runs and classify by the run whose interval the angle falls in.
    if len(runs) > 1:
        edges = []
        for i in range(len(runs)):
            high = runs[i][2]
            low = runs[(i + 1) % len(runs)][1]
            gap = (low - high) % (2 * math.pi)
            edges.append((high + gap / 2.0) % (2 * math.pi))
        agree = 0
        for (a, chroma, L), hue in chromatic:
            for i, edge in enumerate(edges):
                # the run is i if the angle is at or after edge[i]
                if (a - edge) % (2 * math.pi) < (edges[(i + 1) % len(edges)] - edge) % (2 * math.pi):
                    if runs[i][0] == hue:
                        agree += 1
                    break
        print("one-dimensional angle partition: %d / %d chromatic = %.4f"
              % (agree, len(chromatic), agree / len(chromatic)))


if __name__ == "__main__":
    main()
