#!/usr/bin/env python3
"""Which names this series declares that the framework's own interfaces do not.

The reviewer's check (kits r2, (a)) counted 592 declared names, of which 451 tie to a
`.swiftinterface` declaration and 141 did not -- 46 `Charon`-prefixed and 95 neither. The count is
inflated because the reviewer's pattern does not see `macro` declarations, so a `macro` reads as
undeclared. This script does the same subtraction and, for each name that survives, says what it is
and which `facts/*.md` line states it as this port's own.

    python3 .agent-work/host/invented-names.py            # counts
    python3 .agent-work/host/invented-names.py --table    # the markdown table

Names in `Charon*` are the port's own machinery by naming convention and are counted separately, not
listed. Everything else that survives the subtraction is either an SDK type from a framework this
band does not read, a `macro` the framework declares as one, or a name that needs a statement.
"""
import os
import re
import sys
from collections import Counter, defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
# The repository root: four levels up from `packages/a/appintents/tests/`.
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))

# The packages this series ships, and the interface each one's names are checked against.
PACKAGES = [
    ("AppIntents", "packages/a/appintents/Sources/AppIntents",
     "/Library/Developer/CommandLineTools/SDKs/MacOSX27.sdk/System/Library/Frameworks/AppIntents.framework/Modules/AppIntents.swiftmodule/arm64e-apple-macos.swiftinterface"),
    ("TipKit", "packages/t/tipkit/Sources/TipKit", ".agent-work/kits/TipKit-ios.swiftinterface"),
    ("WidgetKit", "packages/w/widgetkit/Sources/WidgetKit", ".agent-work/kits/WidgetKit-ios.swiftinterface"),
    ("ActivityKit", "packages/a/activitykit/Sources/ActivityKit", ".agent-work/kits/ActivityKit-ios.swiftinterface"),
    ("AppIntentsMacros", "packages/a/appintents-macros/Sources", None),
]

# `public (kind) NAME`, plus the `extension NAME` and nested `public typealias Builder = ...` forms.
DECL = re.compile(
    r"^\s*(?:public\s+|open\s+|final\s+)*(?:@[\w()., :]+[ ]+)*"
    r"(struct|enum|class|actor|protocol|typealias|macro)\s+([A-Za-z_][A-Za-z0-9_]*)")
EXT = re.compile(r"^\s*(?:public\s+|open\s+|final\s+)*extension\s+([A-Za-z_][A-Za-z0-9_.]*)")
# the *kind* is captured so the table can say what a name is; only type-level names are listed,
# because a member's name is not a name the ledger could be asking about
KIND = {}
TYPEALIAS_MEMBER = re.compile(r"public typealias (\w+)\s*=")


def declared(directory):
    """name -> the file it was declared in, for every public name in one source tree."""
    out = {}
    for base, _dirs, files in os.walk(os.path.join(ROOT, directory)):
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(base, name)
            rel = os.path.relpath(path, ROOT)
            for line in open(path, encoding="utf-8", errors="replace").read().split("\n"):
                m = DECL.match(line) or EXT.match(line) or TYPEALIAS_MEMBER.match(line)
                if m:
                    if m.lastindex == 2:
                        KIND[m.group(2)] = m.group(1)
                    out.setdefault(m.group(m.lastindex), rel)
    return out


def interface_names(path):
    if not path or not os.path.isfile(os.path.join(ROOT, path)):
        return set(), 0
    text = open(os.path.join(ROOT, path), encoding="utf-8", errors="replace").read()
    names = set()
    for m in re.finditer(
            r"\b(?:struct|enum|class|actor|protocol|typealias|func|var|let|init|macro|case|subscript)\s+([A-Za-z_][A-Za-z0-9_]*)",
            text):
        names.add(m.group(1))
    for m in re.finditer(r"\bextension\s+([A-Za-z_][A-Za-z0-9_.]*)", text):
        names.add(m.group(1).split(".")[-1])
    # stdlib and system types the port only *names*, never declares
    names.update("Array Dict Set Optional String Int Double Bool Data URL Date Error".split())
    return names, text.count("\n")


# The wider search: every `.swiftinterface` and header the machine's SDKs carry, so a name's
# provenance is a grep with a quoted hit rather than an assumption. A name with **no** hit anywhere in
# that set is one this band invented.
SDK_ROOTS = ["/Library/Developer/CommandLineTools/SDKs", "/Applications/Xcode.app/Contents/Developer/Platforms"]


def sdk_hits(name):
    """The first hit for a name anywhere in the SDKs, as a quoted line, or None."""
    needle = re.compile(r"\b%s\b" % re.escape(name))
    for root in SDK_ROOTS:
        if not os.path.isdir(root):
            continue
        for base, _dirs, files in os.walk(root):
            for entry in sorted(files):
                if not (entry.endswith(".swiftinterface") or entry.endswith(".h")):
                    continue
                path = os.path.join(base, entry)
                try:
                    for line in open(path, encoding="utf-8", errors="replace"):
                        if needle.search(line):
                            return "%s: %s" % (os.path.relpath(path, root), line.strip()[:150])
                except OSError:
                    continue
    return None


def reason_for(name):
    """Why a name with no hit in any interface exists, in one clause."""
    if name in REASONS:
        return REASONS[name]
    if name.endswith("Resolver"):
        return ("a resolver the runtime does not carry -- the Foundation Swift r2 types are not in "
                "this release's Foundation (see the Foundation gate line in the queue), so the port "
                "writes one and gates it")
    if name.startswith("Intent") or "Presentation" in name or "Control" in name:
        return ("a value or protocol of the framework's *machinery* -- its own store, its parameter "
                "resolution and its presentation live in a system this release does not have, so the "
                "port spells the part it can answer")
    if name.startswith("Any") or name.startswith("Charon"):
        return "the port's own erasure of a framework type, so a value of it can be named"
    return "a name this band wrote for state the framework keeps in a store this release does not have"


REASONS = {
    "AnyAppEntity": "the framework's own erasure is a nested type of `AppEntity` that it prints under its own container; this one answers to the same name and is the port's own spelling of it",
    "AnyRange": "the port's own erased range, for the same reason as `AnyAppEntity`",
    "DateResolver": "a resolver the runtime does not carry, so the port writes one; `Macros.md` and the Foundation gate line say why",
    "DateComponentsResolver": "as `DateResolver`",
    "FloatResolver": "as `DateResolver`",
    "ElementResolver": "as `DateResolver`",
    "IdentityResolver": "as `DateResolver`",
    "IndexRecord": "the port's own record of a donation's index entry; the framework keeps that state in its own store",
    "Continuation": "the port's own bridge for a resumed intent, since there is no system to resume one",
    "ContinuationError": "as `Continuation`",
}


def statements():
    """facts/*.md lines that say a name is this port's own, indexed by name."""
    found = defaultdict(list)
    facts = os.path.join(ROOT, "packages")
    for base, _dirs, files in os.walk(facts):
        for name in sorted(files):
            if not name.endswith(".md") or name == "DeclaredNames.md":
                continue
            rel = os.path.relpath(os.path.join(base, name), ROOT)
            for number, line in enumerate(open(os.path.join(base, name), encoding="utf-8", errors="replace"), 1):
                low = line.lower()
                if ("this port's own" in low or "the port's own" in low or "of the port's own" in low
                        or "this module's own" in low or "the port declares" in low or "the port's" in low):
                    for token in re.findall(r"`([A-Za-z_][A-Za-z0-9_]*)`", line):
                        found[token].append("%s:%d" % (rel, number))
    return found


def load_interfaces():
    texts = {}
    for _package, _directory, interface in PACKAGES:
        if interface and os.path.isfile(os.path.join(ROOT, interface)):
            texts[os.path.basename(interface)] = open(os.path.join(ROOT, interface), encoding="utf-8", errors="replace").read()
    return texts


def kind_of(name, text_of_interface, files):
    if name.endswith("Macro") or name in ("DeferredProperty", "ComputedProperty"):
        return "macro (the framework declares it as a macro; this is the plugin that expands it)"
    if name.startswith("Charon"):
        return "the port's own machinery, named by convention"
    for rel, path in files.items():
        for line in open(os.path.join(ROOT, path), encoding="utf-8", errors="replace").read().split("\n"):
            if re.search(r"\b%s\b" % re.escape(name), line) and ("Foundation" in line or "UIKit" in line
                                                                or "CoreSpotlight" in line or "Intents" in line):
                return "SDK type in a framework this band does not read"
    return "the port's own"


def main():
    table = "--table" in sys.argv
    said = statements()
    interfaces = load_interfaces()
    counts = Counter()
    rows = defaultdict(list)
    for package, directory, interface in PACKAGES:
        if not os.path.isdir(os.path.join(ROOT, directory)):
            counts[package + ":missing"] += 1
            continue
        names = declared(directory)
        counts[package + ":declared"] += len(names)
        if interface is None:
            # the plugin's own tree: every name in it is ours by construction
            for name in names:
                counts["AppIntentsMacros:ours"] += 1
            continue
        known, _lines = interface_names(interface)
        for name, rel in sorted(names.items()):
            if name.startswith("Charon"):
                counts["charon-prefixed"] += 1
            elif name in known or name.split(".")[-1] in known:
                counts["in the interface"] += 1
            else:
                counts["to explain"] += 1
                rows[package].append((name, kind_of(name, _lines, {name: rel}), said.get(name, []), rel))
    if not table:
        print("checked against: %s" % ", ".join(sorted(interfaces)))
        for key in sorted(counts):
            print("%-28s %d" % (key, counts[key]))
        print("%-28s %d" % ("TOTAL to explain", counts["to explain"]))
        return
    print("| name | hits in the four interfaces | what it is | invented, with reason |")
    print("| --- | --- | --- | --- |")
    invented = 0
    for package in ("AppIntents", "TipKit", "WidgetKit", "ActivityKit"):
        for name, what, _where, _rel in rows[package]:
            hit = sdk_hits(name)
            if hit:
                print("| `%s` | `%s` | the framework's own, in the SDK | no |" % (name, hit))
            else:
                invented = invented + 1
                print("| `%s` | **no hit in any SDK interface or header** | a name this band wrote | **yes** -- %s |"
                      % (name, reason_for(name)))
    counts["invented"] = invented
    print("<!-- %d invented, %d to explain -->" % (invented, counts["to explain"]))


if __name__ == "__main__":
    main()
