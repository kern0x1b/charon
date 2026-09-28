"""portshape -- what the BUILT library answers for a class's members.

The port's side of the AuthenticationServices shape check, read out of the linked binary rather than out
of the source text. Two reasons, and the second is the one that matters:

  * the port's objects are armv7 and this host is arm64, so the library cannot be dlopen'd here and the
    runtime cannot be asked about it -- the file has to be read;
  * a check that reads the source text is a check on the *text*. The first version searched for a
    selector's spelling and reported selectors the file did not contain, and missed selectors it did.

`otool -oV` prints each class's method list out of the binary: the selector, its types and its
implementation address, for the instance list and the metaclass's own list. That is the runtime's view of
the class as the linker left it, which is what an application will call.

An inherited method is visible here too, because the dump lists what the class resolves, which is the
control: `+new` comes from NSObject, and a port that does not declare it still has it.

Usage: portshape <library> <cases-file>
"""
import os
import subprocess
import sys


def methods_of(library):
    """(class, selector, kind) for every method the built library binds, from otool's class dump.

    Only a class's own `baseMethods` counts. A property name, a protocol's member and a superclass's
    member all appear in the dump as `name` lines too, and taking them all is how this read a removed
    method as still bound.
    """
    out = subprocess.run(["otool", "-oV", library], capture_output=True, text=True).stdout
    classes, current, inMetaclass = {}, None, False
    # The field names the dump prints. A line that starts with one of them is describing whatever class
    # is current, not declaring a class -- and "superclass 0x0 _OBJC_CLASS_$_NSObject" is how the
    # previous version lost the class it was in and reported every member of every class missing.
    # Which list a `name` line belongs to. The dump prints the class's own method list under
    # `baseMethods` and its property list under `baseProperties`, and a property list keeps the
    # property's name whether or not an accessor was written -- `@dynamic provider;` leaves the name
    # in baseProperties and takes the method out of baseMethods. Recording every `name` line therefore
    # reported a property as a bound method, and the first version of this read
    # "name 0x7b16 provider" under baseProperties as proof that a mutation had not taken when it had.
    inMethods = False
    for line in out.split("\n"):
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("baseMethods"):
            inMethods = True
            continue
        if stripped.startswith(("baseProtocols", "ivars", "baseProperties", "baseClassMethods",
                                "layout", "weakIvarLayout", "ro")):
            inMethods = False
            continue
        # "_OBJC_CLASS_$_Name" opens an instance list; "_OBJC_METACLASS_$_Name" opens the class list.
        # The class line carries two address columns before the symbol, so the symbol is found rather
        # than tested for at the start of the line: requiring it there found no classes at all, which
        # is a check that reports every member missing and reads like a port that implements nothing.
        # A class-list entry is a line of two bare addresses and then the class symbol, and nothing
        # else in the dump has that shape: the isa and superclass lines carry a field name and one
        # address before the symbol, and treating those as entries is what lost the class entirely.
        # A class-list entry is "<address> <address> <class symbol>" and the first address is printed
        # bare, without 0x, so testing the columns for the 0x prefix found no entries at all. The
        # discriminator that does hold is the field name: every other line carrying a class symbol in
        # this dump is an isa, a superclass or a data pointer, and "name" is the selector line -- which
        # has to be excluded here or it is consumed as a class entry and no method is ever recorded.
        parts = stripped.split()
        if len(parts) >= 3 and parts[0] not in ("isa", "superclass", "data", "cache", "vtable", "name"):
            symbol = parts[2]
            if symbol.startswith("_OBJC_METACLASS_$_"):
                current, inMetaclass = symbol[len("_OBJC_METACLASS_$_"):], True
            elif symbol.startswith("_OBJC_CLASS_$_"):
                current, inMetaclass = symbol[len("_OBJC_CLASS_$_"):], False
        elif stripped.startswith("name") and current and inMethods:
            # "name    0x3f08 copyWithZone:" -- the address and then the selector.
            parts = stripped.split(None, 2)
            if len(parts) == 3 and parts[1].startswith("0x"):
                classes.setdefault(current, set()).add((parts[2], "class" if inMetaclass else "instance"))
    return classes


def main(argv):
    if len(argv) != 3:
        raise SystemExit("usage: portshape <library> <cases-file>")
    library, cases_file = argv[1], argv[2]
    if not os.path.isfile(library):
        # There is nothing to report, which is a failure of the run rather than a verdict about a
        # member, so this one does stop: with no library there is no comparison to make.
        sys.stderr.write("no built library at %s: point BUILT at a build of this worktree's sources\n"
                         % library)
        sys.exit(1)
    bound = methods_of(library)

    print("class\tselector\tkind\tstate\tport")
    asked = missing = 0
    for line in open(cases_file).read().split("\n"):
        if not line or line[0] == "#":
            continue
        className, selector, kind, state = line.split("\t")[:4]
        asked += 1
        have = bound.get(className, set())
        present = (selector, kind) in have
        if not present:
            missing += 1
        print("%s\t%s\t%s\t%s\t%s" % (className, selector, kind, state, "yes" if present else "no"))
    # The same standing rule as compare(): this reports, it does not decide. A member the library does
    # not bind is not a failure here -- a member the header marks must-be-unavailable is *supposed* not
    # to be bound -- so exiting non-zero here made the run abort before the comparison could say which
    # of the missing ones are the four the release marks unavailable.
    sys.stderr.write("portshape: %d cases, %d the library does not bind (a verdict is the comparison's "
                     "to give, not this one's)\n" % (asked, missing))


if __name__ == "__main__":
    main(sys.argv)
