#!/usr/bin/env python3
"""Check that every selector a host differential renames for its own port is one the port defines.

    tests/backports/host/check-private-selectors.py [--prefix PREFIX]... <test object or binary> <port object>...

A differential compiles the backport's sources into the same process as the framework they sit beside, so
the port's classes and the selectors its categories carry are renamed and the test drives the port's answer
and the host's side by side. Nothing checks the two halves against each other: a selector the test declares
in its own category and calls, and that no port object defines, is a link-time no-op and an
"unrecognized selector sent to instance" at run time - after the build, and with nothing in the gate to see
it, because the gate reads the registry of what the backports carry, not what a test asks for.

So this asks the two binaries themselves. The test holds every selector it names as a string; the port
objects hold every selector they define in their method symbols. A string with one of the renaming prefixes
that no port object defines is the failure above, and it is reported with the selector and the objects it
was looked for in. Prefixes default to the four this tree renames with; a differential that renames with
another one passes it. `--source` names a source of the test, and a prefixed literal that source concatenates
(`[@"charonHostSet" stringByAppendingString:...]`) is a piece of a name rather than a name of its own, so it
is not judged: see fragments() for the measurement that made that distinction necessary.
"""
import argparse
import os
import re
import subprocess
import sys

PREFIXES = ("charonHost", "charonHost_", "charon_host_", "CharonHost")

# -[Class(Category) setFoo:bar:] and +[Class foo]: the selector is what follows the space
DEFINED = re.compile(r"[-+]\[[A-Za-z_][A-Za-z0-9_]*(?:\([A-Za-z0-9_]*\))? ([A-Za-z_][A-Za-z0-9_:]*)\]")
# a renamed class is a class, not a selector: the test holds its name as a string too, and it is answered
CLASS = re.compile(r"_OBJC_(?:META)?CLASS_\$_([A-Za-z_][A-Za-z0-9_]*)$")
# every send names its selector as a symbol of its own, so what an object names is what it does not define
SENT = re.compile(r"_objc_msgSend\$([A-Za-z_][A-Za-z0-9_:]*)")
# and a name may be answered by a C symbol as well as by a method: dlsym(RTLD_DEFAULT, "CharonHostUICommandTagShare")
# finds a renamed constant, which is what a test asks for when it looks a constant up that way
DEFINED_SYMBOL = re.compile(r"^[0-9a-f]*\s*[a-zA-Z]\s+_?([A-Za-z_][A-Za-z0-9_:]*)$")


def selectors(paths):
    """Every selector the objects define, whole, every selector they send, and every selector name they hold
    as a string - which is how a test that builds a name at run time spells it."""
    defined, named, sent_by = set(), set(), set()
    for path in paths:
        symbols = subprocess.run(["xcrun", "nm", path], capture_output=True, text=True)
        for line in symbols.stdout.splitlines():
            exported = DEFINED_SYMBOL.match(line.strip())
            if exported:
                defined.add(exported.group(1))
            found = DEFINED.search(line)
            if found:
                defined.add(found.group(1))
            named_class = CLASS.search(line.strip())
            if named_class:
                defined.add(named_class.group(1))
            sent = SENT.search(line.strip())
            if sent:
                sent_by.add(sent.group(1))
        strings = subprocess.run(["xcrun", "strings", "-a", path], capture_output=True, text=True)
        named.update(strings.stdout.split())
    return defined, named, sent_by


def whole(name, prefixes):
    """Whether a string that starts with a prefix is a whole selector rather than a piece of one. A
    differential that builds selector names at run time holds the prefix and the format in the test's
    strings, and those are not selectors anything has to define."""
    for prefix in prefixes:
        if not name.startswith(prefix) or len(name) == len(prefix):
            continue
        if "%" in name or "@" in name:
            return False
        if ":" in name:
            return True
        rest = name[len(prefix):]
        return prefix.endswith("_") or rest[0].isupper()
    return False


def fragments(sources):
    """The prefixed strings the sources build a longer name out of, which are not selectors of their own.

    A differential that renames with a prefix often spells the name it sends at run time, and the pieces of it
    are literals in the source: `[@"charonHostSet" stringByAppendingString:...]` builds
    charonHostSetAllowsExpensiveNetworkAccess: and never sends the bare charonHostSet. The strings pass cannot
    tell a whole selector from a piece of one - both are a token that starts with a prefix - so it reported
    "names the selector charonHostSet, which none of ... defines", which is a name nothing sends and which the
    check's own failure describes ("it would be an unrecognized selector at run time") as absent when it is
    never sent. Only a literal the source concatenates is dropped: every other prefixed string is judged as
    before, so a test that names a selector no port object defines is still reported."""
    found = set()
    if not sources:
        return found
    for path in sources:
        try:
            with open(path, encoding="utf-8", errors="replace") as handle:
                text = handle.read()
        except OSError:
            continue
        for name in re.findall(r'@"([A-Za-z_][A-Za-z0-9_]*)"\s*(?:\n\s*)?stringByAppending', text):
            found.add(name)
    return found


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--prefix", action="append", default=[], help="a prefix the differential renames with; repeatable")
    parser.add_argument("--source", action="append", default=[], help="a source of the test, to tell a whole selector from a piece of one; repeatable")
    parser.add_argument("objects", nargs="+", help="the test's object or binary first, then the port's objects")
    options = parser.parse_args()
    if len(options.objects) < 2:
        parser.error("a test and at least one port object, so there is something to compare")
    prefixes = tuple(options.prefix) + PREFIXES
    # the test is asked what it names, every object is asked what it defines: a selector the test's own code
    # defines is answered as legitimately as one the port's is
    defined, named, sent_by = selectors(options.objects)
    pieces = fragments(options.source)
    renamed = {name for name in sent_by | {n for n in named if whole(n, prefixes)} if whole(name, prefixes)}
    wanted = renamed - defined - pieces
    if not wanted:
        print("note %d renamed selectors are named, all of them defined by %s" % (len(renamed), ", ".join(options.objects)))
        return 0
    for name in sorted(wanted):
        print("FAIL %s names the selector %s, which none of %s defines: it would be an unrecognized selector at run time"
              % (options.objects[0], name, ", ".join(options.objects)))
    print("%d of the %d renamed selectors are named and not defined" % (len(wanted), len(renamed)))
    return 1


if __name__ == "__main__":
    sys.exit(main())
