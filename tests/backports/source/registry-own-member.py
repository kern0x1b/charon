#!/usr/bin/env python3
"""Every registry row's member must be declared on that class by its own header.

A row for a member the class *inherits* is a row the class does not have: NSObject's -init and
+new are NSObject's, and the lift will not redeclare a designated initializer it already carries, which
is how -[PHASENumericPair init] came to be in the registry at all and was removed by stack 13.

The rule is therefore mechanical and belongs to a check rather than to a reviewer's memory: before a
row goes in, look in the class's own header block, not in the framework, and not in the class's
superclass. This walks every registry under packages/ and every SDK header, and reports any row whose
selector is not in its own class's @interface block.

    ./registry-own-member.py [root]      default: the repository above this directory
"""
import os
import re
import sys

# A row's selector, and whether the class is named with one.
ROW = re.compile(r"^[-+]\[(\w+)\s+([A-Za-z_][A-Za-z0-9_]*):?\]$")
INTERFACE_OPEN = re.compile(r"^@interface\s+(\w+)\b")
HEADER_SUFFIXES = (".h",)


def sdk_headers(sdk):
    """The headers of one SDK, by class name, each holding only its own @interface block."""
    blocks = {}
    if not sdk or not os.path.isdir(sdk):
        return blocks
    for base, _, names in os.walk(sdk):
        for name in names:
            if not name.endswith(HEADER_SUFFIXES):
                continue
            try:
                with open(os.path.join(base, name)) as handle:
                    text = handle.read()
            except (OSError, UnicodeDecodeError):
                continue
            # a block runs from its @interface line to the next @end, and a category's name
            # (the parentheses) is not part of the class name
            lines = text.split("\n")
            for index, line in enumerate(lines):
                opening = INTERFACE_OPEN.match(line)
                if not opening:
                    continue
                body = []
                for following in lines[index + 1:]:
                    if following.lstrip().startswith("@end"):
                        break
                    body.append(following)
                blocks.setdefault(opening.group(1), []).append("\n".join(body))
    return blocks


def declared_in_own_block(class_name, selector, blocks):
    """Whether any header declares `selector` inside `class_name`'s own @interface block."""
    for body in blocks.get(class_name, []):
        # What may follow the selector: a colon for a method that takes parameters, a brace for a body,
        # a semicolon for a declaration, or the end of the line. Nothing else is a declaration of it.
        # Leading space matters: the SDK documents a method inside a /*! ... */ block, where the
        # declaration is indented, and anchoring at column zero missed every one of them - which is
        # why the first run of this check reported 79 rows, all of them real methods.
        # What may follow the selector depends on the member: the parameter list's "(" for one that
        # takes parameters, a ";" for a declaration, a "{" for a body, "NS_UNAVAILABLE" for one the
        # header marks unavailable, or the end of the line. Anything else is a different selector that
        # happens to start with this one, which is why the set is explicit rather than "\W".
        pattern = r"^\s*[-+]\s*\([^)]*\)\s*" + re.escape(selector) + \
                  r"\s*(\(|[:;{]|NS_UNAVAILABLE|__attribute|API_|$)"
        if re.search(pattern, body, re.M):
            return True
    return False


# Two proofs, and the check stops without reporting anything if either does not hold: the one row that
# was in the registry and should not have been, and a row that is the class's own.
PROOFS = [("PHASENumericPair", "init", False), ("PHASEEnvelope", "evaluateForValue:", True)]


def prove(headers):
    problems = []
    for class_name, selector, wanted in PROOFS:
        found = declared_in_own_block(class_name, selector, headers)
        if found != wanted:
            problems.append("%s %s: the check says %s, the header says %s"
                            % (class_name, selector, found, wanted))
    for problem in problems:
        sys.stderr.write("FAIL the check does not prove itself: %s\n" % problem)
    if not problems:
        print("ok   the check proves itself: it does not find -[PHASENumericPair init] and does find "
              "-[PHASEEnvelope evaluateForValue:]")
    return not problems


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.abspath(
        os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", ".."))
    sdk = os.environ.get("CHARNON_SDK") or os.path.join(
        os.environ.get("HOME", ""), ".xmake", "packages", "i", "iphoneos-sdk")
    headers = {}
    for base, _, names in os.walk(sdk) if os.path.isdir(sdk) else []:
        del base, names
    # the SDK store holds one directory per version; take the newest, which is what the package builds
    versions = []
    if os.path.isdir(sdk):
        versions = sorted(d for d in os.listdir(sdk) if os.path.isdir(os.path.join(sdk, d)))
    if versions:
        headers = sdk_headers(os.path.join(sdk, versions[-1]))
    rows = considered = 0
    found = []
    registry = os.path.join(root, "packages", "a", "apple-backports", "registry")
    for base, _, names in os.walk(registry):
        for name in sorted(names):
            if not name.endswith(".json"):
                continue
            import json
            with open(os.path.join(base, name)) as handle:
                data = json.load(handle)
            for entry in (data if isinstance(data, list) else data.get("entries", [])):
                match = ROW.match(entry["api"])
                if not match:
                    continue
                class_name, selector = match.group(1), match.group(2)
                considered += 1
                if class_name not in headers:
                    continue          # no header here to judge it against; the gate will say so
                if not declared_in_own_block(class_name, selector, headers):
                    rows += 1
                    found.append("%s: %s" % (os.path.join(base, name).split("registry/")[-1], entry["api"]))
    if not headers:
        print("no SDK headers found under %s: nothing could be checked" % sdk)
        return 0
    if not prove(headers):
        return 1
    for line in found:
        print("FAIL the header does not declare this member on the class itself: " + line)
    print("checked %d method rows against their own class's header, %d not declared" % (considered, rows))
    return 1 if rows else 0


if __name__ == "__main__":
    sys.exit(main())
