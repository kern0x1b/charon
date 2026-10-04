#!/usr/bin/env python3
"""What the framework's OWN -init stores, and what its alias classes hold, read out of the pinned tree.

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

The same tree is also the only place that says what a deprecated ALIAS CLASS holds. Almost all of them hold
nothing:

    src/darwin/Framework/CHIP/zap-generated/MTRStructsObjc.mm:14469
        @implementation MTRTestClusterClusterSimpleStruct : MTRUnitTestingClusterSimpleStruct
        @dynamic a;
        @dynamic b;
        ...
        @end

`@dynamic` with no ivars and no accessor of its own, so every member lives in the superclass's storage and
there is ONE storage for the pair. A port that synthesises an ivar per member has TWO, and no header says so:
the SDK's declaration of the alias is a property redeclaration, which reads identically either way. This
tool therefore reads that table too, for the one class of the 60 whose accessors are written by hand and
forward to a differently named member of the superclass:

    src/darwin/Framework/CHIP/MTRDeviceControllerFactory.mm:1393
        - (BOOL)startServer
        {
            return self.shouldStartServer;
        }

`MTRControllerFactoryParams`'s own annotation says "Please use shouldStartServer" for `startServer` and
"Please use the storage property" for `storageDelegate` - prose, so three of the four are readable out of the
header and the fourth is not readable anywhere but here.

    git clone --depth 1 --branch v1.7-te2 https://github.com/project-chip/connectedhomeip
    python3 tools/matter-init-source.py --upstream <checkout>/src/darwin/Framework/CHIP \\
        --tag v1.7-te2 --commit 99a81bd32986c5292b0b1c9245c8e247c2ad717d -o tools/matter-init-defaults.tsv \\
        --alias-out tools/matter-alias-accessors.tsv

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
# `- (BOOL)startServer` and `- (void)setStartServer:(BOOL)startServer`: the getter and the setter of one
# member, on one line each, which is how the framework writes the whole of MTRControllerFactoryParams.
GETTER = re.compile(r"^-\s*\([^)]*\)\s*(\w+)\s*$")
SETTER = re.compile(r"^-\s*\(void\)\s*(set\w+:)\s*\([^)]*\)\s*\w+\s*$")
SOURCES = (".m", ".mm", ".h")


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


def read_aliases(path, root):
    """[(class, member, kind, successor, file, line)] what an alias class's own accessors forward to.

    An alias class is one the framework's own HEADER marks deprecated and declares as a subclass:
    `MTRDeviceControllerFactory.h:232 MTR_DEPRECATED("Please use MTRDeviceControllerFactoryParams", ...)` over
    `:156 @interface MTRControllerFactoryParams : MTRDeviceControllerFactoryParams`. The superclass comes
    from the header and not from the `@implementation` line, because the framework writes that line with no
    superclass at all - `MTRDeviceControllerFactory.mm:1383 @implementation MTRControllerFactoryParams` - and
    the class's shape is the one the header declares.

    Of those classes 59 have an `@implementation` that is `@dynamic` and nothing else, which means they hold
    no storage of their own and there is nothing to record; a block with any other line in it is the one
    class whose accessors are written by hand, and the table names what each of them forwards to, because the
    header's own deprecation text does not for one of the four ("Please use the storage property") and a
    header that cannot place a member is not a place to guess from.

    The body is read to its `{`, so a member whose body is not one statement is reported by the run and not
    written into the table: `return self.storage;` and `self.storage = storageDelegate;` are the two shapes
    here, and anything else is a reader this version does not understand rather than a rule.
    """
    found = []
    lines = open(path, errors="replace").read().split("\n")
    for index, line in enumerate(lines):
        head = IMPLEMENTATION.match(line)
        if not head or head.group(3):
            continue
        name = head.group(1)
        if deprecated_aliases(root).get(name) is None:
            continue
        walk, end = index + 1, len(lines)
        while walk < end and not lines[walk].startswith("@end"):
            if not lines[walk].strip().startswith("@dynamic"):
                break
            walk += 1
        else:
            # `@dynamic` and nothing else: the alias holds no storage of its own and there is nothing here.
            continue
        walk, end = index + 1, len(lines)
        while walk < end and not lines[walk].startswith("@end"):
            stripped = lines[walk].strip()
            getter, setter = GETTER.match(stripped), SETTER.match(stripped)
            member = None
            if getter:
                member = getter.group(1)
            elif setter:
                lead = setter.group(1)[:-1]
                member = lead[3].lower() + lead[4:]
            if member:
                body, statements = walk + 1, []
                while body < end and lines[body].strip() != "{":
                    body += 1
                body += 1
                while body < end and lines[body].strip() != "}":
                    statements.append(lines[body])
                    body += 1
                found.append((name, member, "getter" if getter else "setter",
                              forwards_to(" ".join(statements)), os.path.relpath(path, root), walk + 1))
            walk += 1
    return [entry for entry in found if entry[3]]


# The framework's own headers, over the same root: `MTR_DEPRECATED(` / `API_DEPRECATED(` on the line above an
# `@interface X : S`. The annotation is accumulated while its parentheses are open, because the framework
# wraps a long one - `MTRDeviceControllerFactory.h:232` opens the macro and :233 carries the text and every
# release - and a reader that stops at the first line read 99 of the 120 and missed the one class this table
# exists for.
DEPRECATED = re.compile(r"^(?:MTR_|API_)DEPRECATED\(")
INTERFACE_HEAD = re.compile(r"^@interface\s+(\w+)\s*:\s*(\w+)")
ALIASES_CACHE = {}


def deprecated_aliases(root):
    """{class: superclass} for every class this tree's own headers mark a deprecated subclass of another.

    Read from the tree rather than passed in, so the table cannot name a class the tree does not declare and
    the run cannot be told which classes to look at. 120 classes at the tag this repository pins, and the
    caller counts the ones it actually emitted.
    """
    if ALIASES_CACHE:
        return ALIASES_CACHE
    for path in sources(root):
        if not path.endswith(".h"):
            continue
        said, balance = "", 0
        for line in open(path, errors="replace"):
            stripped = line.strip()
            if stripped.startswith(("MTR_DEPRECATED", "API_DEPRECATED")):
                said, balance = stripped, stripped.count("(") - stripped.count(")")
                continue
            if said and balance > 0:
                said += " " + stripped
                balance += stripped.count("(") - stripped.count(")")
                continue
            if not said:
                continue
            head = INTERFACE_HEAD.match(stripped)
            if head:
                ALIASES_CACHE[head.group(1)] = head.group(2)
            said, balance = "", 0
    return ALIASES_CACHE


FORWARD = re.compile(r"\bself\.(\w+)")


def forwards_to(body):
    """The superclass member one accessor body names, or None for a body this reader does not read.

    A getter is `return self.shouldStartServer;` and a setter is `self.shouldStartServer = startServer;`, so
    the member is the `self.<name>` in the body. The whole body is read rather than its first line, because
    the framework's first accessor opens with a three-line comment and reading one line found nothing in it.
    A body naming more than one member is refused rather than guessed: there is none in the tree this is read
    from, and one that appeared would be a case the port could not copy either.
    """
    named = FORWARD.findall(body)
    return named[0] if len(set(named)) == 1 else None


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--upstream", required=True,
                        help="the checkout's src/darwin/Framework/CHIP directory")
    parser.add_argument("--tag", required=True, help="the tag the checkout is at")
    parser.add_argument("--commit", required=True, help="the commit that tag names")
    parser.add_argument("-o", "--out", required=True, help="the TSV to write")
    parser.add_argument("--alias-out", required=True,
                        help="the TSV of what a deprecated alias class's own accessors forward to")
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

    forwarded, dynamic_only = [], 0
    for path in sources(arguments.upstream):
        forwarded.extend(read_aliases(path, arguments.upstream))
    with open(arguments.alias_out, "w") as out:
        out.write("# upstream\tproject-chip/connectedhomeip\t%s\t%s\tApache-2.0\n"
                  % (arguments.tag, arguments.commit))
        out.write("# what\tone line per accessor a deprecated alias class writes BY HAND, and the member of"
                  " the superclass it forwards to\n")
        out.write("# columns\tclass\tmember\tkind\tforwards_to\tfile\tline\n")
        for name, member, kind, target, where, line in forwarded:
            out.write("%s\t%s\t%s\t%s\t%s:%d\n" % (name, member, kind, target, where, line))
    alias_classes = sorted(set(entry[0] for entry in forwarded))
    print("alias-accessors: %d hand-written accessor(s) over %d class(es), from %s at %s"
          % (len(forwarded), len(alias_classes), arguments.tag, arguments.commit[:12]))
    print("alias-accessors: wrote %s" % arguments.alias_out)
    if alias_classes:
        print("alias-accessors: the classes whose accessors are written by hand, and are the framework's"
              " only ones: %s" % ", ".join(alias_classes))
    return 0


if __name__ == "__main__":
    sys.exit(main())