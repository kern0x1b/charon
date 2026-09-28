#!/usr/bin/env python3
"""One mutation of the port's time functions. The three are the three relations the case asks: the
round trip, the agreement with CFAbsoluteTime, and the monotonic reading."""
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
if text.count(old) != 1:
    sys.exit("mutate.py: %r appears %d times in %s, so the mutation would not be a mutation"
             % (old, text.count(old), path))
open(path, "w").write(text.replace(old, new, 1))
print("mutated: " + old.strip()[:60])
