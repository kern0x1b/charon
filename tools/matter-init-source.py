#!/usr/bin/env python3
"""What the framework's OWN -init stores, read out of the pinned upstream tree.

The port answers 26.2's Matter, and 26.2's Matter is the Darwin framework of project-chip/connectedhomeip.
That framework writes an initialiser for most of its plain data classes, and what that initialiser stores is
NOT always the type's zero:

    charon/.agent-work/upstreams/chip/src/darwin/Framework/CHIP/MTRCluster.mm:117
        @implementation MTRReadParams
        - (instancetype)init
        {
            if (self = [super init]) {
                _filterByFabric = YES;
                _assumeUnknownAttributesReportable = YES;
            }
            return self;
        }

so a port that writes `_filterByFabric = NO` because NO is the zero of a BOOL disagrees with the framework it
implements, and no header says so: `MTRCluster.h` declares the member and nothing about its initial value.

This tool reads those stores out of the tree and writes the table tools/matter-generate.py consumes. It is a
READER, not a transcription: every line of the table is a line of the upstream source, with the file and the
line it came from, so a reader can open it and check. The expression is stored as the source writes it and
the generator does the converting, which keeps one place where a C literal is decided.

    git clone --depth 1 --branch v1.7-te2 https://github.com/project-chip/connectedhomeip
    python3 tools/matter-init-source.py --upstream <checkout>/src/darwin/Framework/CHIP \\
        --tag v1.7-te2 --commit 99a81bd32986c5292b0b1c9245c8e247c2ad717d -o tools/matter-init-defaults.tsv

A store this reader does not understand is NOT dropped: it is written with an `expression` the generator
reports by name, so an expression added upstream shows up as a named gap instead of as a silent zero.
"""
import argparse
import os
import re
import sys

# `@implementation Name`, optionally `: Super`, optionally `(Category)` - and a CATEGORY's @implementation is
# the class's own method list as far as the runtime is concerned, so `MTRSubscribeParams (Deprecated)`'s
# `-init` IS the -init `[[MTRSubscribeParams alloc] init]` runs. That is the whole of the reading for
# MTRSubscribeParams' three non-zero members: the class's own @implementation has no -init and the one that
# runs is in the category.
IMPLEMENTATION = re.compile(r"^@implementation\s+(\w+)\s*(?::\s*(\w+))?\s*(?:\(\s*(\w*)\s*\))?\s*$")
# `- (instancetype)init`, on one line, which is how every one of the 1,014 initialisers in this tree is
# written. Anything else is named by the run rather than guessed at.
INITIALISER = re.compile(r"^-\s*\(\s*instancetype\s*\)\s*init\s*$")
STORE = re.compile(r"^\s*_(\w+)\s*=\s*(.+?);\s*$")
SOURCES = (".m", ".mm")


def sources(root):
    """Every implementation file under the tree, in a stable order, so two runs produce the same table."""
    found = []
    for base, directories, names in os.walk(root):
        directories.sort()
        for name in sorted(names):
            if name.endswith(SOURCES):
                found.append(os.path.join(base, name))
    return found


def read(path, root):
    """[(class, category, member, expression, file, line)] every store an -init of this tree makes."""
    found = []
    lines = open(path, errors="replace").read().split("\n")
    for index, line in enumerate(lines):
        head = IMPLEMENTATION.match(line)
        if not head:
            continue
        name, category = head.group(1), head.group(3) or ""
        walk = index + 1
        while walk < len(lines) and not lines[walk].startswith("@end"):
            if INITIALISER.match(lines[walk].strip()):
                body = walk + 1
                while body < len(lines) and not lines[body].strip().startswith("}"):
                    store = STORE.match(lines[body])
                    if store:
                        found.append((name, category, store.group(1), store.group(2),
                                      os.path.relpath(path, root), body + 1))
                    body += 1
            walk += 1
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--upstream", required=True,
                        help="the checkout's src/darwin/Framework/CHIP directory")
    parser.add_argument("--tag", required=True, help="the tag the checkout is at")
    parser.add_argument("--commit", required=True, help="the commit that tag names")
    parser.add_argument("-o", "--out", required=True, help="the TSV to write")
    arguments = parser.parse_args()

    if not os.path.isdir(arguments.upstream):
        print("no such directory: %s" % arguments.upstream, file=sys.stderr)
        return 2

    stores, classes, unknown = [], set(), []
    for path in sources(arguments.upstream):
        for name, category, member, expression, where, line in read(path, arguments.upstream):
            classes.add(name)
            stores.append((name, member, expression, where, line))
            if not expression:
                unknown.append((name, member, where, line))
    # Two stores of one member in one class is the framework's own inconsistency and the generator has to be
    # able to say which one it took, so the file order decides and the count is printed.
    seen, order = {}, []
    for name, member, expression, where, line in stores:
        key = (name, member)
        if key not in seen:
            order.append(key)
        seen.setdefault(key, []).append((expression, where, line))

    with open(arguments.out, "w") as out:
        out.write("# upstream\tproject-chip/connectedhomeip\t%s\t%s\tApache-2.0\n"
                  % (arguments.tag, arguments.commit))
        out.write("# what\tone line per store an - (instancetype)init of that tree makes, in the source's own"
                  " expression\n")
        out.write("# columns\tclass\tmember\texpression\tfile\tline\n")
        for key in order:
            for expression, where, line in seen[key]:
                out.write("%s\t%s\t%s\t%s:%d\n" % (key[0], key[1], expression, where, line))

    repeated = sum(1 for key in order if len(seen[key]) > 1)
    print("init-defaults: %d stores over %d classes with an -init, from %s at %s"
          % (len(order), len(classes), arguments.tag, arguments.commit[:12]))
    print("init-defaults: wrote %s" % arguments.out)
    if repeated:
        print("init-defaults: %d members are stored by more than one -init; the generator takes the first"
              % repeated)
    if unknown:
        for name, member, where, line in unknown:
            print("init-defaults: UNREAD store %s.%s at %s:%d" % (name, member, where, line))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())