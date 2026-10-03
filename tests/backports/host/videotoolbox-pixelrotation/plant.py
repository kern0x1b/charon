#!/usr/bin/env python3
"""plant.py - copy one file with one exact line replaced, or report that the needle is not there.

    plant.py SOURCE TARGET FROM TO

Exits non-zero when the needle is absent. That is the whole point: a plant that quietly did not apply
measures the unmutated probe and reports the mutant as caught, which is the same shape of output a real
catch has.
"""
import sys


def main():
    if len(sys.argv) != 5:
        sys.exit("plant.py: pass SOURCE TARGET FROM TO")
    source, target, needle, replacement = sys.argv[1:5]
    text = open(source, encoding="utf-8").read()
    if needle not in text:
        print("plant.py: %r is not in %s" % (needle, source), file=sys.stderr)
        return 1
    open(target, "w", encoding="utf-8").write(text.replace(needle, replacement, 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
