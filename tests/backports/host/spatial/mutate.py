#!/usr/bin/env python3
"""mutate.py FILE FROM TO - the one-token change the control below makes.

Refused unless FROM occurs exactly once, so a control that cannot be planted says so instead of
reporting a mutant that was never applied (2026-10-03: a planted run over an unplanted file
reported a mutant as applied four times running).
"""
import sys

path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as handle:
    text = handle.read()
count = text.count(old)
if count != 1:
    sys.exit("%s: %r occurs %d times, not once" % (path, old, count))
with open(path, "w") as handle:
    handle.write(text.replace(old, new))
print("planted: %s -> %s" % (old, new))