#!/usr/bin/env python3
"""plant.py - replace one exact line of one file, or report that the needle is not there.

    plant.py FILE FROM TO

Exits non-zero when the needle is absent. That is the whole point: a plant that quietly did not apply
measures the unmutated tree and reports the mutant as caught, which is the same shape of output a real
catch has.
"""
import sys


def main():
    if len(sys.argv) != 4:
        sys.exit("plant.py: pass FILE FROM TO")
    path, needle, replacement = sys.argv[1:4]
    text = open(path, encoding="utf-8").read()
    if needle not in text:
        print("plant.py: %r is not in %s" % (needle, path), file=sys.stderr)
        return 1
    open(path, "w", encoding="utf-8").write(text.replace(needle, replacement, 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
