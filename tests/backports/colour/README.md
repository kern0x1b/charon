# colour - what this directory holds, and what is owed

One probe and nothing else yet. `AXNameFromColor` is **owed**, not carried: the host answers a curated
named-colour vocabulary with a nearest-match rule, not the components of a colour, so the work is a
black-box fit and not a lookup, and the fit has not been done. There is no registry row for the
function - not an `absent` one either, because `absent` says the API is not carried and that is not
what is true here.

`probe.m` is the host's own function over nineteen colours, chosen so that every pair shows something a
component lookup could not produce:

| colour | the host answers | a component lookup would say |
| --- | --- | --- |
| (128,128,128) and (200,200,200) | `gray` and `gray` | two different grays |
| (255,165,0) | `bright orange` | orange |
| (0,0,255) | `very dark blue` | blue |
| (255,255,0) | `very light vibrant yellow` | yellow |
| (128,0,128) and (255,0,255) | `dark magenta` and `dark magenta` | purple and magenta |

Build and run it with the host's SDK, no user data anywhere in it:

```
xcrun clang -target arm64-apple-macos26.0 -isysroot "$(xcrun --show-sdk-path)" -fobjc-arc -O0 -w \
    tests/backports/colour/probe.m -framework Foundation -framework Accessibility -framework AppKit \
    -o /tmp/colour-probe && /tmp/colour-probe
```

## Owed

The full fit, in the order it has to be done, because each step's result decides the next:

1. **Probe densely.** A regular 17x17x17 sRGB grid, 20,000 random colours, the named edge cases above,
   and the neighbours of every grid point where the answer changes. Nothing is read out of the
   framework's binary or its resources; the names are facts of the answers the function returned.
2. **Identify the vocabulary and the rule.** The set of names the function ever answers, then the
   decision rule: nearest prototype in which space? Fit sRGB, linear sRGB, Lab and OKLab, with per-name
   prototype centroids and the boundaries between two names found by bisecting along the grid edges
   where the answer changes.
3. **Implement the port's own rule and the port's own prototype table** from those measurements. Not
   Apple's numbers, and not a table copied out of a binary: a table we measured, with a name for where
   it came from.
4. **Report the agreement over a held-out sample** of at least 200,000 colours that were **not** in the
   fit set, with the exact number of disagreements and where they cluster. A row is `implemented` only
   for what agrees, and the rest is an owed line carrying the number.
5. **A differential** over the held-out sample that declares each disagreement class with a reason, so
   the port and the host are compared rather than assumed.
