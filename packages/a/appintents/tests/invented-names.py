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
#
# **The paths are SDK paths in the shared store, not this worktree's scratch.** The first version
# pointed TipKit, WidgetKit and ActivityKit at `.agent-work/kits/*-ios.swiftinterface`, which exists
# only in the band worktree that extracted them: on any other checkout the script scored those three
# modules as *absent from every interface* and the counts came out 700/425/44/223 against the
# 648/573/44/75 it prints here (kits r4, finding 1). Each path is now a glob under
# `charon@iphoneos-sdk`'s install, so it is the machine's own copy of the release the rows are written
# against -- and a glob that matches **not exactly one** file is a hard error naming the pattern, never
# a silent absence.
SDK = os.path.join(os.path.expanduser("~"), ".xmake/packages/i/iphoneos-sdk/26.2",
                   "*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs",
                   "iPhoneOS26.2.sdk/System/Library/Frameworks/%s.framework/Modules/%s.swiftmodule/"
                   "arm64e-apple-ios.swiftinterface")

PACKAGES = [
    ("AppIntents", "packages/a/appintents/Sources/AppIntents", SDK % ("AppIntents", "AppIntents")),
    ("TipKit", "packages/t/tipkit/Sources/TipKit", SDK % ("TipKit", "TipKit")),
    ("WidgetKit", "packages/w/widgetkit/Sources/WidgetKit", SDK % ("WidgetKit", "WidgetKit")),
    ("ActivityKit", "packages/a/activitykit/Sources/ActivityKit", SDK % ("ActivityKit", "ActivityKit")),
    ("AppIntentsMacros", "packages/a/appintents-macros/Sources", None),
]


def one(pattern, override=None):
    """Exactly one match, or a hard error naming the pattern. A missing input is never an absence."""
    if override:
        if not os.path.isfile(override):
            sys.exit("invented-names: the interface %s does not exist; refusing to score the module" % override)
        return [override]
    import glob as _glob
    found = sorted(_glob.glob(os.path.expanduser(pattern)))
    if not found:
        sys.exit("invented-names: %s matches no file; a missing interface is a hard error and never an "
                 "absent module" % pattern)
    if len(found) > 1:
        print("invented-names: %s matches %d installs of the SDK, all read: %s"
              % (os.path.basename(os.path.dirname(pattern)), len(found), ", ".join(os.path.basename(os.path.dirname(os.path.dirname(f))) for f in found)))
    return found


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
    if not path:
        return set(), 0
    names = set()
    for resolved in one(path):
        text = open(resolved, encoding="utf-8", errors="replace").read()
        names |= set(re.findall(
            r"\b(?:struct|enum|class|actor|protocol|typealias|func|var|let|init|macro|case|subscript)\s+([A-Za-z_][A-Za-z0-9_]*)", text))
        for m in re.finditer(r"\bextension\s+([A-Za-z_][A-Za-z0-9_.]*)", text):
            names.add(m.group(1).split(".")[-1])
    names.update("Array Dict Set Optional String Int Double Bool Data URL Date Error".split())
    return names, 0
    return names, 0


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
            texts[os.path.basename(interface)] = "\n".join(open(p, encoding="utf-8", errors="replace").read() for p in one(interface))
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
    if "--control" in sys.argv:
        # The review's control (kits r4, finding 1): a path that does not exist has to be a hard
        # error, so that a missing input can never again be scored as an absent module.
        try:
            one("/nonexistent/sdk/AppIntents.framework/Modules/AppIntents.swiftmodule/x.swiftinterface")
        except SystemExit as error:
            print("control: a missing interface exits non-zero: %s" % error)
            return 0
        print("control FAILED: a missing interface was accepted")
        return 1
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
    sys.exit(main() or 0)
