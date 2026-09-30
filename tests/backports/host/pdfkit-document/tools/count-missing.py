#!/usr/bin/env python3
"""Which PDFKit members the 26.2 header declares and the registry has NO row for, by class.

    count-missing.py <checkout> [--registry <file>...]

A row is what the registry calls a member, and this is the other direction of the same question
declared-check.py asks.  That one asks "does every row name something a header declares?" and answers
for the rows.  This one asks "does every declared member have a row?" and answers for the headers, which
is the direction that finds work: a member Apple declares and the registry never mentions is a member
the package's surface does not describe, and nothing else in the tree would notice its absence.

It is also the only honest way to size a family.  Counting inert rows measures what a previous series
already looked at; counting declarations measures what is left, and the two are different numbers.

The port's own members are excluded, on the same reasoning as declared-check.py: -charon_CGPDFDocument
and the rest are declared in the PORT's header, and a row for one of those is the port's business rather
than a gap in the package's surface.

    the 26.2 headers: 16 @interfaces, N selectors, M properties
    PDFSelection   11 declared,  0 rows, 11 missing
    ...
    TOTAL         180 declared, 66 rows, 114 missing

Exit 0 always: this is a census, not a check, and a package with gaps is the normal state.  Exit 2 when
the SDK or the checkout is wrong, which is a fault rather than a finding.
"""
import glob
import json
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_HOME = os.environ.get("HOME")


def _candidate_roots():
    out, here = [], _HERE
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
    for c in CANDIDATES:
        print("    " + os.path.normpath(c))
    sys.exit(2)
HEADERS = os.path.join(SDK, "System/Library/Frameworks/PDFKit.framework/Headers")

CLASS_BLOCK = re.compile(r"@interface\s+(\w+)[^\n]*\n(.*?)@end", re.S)
DECL_METHOD = re.compile(
    r"^\s*[-+]\s*\([^)]*\)\s*([A-Za-z_]\w*)\s*(?::|(?:[A-Z][A-Z0-9_]*\([^)]*\)\s*)*;)", re.M)
DECL_PROPERTY = re.compile(
    r"@property\s*(?:\([^)]*\))?[^;\n]*?"
    r"(?P<name>[A-Za-z_]\w*)\s*"
    r"(?:[A-Z][A-Z0-9_]*\([^)]*\)\s*)*;")
# NSObject's own -dealloc is in no PDFKit header and every class inherits it.  -init and
# -copyWithZone: are declared on some classes and not others, and a row for one is the port's own
# override rather than a gap, so they are counted as covered and never as missing.
INHERITED = {"dealloc", "init", "copyWithZone:"}


def census(headers):
    """class -> {members}, and the set of class names"""
    out = {}
    for path in sorted(headers):
        text = open(path, errors="ignore").read()
        for name, body in CLASS_BLOCK.findall(text):
            members = out.setdefault(name, set())
            for selector in DECL_METHOD.findall(body):
                # a method is named by its SELECTOR, not by its first keyword: -setValue:forKey: and
                # -value are different members and a census that collapsed them would undercount the
                # work.  The full selector is rebuilt from the declaration line.
                for line in body.splitlines():
                    if re.match(r"^\s*[-+]\s*\([^)]*\)\s*" + re.escape(selector) + r"\s*[:;]", line) \
                            or re.match(r"^\s*[-+]\s*\([^)]*\)\s*" + re.escape(selector) + r"\s*"
                                        r"(?:[A-Z][A-Z0-9_]*\([^)]*\)\s*)*;", line):
                        parts = re.findall(r"([A-Za-z_]\w*)\s*:", line.split(selector, 1)[1]) \
                            if selector + ":" in line else []
                        members.add(selector + "".join(p + ":" for p in parts) if parts else selector)
                        break
            for prop in DECL_PROPERTY.findall(body):
                members.add(prop)
    return out


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    checkout = os.path.abspath(sys.argv[1])
    registry = [a for a in sys.argv[2:] if not a.startswith("--")] or \
        sorted(glob.glob(os.path.join(checkout, "packages/a/apple-backports/registry/PDFKit/*.json")))
    declared = census(glob.glob(os.path.join(HEADERS, "*.h")))
    if not declared:
        print(f"  the headers under {HEADERS} yielded no @interface at all - the path is wrong")
        return 2
    own_header = os.path.join(checkout, "packages/a/apple-backports/PDFKit/CharonPDFKit.h")
    own = census([own_header]).get("__port__", set()) if os.path.exists(own_header) else set()
    if os.path.exists(own_header):
        for name, body in CLASS_BLOCK.findall(open(own_header, errors="ignore").read()):
            own |= {s for s in DECL_METHOD.findall(body)} | set(DECL_PROPERTY.findall(body))

    # what the registry covers, per class, as SETS so a row for one member does not stand in for a row
    # for every member that shares its first keyword
    rows = {}
    for path in registry:
        held = json.load(open(path))
        for entry in (held if isinstance(held, list) else held["entries"]):
            api = entry["api"]
            m = re.match(r"[-+]\[(\w+)\s+([^\]]*)\]", api)
            if m:
                owner, selector = m.group(1), m.group(2)
            elif "." in api:
                owner, selector = api.split(".", 1)
            else:
                rows.setdefault(api, set())
                continue
            rows.setdefault(owner, set()).add(selector.split(":")[0].rstrip(":"))

    total_d = total_r = total_m = 0
    print(f"  the 26.2 headers: {len(declared)} @interfaces")
    for cls in sorted(declared, key=lambda c: -len(declared[c])):
        members = {m for m in declared[cls] if m not in INHERITED}
        covered = rows.get(cls, set()) | (own if cls not in rows else set())
        missing = sorted(m for m in members if m not in covered)
        if not members and not rows.get(cls):
            continue
        total_d += len(members)
        total_r += len(members) - len(missing)
        total_m += len(missing)
        print(f"  {cls:<20} {len(members):>3} declared, {len(members) - len(missing):>3} covered,"
              f" {len(missing):>3} missing")
    print(f"  {'TOTAL':<20} {total_d:>3} declared, {total_r:>3} covered, {total_m:>3} missing")


if __name__ == "__main__":
    main()
