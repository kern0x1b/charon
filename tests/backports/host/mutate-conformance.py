#!/usr/bin/env python3
"""Break ONE defined method of a class, so a conformance check has to notice.

    python3 mutate-conformance.py FILE.m

Used by tests/backports/host/protocol-conformance.sh to make its own mutant. A separate file and not
a heredoc inside the shell script, because a regex inside a heredoc is three levels of escaping and
the last version of it did not compile - which a reader cannot tell from a mutant that simply did not
bite.

The method head it matches is one followed by a body, so it renames a DEFINED method rather than
touching a declaration or an ivar list: an earlier version matched the class's ivars, rewrote a line
that compiled fine, and left the mutant looking green.
"""
import re
import sys


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    path = sys.argv[1]
    source = open(path).read()
    # a method head: "- (type)selector" on one line, or continued, immediately followed by "{"
    match = re.search(r"^(- \([^)]*\)[^\n]*(?:\n[^\n-][^\n]*)*\n\{)", source, re.M)
    if not match:
        print("mutate-conformance: no method definition in %s" % path)
        return 1
    head = match.group(1)
    renamed = re.sub(r"\)\s*(\w+)\n\{$", r")charonMutatedSelector\n{", head, count=1)
    if renamed == head:
        print("mutate-conformance: matched a head it could not rename in %s" % path)
        return 1
    open(path, "w").write(source.replace(head, renamed, 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
