#!/usr/bin/env python3
"""The fit: which space, and what the vocabulary is.

The host answers 267 distinct names from 28 words, so a name is a modifier plus a hue word rather than
a table entry. This splits the names that way, then asks which colour space decides the hue word: for
each candidate it takes every fit point answered with a hue word, computes that word's prototype as the
mean of its points in that space, and classifies by nearest prototype. The space with the best
agreement is the one the port will use.

    Usage: fit.py <fit.tsv> [--heldout heldout.tsv]
"""

import collections
import math
import sys

MODIFIERS = ("very", "light", "dark", "pastel", "grayish", "vibrant", "bright")


# The floor lives in sample-floor.py, beside the other fit, because two fits read the same
# sample and a disagreement between two copies of the decision would be silent.
import sample_floor

GRID_ROWS = sample_floor.GRID_ROWS
refuse_small_sample = sample_floor.refuse_small_sample


def read(path):
    rows = []
    for line in open(path):
        if line.startswith("#"):
            continue
        kind, r, g, b, name = line.rstrip("\n").split("\t")
        rows.append((int(r), int(g), int(b), name))
    return rows


def split(name):
    words = name.split()
    while words and words[0] in MODIFIERS:
        words.pop(0)
    return " ".join(words) or name


# The colour spaces, each as three numbers per colour.
def srgb(r, g, b):
    return (r / 255.0, g / 255.0, b / 255.0)


def linear(r, g, b):
    out = []
    for value in (r / 255.0, g / 255.0, b / 255.0):
        out.append(value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4)
    return tuple(out)


def lab(r, g, b):
    x, y, z = linear(r, g, b)
    def f(t):
        return t ** (1 / 3) if t > 216 / 24389 else (841 / 108) * t + 4 / 29
    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def oklab(r, g, b):
    x, y, z = linear(r, g, b)
    l = 0.4122214708 * x + 0.5363325363 * y + 0.0514459929 * z
    m = 0.2119034982 * x + 0.6806995451 * y + 0.1073969566 * z
    s = 0.0883024619 * x + 0.2817188376 * y + 0.6299787005 * z
    l_, m_, s_ = (v ** (1 / 3) if v > 0 else -((-v) ** (1 / 3)) for v in (l, m, s))
    return (0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)


SPACES = {"srgb": srgb, "linear": linear, "lab": lab, "oklab": oklab}


def main():
    if not refuse_small_sample(sys.argv[1]):
        return 1
    rows = read(sys.argv[1])
    hues = collections.Counter(split(name) for _, _, _, name in rows)
    print("fit rows: %d" % len(rows))
    print("distinct names: %d" % len(set(n for _, _, _, n in rows)))
    print("distinct hue words: %d" % len(hues))
    for hue, count in hues.most_common():
        print("  %-16s %d" % (hue, count))
    # The three near-neutrals, counted on their own, because they are not hues and a reader looking for
    # them in the list above has to add them up.
    for name in ("gray", "black", "white"):
        print("near-neutral %-6s %d" % (name, hues.get(name, 0)))

    # Deduplicated points, because the boundary block asks the same colour twice.
    points = {}
    for r, g, b, name in rows:
        points[(r, g, b)] = split(name)

    for label, space in SPACES.items():
        sums = collections.defaultdict(lambda: [0.0, 0.0, 0.0, 0])
        for (r, g, b), hue in points.items():
            v = space(r, g, b)
            acc = sums[hue]
            acc[0] += v[0]; acc[1] += v[1]; acc[2] += v[2]; acc[3] += 1
        prototypes = {h: (a[0] / a[3], a[1] / a[3], a[2] / a[3]) for h, a in sums.items()}
        agree = 0
        for (r, g, b), hue in points.items():
            v = space(r, g, b)
            best, bestDistance = None, None
            for candidate, p in prototypes.items():
                d = sum((v[i] - p[i]) ** 2 for i in range(3))
                if bestDistance is None or d < bestDistance:
                    best, bestDistance = candidate, d
            if best == hue:
                agree += 1
        print("space %-8s hue-word agreement %d / %d = %.4f" % (label, agree, len(points),
                                                                agree / len(points)))


if __name__ == "__main__":
    sys.exit(main())
