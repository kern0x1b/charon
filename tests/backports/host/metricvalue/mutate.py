#!/usr/bin/env python3
"""One mutation of the shared value machinery, for the differential to catch. The conversion table and
the one place every value class passes through, so a change to it changes every representation in
every framework that includes the header - which is the point of sharing it and the reason the
mutants below are the ones to run."""
import sys
path, name, old, new = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
text = open(path).read()
if text.count(old) != 1:
    sys.exit("mutate.py: %r appears %d times in %s, so the mutation would not be a mutation"
             % (old, text.count(old), path))
open(path, "w").write(text.replace(old, new, 1))
print("mutated %s: %s" % (name, old.strip()[:60]))
