#!/usr/bin/env python3
"""Does every PDFKit registry row name a member the 26.2 header of ITS OWN class declares?

    declared-check.py <checkout> [--registry <file>...]

It exists because this series put three rows on the registry for methods the 26.2 PDFView.h does not
declare, and the header in the same series said so in as many words.  A row for a member that is not
the API is found by anything that treats the registry as the package's surface, and one of the three
collided BY NAME with a member another class owns and the same file already describes.

For each row:
  * a class row must match an @interface of that name in the framework's headers;
  * a method row's selector - the one after the brackets - must appear in that class's @interface;
  * a property row's name must be declared @property in that class's @interface.

The port's OWN members - the ones it adds, like -[PDFPage initWithCGPDFPage:document:index:] and
-charon_CGPDFDocument - are declared in the PORT's header, not the SDK's, and a row for one of those is
not a finding.  So the port's own header is consulted too, and a row that names a member of the port's
own making is reported separately rather than mixed in.

Exit 0 when every row names a declared member.  Exit 1, naming each row that does not.
"""
import glob
import json
import os
import re
import sys

# the 26.2 SDK, wherever this checkout keeps it: the coordinate's copy, or $PWD/.agent-work's.
# The 26.2 SDK, in the order a checkout is likely to hold it: beside this worktree, then the
# coordinator's own copy.  Resolved by looking for the header itself, and named if it is not found.
_HOME = os.environ.get("HOME", "")
def _roots():
    """Every ancestor of the tool that could be a checkout root, nearest first: a worktree carries
    .git as a FILE and the main clone as a directory, and neither is five levels up in both shapes, so
    the roots are walked to rather than counted."""
    here = os.path.dirname(os.path.abspath(__file__))
    out = []
    while True:
        out.append(here)
        if os.path.exists(os.path.join(here, ".git")):
            break
        parent = os.path.dirname(here)
        if parent == here:
            break
        here = parent
    if _HOME:
        out.append(os.path.join(_HOME, "charon"))
    return out


def _candidate_roots():
    """Every ancestor of the tool that HOLDS a .agent-work, plus the main clone.

    Which directory holds .agent-work differs by shape - a worktree keeps its own .agent-work and the
    SDK sits in the repository's, two above; the main clone keeps both together - so the ancestors are
    tested for the DIRECTORY rather than for .git, which is a file in a worktree and a directory in
    a clone."""
    out, here = [], os.path.dirname(os.path.abspath(__file__))
    while True:
        out.append(here)
        parent = os.path.dirname(here)
        if parent == here:
            break
        here = parent
    if _HOME:
        out.append(os.path.join(_HOME, "charon"))
        out.append(os.path.join(_HOME, "charon", ".agent-work", "worktrees"))
    return out


CANDIDATES = [os.path.join(root, ".agent-work", "sdk-26.2", "iPhoneOS26.2.sdk")
              for root in _candidate_roots()]
_PROBE = "System/Library/Frameworks/PDFKit.framework/Headers/PDFDocument.h"
SDK = next((os.path.normpath(c) for c in CANDIDATES if os.path.isfile(os.path.join(c, _PROBE))), None)
if SDK is None:
    print("  the 26.2 SDK was not found.  Looked for " + _PROBE + " under:")
    for candidate in CANDIDATES:
        print("    " + os.path.normpath(candidate))
    sys.exit(2)
HEADERS = os.path.join(SDK, "System/Library/Frameworks/PDFKit.framework/Headers")

# A method line may wrap, and @property carries an optional custom setter: - (nonatomic, setter=enablePageShadows:)
# BOOL pageShadowsEnabled must read as the property "pageShadowsEnabled", not as a type word.
CLASS_BLOCK = re.compile(r"@interface\s+(\w+)[^\n]*\n(.*?)@end", re.S)
# A METHOD has the same trailing-macro shape as a property, and for the same reason: the 26.2 header
# writes "- (void)removeAllAppearanceStreams PDFKIT_DEPRECATED(10_5, 10_12, NA, NA);", so the token
# next to the ';' is a ')' and a pattern that wanted a ':' or a ';' there matched nothing.  It is the
# same root cause as the property pattern and it is the third place it bit - this row was the only one
# still flagged after that one was fixed, and it is a member the header plainly declares.
DECL_METHOD = re.compile(
    r"^\s*[-+]\s*\([^)]*\)\s*([A-Za-z_]\w*)\s*(?::|(?:[A-Z][A-Z0-9_]*\([^)]*\)\s*)*;)", re.M)
# A property's NAME is the last identifier before the ';', and it is NOT always adjacent to it: Apple's
# headers end a declaration with an availability macro - "@property (nonatomic, copy, nullable)
# NSDate *modificationDate PDFKIT_AVAILABLE(10_5, 11_0);" - so the token next to the ';' is a ')'.
# A pattern that wanted a word there matched nothing at all, and the members that still passed were only
# the ones the PORT's own header declares without a macro.  So the trailing macro is consumed and named
# apart, and the name is the last identifier left.  It is the MACRO and not the '*': a property of a
# scalar type with a macro fails identically, and one of a class type without one is found.
DECL_PROPERTY = re.compile(
    r"@property\s*(?:\([^)]*\))?[^;\n]*?"
    r"(?P<name>[A-Za-z_]\w*)\s*"
    r"(?:[A-Z][A-Z0-9_]*\([^)]*\)\s*)*;")
# A class-typed property whose name is followed by the macro: the name is the one captured above.  A
# declaration with NO macro captures the same way, because the macro group may match zero times.
# NSObject's own -dealloc is not in PDFKit's headers, and every class inherits it.
INHERITED = {"dealloc", "init", "copyWithZone:"}


def declarations(headers):
    """selector -> classes, and property name -> classes, over the given headers"""
    methods, properties, classes = {}, {}, set()
    for path in sorted(headers):
        text = open(path, errors="ignore").read()
        for name, body in CLASS_BLOCK.findall(text):
            classes.add(name)
            for selector in DECL_METHOD.findall(body):
                methods.setdefault(selector, set()).add(name)
            for prop in DECL_PROPERTY.findall(body):
                properties.setdefault(prop, set()).add(name)
    return methods, properties, classes


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    checkout = os.path.abspath(sys.argv[1])
    registry = [a for a in sys.argv[2:] if not a.startswith("--")] or \
        sorted(glob.glob(os.path.join(checkout, "packages/a/apple-backports/registry/PDFKit/*.json")))
    sdk_methods, sdk_properties, sdk_classes = declarations(glob.glob(os.path.join(HEADERS, "*.h")))
    own_header = os.path.join(checkout, "packages/a/apple-backports/PDFKit/CharonPDFKit.h")
    own_methods, own_properties, own_classes = declarations([own_header]) if os.path.exists(own_header) \
        else ({}, {}, set())
    if not sdk_classes:
        print(f"  the headers under {HEADERS} yielded no @interface at all - the path is wrong")
        return 2

    checked = found = ours = 0
    problems = []
    for path in registry:
        held = json.load(open(path))
        for entry in (held if isinstance(held, list) else held["entries"]):
            api = entry["api"]
            checked += 1
            # -dealloc, -init and -copyWithZone: are NSObject's own and are declared by no PDFKit
            # header; the rows that name them are the port's own overrides, and the gate requires a
            # row for a member the port defines.  A row for one of these is never a finding.
            bare = re.match(r"[-+]\[[\w]+ ([^:\]]+)", api)
            if bare and bare.group(1).rstrip(":") in {"dealloc", "init", "copyWithZone"}:
                ours += 1
                continue
            # A PROPERTY is declared as one, and -[X pageCount] is the same member Apple's header
            # writes @property (nonatomic, readonly) NSUInteger pageCount - so a method-form row for a
            # property-form member is NOT a finding, and reading the headers as methods only reported
            # six that were all properties or inherited.  Both forms are read, and a row passes on
            # either: a property row may name a method-form declaration and a method row a property one,
            # because Apple's headers use @property for what is a getter pair.
            if api.startswith("-[") or api.startswith("+["):
                match = re.match(r"[-+]\[(\w+)\s+([^\]]*)\]", api)
                if not match:
                    problems.append((api, "the row's own name could not be read"))
                    found += 1
                    continue
                owner, selector = match.group(1), match.group(2).split(":")[0]
                if owner not in sdk_classes and owner not in own_classes:
                    problems.append((api, f"no @interface {owner} in the 26.2 headers"))
                elif selector in sdk_methods and owner not in sdk_methods[selector] and \
                        selector not in own_methods.get(selector, set()):
                    problems.append((api, f"-[{owner} {selector}…] is declared, but on "
                                            f"{sorted(sdk_methods[selector])} and not on {owner}"))
                elif (selector not in sdk_methods and selector not in own_methods
                      and not (owner in sdk_properties.get(selector, set()))
                      and not (owner in own_properties.get(selector, set()))):
                    problems.append((api, f"-[{owner} {selector}…] is declared by no @interface, "
                                            f"as a method or a property"))
                elif selector in own_methods and owner not in sdk_methods.get(selector, set()):
                    ours += 1
            elif "." in api:
                owner, prop = api.split(".", 1)
                if owner not in sdk_classes and owner not in own_classes:
                    problems.append((api, f"no @interface {owner} in the 26.2 headers"))
                elif prop in sdk_properties and owner not in sdk_properties[prop] and \
                        owner not in own_properties.get(prop, set()):
                    problems.append((api, f"{owner}.{prop} is declared, but on "
                                            f"{sorted(sdk_properties[prop])} and not on {owner}"))
                elif prop in INHERITED:
                    continue
                elif (prop not in sdk_properties
                      and not (owner in own_properties.get(prop, set()))
                      and not (owner in sdk_methods.get(prop, set()))
                      and not (owner in own_methods.get(prop, set()))):
                    problems.append((api, f"{owner}.{prop} is declared by no @interface, "
                                            f"as a property or a method"))
                elif owner not in sdk_properties.get(prop, set()) and \
                        owner in own_properties.get(prop, set()):
                    ours += 1
            else:
                if api not in sdk_classes and api not in own_classes:
                    problems.append((api, f"no @interface {api} in the 26.2 headers"))
                elif api in own_classes and api not in sdk_classes:
                    ours += 1
    print(f"  the 26.2 headers: {len(sdk_classes)} @interfaces, {len(sdk_methods)} selectors, "
          f"{len(sdk_properties)} properties")
    print(f"  {checked} PDFKit registry rows checked, {found} name a member no header of their own class declares, "
          f"{ours} name a member of the PORT's own making")
    for api, why in problems:
        print(f"  NOT DECLARED  {api}  {why}")
    return 1 if problems else 0


sys.exit(main())
