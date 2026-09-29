#!/usr/bin/env python3
"""accessibilitychart/mutate.py - change one line of a copy of the port's source, for mutants.sh.

The copy is a mutant's own, so the change is written to it and never to the tree's file. The line that
is replaced has to be there: a mutant whose line has moved on is not a mutant that survived, it is a
mutant that tested nothing, and the assert is what tells the two apart.

MUTATE_NTH is required and says which occurrence is the mutant's, counted from the front. The three
chart classes each write the same two-line title setter, so a text that matches all three and changed
the first would break one rule and look like it had broken three; naming the occurrence keeps a mutant
to one line and one rule.

    Usage: MUTATE=<file> MUTATE_OLD=<text> MUTATE_NEW=<text> MUTATE_NTH=<n> mutate.py
"""

import os
import sys


def main():
    path = os.environ.get("MUTATE", "")
    old = os.environ.get("MUTATE_OLD", "")
    new = os.environ.get("MUTATE_NEW", "")
    nth_text = os.environ.get("MUTATE_NTH", "")
    if not path or not old or not nth_text:
        print("usage: MUTATE=<file> MUTATE_OLD=<text> MUTATE_NEW=<text> MUTATE_NTH=<n> mutate.py",
              file=sys.stderr)
        return 2
    text = open(path).read()
    found = text.count(old)
    nth = int(nth_text)
    if nth < 1 or found < nth:
        print("the mutant's line is in the file %d times and the mutant wants the %d of them: %r"
              % (found, nth, old), file=sys.stderr)
        return 1
    # Everything before the nth occurrence, then the occurrence is replaced, then everything after it.
    parts = text.split(old)
    head = parts[0]
    for part in parts[1:nth]:
        head += old + part
    tail = parts[nth]
    open(path, "w").write(head + new + tail)
    return 0


if __name__ == "__main__":
    sys.exit(main())
