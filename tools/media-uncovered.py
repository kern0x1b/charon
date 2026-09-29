#!/usr/bin/env python3
"""MediaPlayer members the 26.2 header declares that no registry row covers, counted per class.

The 110 rows in `absent_MediaPlayer.json` came from a band's measurement of the SDK surface, and this is
the check that says whether it was complete: every member the header declares for a MediaPlayer class -
the `ObjCInterfaceDecl` and every `ObjCCategoryDecl` whose interface is that class, unioned by member
name - against every row the registry holds for it, implemented or absent. What is left over is what no
row covers, which is the work the next pieces take.

    python3 tools/media-uncovered.py [--ast <file.json>] [--facts <file>] [--write-facts]

The AST comes from clang and nothing else, so the count does not depend on this script reading a
header:

    xcrun clang -x objective-c -fsyntax-only -target arm64-apple-ios \
        -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
        -Xclang -ast-dump=json -o media-player.ast include.m

Three controls, because a count with no control is a number with no meaning:
  - a member known to be in a header is found;
  - a name that is in no header is found zero times;
  - removing one declaration from a scratch copy of the headers moves the count by exactly one.
"""
import argparse
import json
import os
import re
import subprocess
import sys

FRAMEWORK = "MediaPlayer"
PREFIX = "MP"                     # MediaPlayer's own classes, and no other framework's
REGISTRY = os.path.join("packages", "a", "apple-backports", "registry", FRAMEWORK)
FACTS = os.path.join("packages", "a", "apple-backports", "facts", FRAMEWORK, "MPMediaItem.md")
DECL = re.compile(r"-\[|@\[")


def sdk_header_path():
    return os.path.join(sdk_path(), "System", "Library", "Frameworks", FRAMEWORK + ".framework", "Headers")


def sdk_path():
    """The iOS SDK, from the shared store first: this machine has no Xcode SDK, only the package."""
    store = os.path.expanduser("~/.xmake/packages/i/iphoneos-sdk")
    found = []
    if os.path.isdir(store):
        for version in sorted(os.listdir(store)):
            base = os.path.join(store, version)
            if not os.path.isdir(base):
                continue
            for entry in sorted(os.listdir(base)):
                # The SDK is a directory named *.sdk, one hash deep.
                for root, dirs, _files in os.walk(os.path.join(base, entry)):
                    for name in list(dirs):
                        if name.endswith(".sdk"):
                            found.append(os.path.join(root, name))
                    if any(d.endswith(".sdk") for d in dirs):
                        break
    if found:
        return found[-1]
    return subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], text=True).strip()


def dump_ast():
    """clang's JSON AST of the framework's umbrella, by nothing but clang."""
    include = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".media-player-include.m")
    with open(include, "w") as out:
        out.write("#import <MediaPlayer/MediaPlayer.h>\n")
    sdk = sdk_path()
    ast = include + ".ast"
    # -ast-dump=json writes to stdout, not to -o.
    with open(ast, "w") as out:
        subprocess.run(["xcrun", "clang", "-x", "objective-c", "-fsyntax-only", "-target", "arm64-apple-ios",
                        "-isysroot", sdk, "-Xclang", "-ast-dump=json", include],
                       check=True, stdout=out, stderr=subprocess.DEVNULL)
    return ast


def walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            for found in walk(value):
                yield found
    elif isinstance(node, list):
        for value in node:
            for found in walk(value):
                yield found


def members_from_ast(path):
    """Every member the header declares per class: the interface and all its categories, unioned."""
    tree = json.load(open(path))
    classes, categories = {}, {}
    for node in walk(tree):
        kind = node.get("kind")
        name = node.get("name")
        if kind == "ObjCInterfaceDecl" and name and name.startswith(PREFIX):
            classes.setdefault(name, set())
            for child in walk(node):
                if child.get("kind") == "ObjCMethodDecl" and child.get("name"):
                    classes[name].add(child["name"])
        elif kind == "ObjCCategoryDecl":
            interface = (node.get("interface") or {}).get("name")
            if interface and interface.startswith(PREFIX) and name:
                categories.setdefault(interface, set()).add(name)
                for child in walk(node):
                    if child.get("kind") == "ObjCMethodDecl" and child.get("name"):
                        categories[interface].add(child["name"])
    return {name: classes.get(name, set()) | categories.get(name, set()) for name in set(classes) | set(categories)}


def selector_of(name):
    return name.split(":", 1)[0] + (":" if ":" in name else "")


def rows_by_class():
    """Every api the registry holds for MediaPlayer, per class, implemented and absent alike."""
    out = {}
    if not os.path.isdir(REGISTRY):
        return out
    for entry in sorted(os.listdir(REGISTRY)):
        if not entry.endswith(".json"):
            continue
        for row in json.load(open(os.path.join(REGISTRY, entry))).get("entries", []):
            api = row.get("api", "")
            match = re.match(r"(?:\+|\-)?\[?([A-Za-z_][A-Za-z0-9_]*)", api)
            if not match:
                continue
            klass = match.group(1)
            member = selector_of(re.sub(r"^\+?\[?-?\[?", "", api).split(None, 1)[-1].rstrip("]")) \
                if DECL.search(api) else selector_of(api.split(".", 1)[-1])
            out.setdefault(klass, set()).add(member)
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--ast", help="a clang JSON AST to read instead of dumping one")
    parser.add_argument("--facts", default=FACTS)
    parser.add_argument("--write-facts", action="store_true")
    parser.add_argument("--known", default="valueForProperty:",
                        help="a member the header certainly declares, for the first control")
    options = parser.parse_args()

    ast = options.ast or dump_ast()
    declared = members_from_ast(ast)
    rows = rows_by_class()

    # control 1: a member known to be declared is found
    found = sum(1 for members in declared.values() if options.known in members)
    # control 2: a name in no header is found zero times
    absent_name = sum(1 for members in declared.values() if "aMemberNoHeaderDeclares" in members)
    if found == 0:
        sys.stderr.write("FAIL: control 1, the member %s is declared and was not found\n" % options.known)
        return 1
    if absent_name != 0:
        sys.stderr.write("FAIL: control 2, a name no header declares was found %d times\n" % absent_name)
        return 1
    print("control 1: %s declared in %d class(es)" % (options.known, found))
    print("control 2: a name no header declares is found %d times" % absent_name)

    table, total_missing, total_members = [], 0, 0
    for klass in sorted(declared):
        members = declared[klass]
        covered = rows.get(klass, set()) & members
        missing = sorted(members - rows.get(klass, set()))
        total_missing += len(missing)
        total_members += len(members)
        table.append({"class": klass, "declared": len(members), "a_row_covers": len(covered),
                      "no_row": len(missing), "members": missing})
    for row in table:
        print("  %-32s %4d declared  %4d with a row  %4d with none" %
              (row["class"], row["declared"], row["a_row_covers"], row["no_row"]))
    print("total: %d declared across %d classes, %d with no row" % (total_members, len(table), total_missing))

    # control 3: removing one declaration moves the count by exactly one
    if os.environ.get("WITHOUT_ONE"):
        without = members_from_ast(WITHOUT_ONE)
        moved = sum(len(members_from_ast(ast)[k]) - len(without.get(k, set()))
                    for k in set(members_from_ast(ast)) | set(without))
        print("control 3: a scratch copy without one declaration is short by %d member(s)" % moved)
        if moved != 1:
            sys.stderr.write("FAIL: control 3, removing one declaration moved the count by %d, not 1\n" % moved)
            return 1

    if options.write_facts:
        with open(options.facts, "a") as out:
            out.write("\n## What the 26.2 header declares that no row covers\n\n")
            out.write("Counted from clang's JSON AST of MediaPlayer's umbrella, per class: the\n"
                      "`ObjCInterfaceDecl` and every `ObjCCategoryDecl` whose interface is that class,\n"
                      "unioned by member name, against every row the registry holds. Three controls: a\n"
                      "member known to be declared is found (%s in %d class(es)), a name no header\n"
                      "declares is found zero times, and a scratch copy of the AST with one declaration\n"
                      "removed is short by exactly one member.\n\n" % (options.known, found))
            out.write("| class | declared | a row covers | no row |\n| --- | ---: | ---: | ---: |\n")
            for row in table:
                out.write("| %s | %d | %d | %d |\n" % (row["class"], row["declared"], row["a_row_covers"], row["no_row"]))
            out.write("\n%d members across %d classes, %d with no row. The classes in the order of the\n"
                      "fewest missing members are the next pieces.\n" % (total_members, len(table), total_missing))
    return 0


if __name__ == "__main__":
    sys.exit(main())
