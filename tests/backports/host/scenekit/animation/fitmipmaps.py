#!/usr/bin/env python3
"""fitmipmaps.py <mipmaps output> : SceneKit's 8x8 renders of the gradient (lambda 5: level 5, 8 texels, bilinear)
against models of the level-5 sample. A level is Metal's own sRGB one; srgblevels.swift's rule, every level made from
the one before it as stored in 8 bits (what SceneKit/CharonSCNRenderer.m, CharonSCNUploadLinearLevels, builds); the
exact box average in linear light from level 0 (the port before); or GL ES 2.0's glGenerateMipmap of the encoded texels
(Metal's unorm level). A sample is filtered in linear light (an sRGB texture) or in the encoding (decoding in the
shader). Prints, per model, the pixels exact and the worst difference in levels; then SceneKit's renders of the image
given as an MTLTexture: of Metal's levels, which must be SceneKit's own renders exactly, and of the rule's, which the
rule's model must give exactly; and how many of Metal's texels of levels 1 to 8 the rule gives from Metal's own level
above, the misses within 0.03 of a tie between two bytes, and the others."""
import re, sys

def lin(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
def enc(l): return l * 12.92 if l <= 0.0031308 else 1.055 * l ** (1 / 2.4) - 0.055

text = open(sys.argv[1]).read()
metal = {m.group(1): eval(m.group(2)) for m in re.finditer(r"metal (\w+) level 5 (\[[^\]]*\])", text)}
rule = eval(re.search(r"rule level 5 (\[[^\]]*\])", text).group(1))
renders = {}
for l in text.splitlines():
    if l.split()[0] in ("scn", "given-metal", "given-rule"):
        renders.setdefault(l.split()[0], []).append(tuple(map(float, l.split()[1:])))
scn = renders["scn"]
chain = [lin(i / 255) for i in range(256)]
for _ in range(5):
    chain = [(chain[2 * i] + chain[2 * i + 1]) / 2 for i in range(len(chain) // 2)]
exact = [round(enc(v) * 255) for v in chain]

def sample(level, u, linear):
    n = len(level); x = u * n - 0.5; i = int(x // 1); f = x - i
    a, b = level[i % n] / 255, level[(i + 1) % n] / 255
    return (enc(lin(a) * (1 - f) + lin(b) * f) if linear else a * (1 - f) + b * f) * 255

models = [("Metal's sRGB level, filtered in linear light", metal["srgb"], True),
          ("the rule's level, filtered in linear light", rule, True),
          ("linear-light box level from level 0, filtered in linear light", exact, True),
          ("linear-light box level from level 0, filtered in the encoding", exact, False),
          ("glGenerateMipmap level, filtered in the encoding", metal["unorm"], False)]
for name, level, linear in models:
    d = [max(abs(round(sample(level, (x + 0.5) / 8 + tx, linear)) - r), abs(round(sample(level, (y + 0.5) / 8 + ty, linear)) - g))
         for tx, ty, x, y, r, g in scn]
    print(f"{name}: level {level}, {d.count(0)} of {len(d)} pixels exact, worst {max(d):.0f}")

def worst(a, b): return max(max(abs(p[4] - q[4]), abs(p[5] - q[5])) for p, q in zip(a, b))
same = sum(p == q for p, q in zip(scn, renders["given-metal"]))
print(f"SceneKit given Metal's levels: {same} of {len(scn)} pixels its own render's, worst {worst(scn, renders['given-metal']):.0f}")
d = [max(abs(round(sample(rule, (x + 0.5) / 8 + tx, True)) - r), abs(round(sample(rule, (y + 0.5) / 8 + ty, True)) - g))
     for tx, ty, x, y, r, g in renders["given-rule"]]
print(f"SceneKit given the rule's levels against the rule's model: {d.count(0)} of {len(d)} pixels exact, worst {max(d):.0f}")

levels = {int(m.group(1)): eval(m.group(2)) for m in re.finditer(r"metal srgb level (\d+) (\[[^\]]*\])", text)}
levels[0] = list(range(256))
hits, ties, others = 0, 0, []
for k in range(1, 9):
    for i, got in enumerate(levels[k]):
        want = enc(sum(lin(v / 255) for v in levels[k - 1][2 * i:2 * i + 2]) / 2) * 255
        if int(want + 0.5) == got: hits += 1
        elif abs(want % 1 - 0.5) <= 0.03: ties += 1
        else: others.append(f"level {k} texel {i}: {want:.2f}, Metal {got}")
print(f"the rule from Metal's level above: {hits} of 255 texels, {ties} missed at a tie, others: {others}")
