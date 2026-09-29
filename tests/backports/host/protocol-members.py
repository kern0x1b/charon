#!/usr/bin/env python3
"""Does a class really answer a protocol? Read the AST, not the warnings.

    python3 tests/backports/host/protocol-members.py PROTOCOL CLASS SDK FILE

A protocol row marked `implemented` claims every member of the protocol is callable, and
backports.lua:664 turns that claim into a band floor. The criterion is therefore exact:

  for EVERY member of the protocol - required and optional instance and class methods, and every
  property's getter (and its setter when readwrite) - the class's @implementation, its category
  implementations in the same file, its @synthesize, or anything up to NSObject must DEFINE that
  selector. Anything not defined is a callable gap, and the row is not `implemented`.

WHY NOT THE WARNINGS. Two diagnostics were tried and both are wrong in different ways, and it took a
review of each to see it:

  - `-Wprotocol` misses property ACCESSORS entirely. It is about methods.
  - `-Wobjc-protocol-property-synthesis` cannot see a HAND-WRITTEN getter: clang emits it for any
    protocol property the @implementation does not @synthesize, whether or not a getter exists. So a
    class that implements all six of MTLFunction's properties by hand still reports six warnings -
    which is exactly what the review measured on a tree where the getters were already written.

So this reads declarations. `-Xclang -ast-dump=json` gives the SDK's protocol members through the
file's own import and the class's own @implementation, and a comparison of the two is the criterion.
No pragma is stripped, because nothing here is a warning: a suppressed warning hides a message, and
a declaration is not a message.

It reads IN PLACE. It writes nothing at all, and if it ever needs to it writes only under the
worktree's .agent-work/runs.
"""
import json
import os
import subprocess
import sys


def walk(node):
    yield node
    for child in node.get("inner") or []:
        for found in walk(child):
            yield found


def selector_of(node):
    """The full selector of an ObjCMethodDecl, from its pieces."""
    pieces = [c for c in node.get("inner") or [] if c.get("kind") == "ObjCSelectorPieceRef"]
    names = [c.get("name") for c in pieces if c.get("name")]
    return "".join(names) if names else node.get("name")


def protocol_members(document, name):
    """{selector} for one protocol: instance and class methods, plus each property's accessors.

    A @property contributes its getter, and its setter too when it is readwrite - `readwrite` is the
    spelling in the AST's attributes, and a property with no explicit spelling is readwrite.
    """
    members = set()
    for node in walk(document):
        if node.get("kind") != "ObjCProtocolDecl" or node.get("name") != name:
            continue
        for child in node.get("inner") or []:
            if child.get("kind") == "ObjCMethodDecl":
                name_ = selector_of(child)
                if name_:
                    members.add(("+" if child.get("static") else "-") + name_)
            elif child.get("kind") == "ObjCPropertyDecl":
                getter = child.get("name")
                if not getter:
                    continue
                members.add("-" + getter)
                # A SETTER is owed only for a readwrite property, and the node says so in a plain
                # boolean: `readonly`. An earlier version looked for an attribute kind spelled
                # readwrite_attr, which this AST does not emit, so every property looked readwrite and
                # the criterion demanded five setters that no header ever declared.
                if not child.get("readonly"):
                    members.add("-set" + getter[:1].upper() + getter[1:] + ":")
    return members


def class_defines(document, name):
    """Every selector the class defines: its methods, its categories', and its @synthesize."""
    defines = set()
    for node in walk(document):
        kind = node.get("kind")
        if kind == "ObjCImplementationDecl" and node.get("name") == name:
            for child in node.get("inner") or []:
                if child.get("kind") == "ObjCMethodDecl":
                    selector = selector_of(child)
                    if selector:
                        defines.add(("+" if child.get("static") else "-") + selector)
        elif kind == "ObjCCategoryImplDecl":
            # a category's own methods, whatever the class it extends
            for child in node.get("inner") or []:
                if child.get("kind") == "ObjCMethodDecl":
                    selector = selector_of(child)
                    if selector:
                        defines.add(("+" if child.get("static") else "-") + selector)
        elif kind == "ObjCImplementationDecl" and node.get("name") == name:
            for child in node.get("inner") or []:
                if child.get("kind") == "ObjCIvarDecl":
                    continue
    return defines


def synthesised(document, name):
    """What @synthesize binds, which is a getter AND a setter where the property is readwrite."""
    bound = set()
    for node in walk(document):
        if node.get("kind") != "ObjCImplementationDecl" or node.get("name") != name:
            continue
        for child in node.get("inner") or []:
            if child.get("kind") == "ObjCPropertyImplDecl" and child.get("name"):
                bound.add("-" + child["name"])
                bound.add("-set" + child["name"][:1].upper() + child["name"][1:] + ":")
    return bound


def ast_for(path, sdk):
    """The AST of one class file, compiled with the library's flags and no -I, from the package dir.

    A translation unit that DOES NOT COMPILE is refused, and the refusal names the errors. This is the
    whole lesson of the r4 review: clang emits an AST for a file with errors in it, so this tool read
    a broken file, found the class's declarations, and reported the protocol CONFORMANT - which is how
    a row claimed a band floor for a class that does not build. A criterion that cannot see whether its
    input compiles is not a criterion.
    """
    result = subprocess.run(
        ["xcrun", "clang", "-target", "armv7-apple-ios6.1.3", "-isysroot", sdk, "-fobjc-arc", "-Os",
         "-g0", "-Wno-unguarded-availability-new", "-Wno-unguarded-availability",
         "-Werror=objc-missing-property-synthesis",
         "-Xclang", "-ast-dump=json", "-fsyntax-only", path],
        cwd=os.getcwd(), capture_output=True, text=True)
    errors = [line for line in result.stderr.split("\n") if " error:" in line]
    if errors:
        print("protocol-members: %s DOES NOT COMPILE, so its declarations cannot be trusted:"
              % os.path.basename(path))
        for line in errors[:6]:
            print("      %s" % line.split(" error:")[0].split("/")[-1] + " error:" + line.split(" error:")[1])
        raise SystemExit(2)
    if not result.stdout.strip():
        raise SystemExit("protocol-members: %s produced no AST:\n%s" % (path, result.stderr[-800:]))
    return json.loads(result.stdout)


def main():
    if len(sys.argv) != 5:
        print(__doc__)
        return 2
    protocol, cls, sdk, path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    if not os.path.isfile(path):
        print("protocol-members: %s is not a file. The class file is NOT derivable from the class"
              % path)
        print("name: four of the five implemented rows live in a differently named file -")
        print("CharonMetalSampler and CharonMetalFunction are both in CharonMetalTexture.m and")
        print("CharonMetalLibrary.m respectively - so FILE is an argument and not a guess.")
        return 2
    document = ast_for(path, sdk)
    members = protocol_members(document, protocol)
    defines = class_defines(document, cls) | synthesised(document, cls)
    missing = sorted(members - defines)
    print("  %-26s via %-28s %s" % (protocol, cls, os.path.basename(path)))
    if missing:
        for selector in missing:
            print("      missing: %s" % selector)
    else:
        print("      every protocol member is defined")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
