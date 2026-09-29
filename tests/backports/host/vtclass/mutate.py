#!/usr/bin/env python3
"""One mutation of the port's value file. A mutation that does not apply is an error, not a pass."""
import sys

path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
if text.count(old) != 1:
    sys.exit("mutate.py: %r appears %d times in %s, so the mutation would not be a mutation"
             % (old, text.count(old), path))
open(path, "w").write(text.replace(old, new, 1))
