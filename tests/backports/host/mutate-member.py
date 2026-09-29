#!/usr/bin/env python3
"""Remove ONE member a class really defines for a protocol, so a conformance check must notice.

    python3 mutate-member.py PROTOCOL CLASS SDK FILE method|getter

A mutant is only worth anything if the member it removes is one the PROTOCOL REQUIRES. An earlier
mutator renamed whichever method came first in the file, which for CharonMetalLibrary was
-functionNames - a method no protocol asks for - so the class still compiled and still conformed, and
the mutant read as green while testing nothing. This one asks protocol-members.py which selectors
that protocol needs and that class DEFINES, and removes the first of the requested kind from the
class's own @implementation. So the member removed is a required one by construction.

Writes only the file it is given, and the caller passes a SCRATCH COPY under the worktree's
.agent-work/runs - never a file in the tree.
"""
import importlib.util
import os
import re
import sys


def load(path):
    spec = importlib.util.spec_from_file_location("protocol_members", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    if len(sys.argv) != 6:
        print(__doc__)
        return 2
    protocol, cls, sdk, path, kind = sys.argv[1:6]
    here = os.path.dirname(os.path.abspath(__file__))
    pm = load(os.path.join(here, "protocol-members.py"))

    document = pm.ast_for(path, sdk)
    wanted = pm.protocol_members(document, protocol)
    defined = pm.class_defines(document, cls) | pm.synthesised(document, cls)
    removable = sorted(wanted & defined)
    if not removable:
        print("mutate-member: %s defines no member %s requires, so there is nothing to remove"
              % (cls, protocol))
        return 1
    getter = "-" + re.sub(r"^set(.+):$", lambda m: m.group(1)[:1].lower() + m.group(1)[1:], "").lstrip("-")
    if kind == "getter":
        chosen = [s for s in removable if s.startswith("-") and not s.startswith("-set")]
        if not chosen:
            print("mutate-member: %s defines no property getter for %s" % (cls, protocol))
            return 1
    else:
        chosen = [s for s in removable if not s.startswith("-set")]
        if not chosen:
            print("mutate-member: %s defines no method for %s" % (cls, protocol))
            return 1
    selector = chosen[0]
    name = selector.lstrip("-+")

    source = open(path).read()
    # the method DEFINITION with its body. The return type is allowed to CONTAIN COLONS - the head is
    # - (id<MTLDevice>)device - and an earlier version excluded them, so it matched nothing and every
    # mutant read as green while removing nothing. The selector's own parameters are matched
    # explicitly rather than by "no colons on the line".
    pattern = re.compile(
        r"^([-+] \([^)]*\)\s*%s(?:\s*:\s*\([^)]*\)\s*\w+)*\s*\n\{)" % re.escape(name), re.M)
    match = pattern.search(source)
    if not match:
        print("mutate-member: could not find the definition of %s in %s" % (name, os.path.basename(path)))
        return 1
    # the body, by brace depth from the '{' the head ends with
    depth, index = 0, match.end() - 1
    for index in range(match.end() - 1, len(source)):
        depth += (source[index] == "{") - (source[index] == "}")
        if depth <= 0:
            break
    # the head starts at its own line, and only COMMENT lines above it go too
    start = match.start()
    head = start
    for back in range(start - 1, -1, -1):
        line_start = source.rfind("\n", 0, back) + 1
        line = source[line_start:back]
        if not line.strip() or not line.lstrip().startswith("//"):
            break
        head = line_start
    # what follows the method, with the blank line the removal left behind
    tail = source[index + 1:]
    open(path, "w").write(source[:head] + tail.lstrip("\n"))
    print("removed %s from %s" % (selector, os.path.basename(path)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
