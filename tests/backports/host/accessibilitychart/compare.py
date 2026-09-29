#!/usr/bin/env python3
"""accessibilitychart/compare.py - the two answers against what the case declares.

Three of the cases the port's differential asks are expected to differ: the host's own -copyWithZone:
drops three value-typed fields, which was measured and is written down in
facts/Accessibility/Accessibility.md, and expected-differences.tsv carries what each side answers on
each of them. Everything else must answer the same.

Four things fail here, and each is a failure of the case rather than a detail it can pass over:

  * a case that differs and is not declared
  * a declared case whose system-side answer has moved
  * a declared case whose port-side answer has moved
  * a declared case that no longer differs at all, so the declaration is stale

A check that examined nothing would pass every one of these, so the summary line counts the cases it
read and the differences it compared, and both come from the two files on disk.

    Usage: compare.py <host.tsv> <port.tsv> <expected-differences.tsv>
"""

import sys


def read_rows(path):
    """label -> value, from the two programs' output. A label twice is a case that cannot be compared."""
    rows = {}
    for number, line in enumerate(open(path), 1):
        label, tab, value = line.rstrip("\n").partition("\t")
        if not tab:
            print("FAIL: %s line %d is not a label and a value: %r" % (path, number, line))
            sys.exit(1)
        if label in rows:
            print("FAIL: %s names %s twice, so the two answers cannot be lined up" % (path, label))
            sys.exit(1)
        rows[label] = value
    return rows


def read_declarations(path):
    """label -> (system, port, why), from the file the case declares its differences in."""
    declared, why = {}, {}
    for number, line in enumerate(open(path), 1):
        if number == 1 or not line.strip():
            continue
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 4:
            print("FAIL: %s line %d has no reason, so a difference could be declared without one"
                  % (path, number))
            sys.exit(1)
        declared[parts[0]] = (parts[1], parts[2])
        why[parts[0]] = "\t".join(parts[3:])
    return declared, why


def main():
    host_path, port_path, expected_path = sys.argv[1:4]
    host = read_rows(host_path)
    port = read_rows(port_path)
    declared, why = read_declarations(expected_path)

    failures = 0
    for label in sorted(set(host) | set(port)):
        system, mine = host.get(label), port.get(label)
        if label in declared:
            want_system, want_port = declared[label]
            if system != want_system:
                print("DECLARED DIFFERENCE MOVED (system): %s answers %r, the case declares %r"
                      % (label, system, want_system))
                print("  why: " + why[label])
                failures += 1
            if mine != want_port:
                print("DECLARED DIFFERENCE MOVED (port): %s answers %r, the case declares %r"
                      % (label, mine, want_port))
                print("  why: " + why[label])
                failures += 1
            if system == mine:
                print("DECLARED DIFFERENCE GONE: %s answers %r on both sides, so the case is stale"
                      % (label, system))
                print("  why: " + why[label])
                failures += 1
            else:
                print("declared difference: %s: system %s, port %s" % (label, system, mine))
        elif system != mine:
            print("UNDECLARED DIFFERENCE: %s: system %r, port %r" % (label, system, mine))
            failures += 1

    compared = len(set(host) | set(port))
    print("cases read: %d a side; declared differences: %d; undeclared or moved: %d"
          % (compared, len(declared), failures))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
