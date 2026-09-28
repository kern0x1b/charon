#!/usr/bin/env python3
"""Write the UIKit objects that carry the measured constants, one per first-exporting release.

    xmake l tools/corpus/gen-uikit-constants.py

Every value comes from `tools/corpus/uikit-constants.tsv`, which is what `charon/tools/cfconst.py`
and the held dyld caches measured; nothing here is typed by hand. One object carries the API of one
release, because an object is kept or reexported as a whole and an object that defines a symbol the
band already has beside one it does not is refused at link time
(`modules/apple/backports.lua`, `band()`), so the file per release is the release the symbols first
appear in, measured rather than read from a header.

A constant another registry file already names is not written again: two files naming one symbol is
an error the build refuses (`registry()`: "is named by both ... and ..."), and `UIKitExportedConstants-<release>.m`
carries those on main. The exclusion is read from that registry, so it cannot come back unnoticed.
"""
import collections
import csv
import re
import glob
import json
import os
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))   # tools/corpus/.. is the repository
TABLE = os.path.join(HERE, "uikit-constants.tsv")
OUT = os.path.join(ROOT, "packages", "a", "apple-backports", "UIKit")
FACTS = os.path.join(ROOT, "packages", "a", "apple-backports", "facts", "UIKit")
REGISTRY = os.path.join(ROOT, "packages", "a", "apple-backports", "registry", "UIKit")
OWNED = "uikit-constants.json"

ATTRS = ("API_AVAILABLE", "API_UNAVAILABLE", "API_DEPRECATED", "NS_SWIFT_NAME",
         "NS_REFINED_FOR_SWIFT", "NS_SWIFT_UNAVAILABLE", "UIKIT_AVAILABLE", "NS_CLASS_AVAILABLE",
         "NS_AVAILABLE", "API_DEPRECATED_WITH_REPLACEMENT")
KEYWORDS = {"default"}

# The C function that shares the 16.0 object, because it reads UIGuidedAccessErrorDomain from it.
# A function in one object that reaches a constant in another breaks in exactly the bands where the
# two land on opposite sides of the release split (charon/AGENTS.md, "A C function shared between
# backport files"), so the generator owns this text too: it is the file's author, not a hand edit
# that a regeneration would drop.
EXTRAS = {
    "16.0": ("""// Configuring the accessibility features of a Single App Mode session, iOS 12.2, and the
// error domain its failures are reported in (the value of the domain read from the 16.0
// cache, the oldest held release that exports it).
//
// It is in this object because it reads UIGuidedAccessErrorDomain, which is above: a C function
// that reaches a constant in another object breaks in exactly the bands where the two land on
// opposite sides of the release split (charon/AGENTS.md, "A C function shared between backport
// files"). Both arrived in 12.2, whose first held exporting release is 16.0, so the object carries
// one release.

void UIGuidedAccessConfigureAccessibilityFeatures(UIGuidedAccessAccessibilityFeature features, BOOL enabled, void (^completion)(BOOL success, NSError *error))
{
    if (!completion)
        return;
    // "The application is not authorized to perform the requested action. For example, it may have
    // requested a configuration change but is not locked into Single App Mode via a configuration
    // profile" (SDK 26.2, UIGuidedAccess.h:17-19, UIGuidedAccessErrorPermissionDenied) - which is
    // this case exactly: the function changes what a Single App Mode session allows, there is no
    // such session here, and the request is answered on the next turn of the main queue, as the
    // release's own completion is not called from inside the request.
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(NO, [NSError errorWithDomain:UIGuidedAccessErrorDomain
                                            code:UIGuidedAccessErrorPermissionDenied
                                        userInfo:nil]);
    });
}"""),
}


def clean_type(text):
    for attr in ATTRS:
        text = re.sub(r"\b%s\b(\([^)]*\))?" % attr, " ", text)
    text = re.sub(r"\b_Nullable\b|\b_Nonnull\b|\b__kindof\b|\b_null_unspecified\b", " ", text)
    return " ".join(text.split())


def c_quote(text):
    out = []
    for ch in text:
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ord(ch) < 0x20:
            out.append("\\%03o" % ord(ch))
        else:
            out.append(ch)
    return "".join(out)


def spell(name):
    return "`%s`" % name if name in KEYWORDS else name


def literal(row):
    """The C literal a row carries, or nil when the value is not one.

    A constant's value is a number or a name; a *block*'s is the address of the release's own code,
    and three rows of the first version of the table held one - the colour transformers, which are
    implemented in UIConfigurationColorTransformers14.m and have no value to carry. A hex address is
    not a value, so it is refused here rather than written out as one.
    """
    value = row["value"]
    if row["kind"] == "constant string":
        if len(value) >= 2 and value[0] == '"' and value[-1] == '"':
            value = value[1:-1]
        return '@"%s"' % c_quote(value)
    if re.match(r"^-?[0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?$", value):
        return value
    if re.match(r"^-?[A-Z][A-Z0-9_]*$", value):
        return value
    if value.startswith("{") and value.endswith("}"):
        members = [m.strip() for m in value[1:-1].split(",")]
        if members and all(re.match(r"^[A-Za-z_]\w* = (-?[0-9.]+([eE][+-]?[0-9]+)?|-?[A-Z][A-Z0-9_]*)$", m)
                          for m in members):
            return "{%s}" % ", ".join("." + m for m in members)
    return None


def carried_elsewhere():
    """The names main's own UIKitExportedConstants-<release>.m objects define.

    Not the registry: this band's own entries live in the framework's other registry files, so
    reading those would count its own work as another band's and discard all of it. The duplicate
    that breaks a link is a symbol two *objects* define, and those objects are the exported-constants
    ones on main.
    """
    found = set()
    for path in sorted(glob.glob(os.path.join(OUT, "UIKitExportedConstants-*.m"))):
        for line in open(path, encoding="utf-8"):
            match = re.match(r"^\s*[\w \*]+?\b(\w+)\s*=", line)
            if match:
                found.add(match.group(1))
    return found


def main():
    with open(TABLE, newline="", encoding="utf-8") as handle:
        measured = list(csv.DictReader(handle, delimiter="\t"))
    elsewhere = carried_elsewhere()
    rows = [r for r in measured if r["api"] not in elsewhere]
    skipped = [r for r in measured if r["api"] in elsewhere]

    by_release = collections.defaultdict(list)
    for row in rows:
        by_release[row["from-release"]].append(row)

    os.makedirs(OUT, exist_ok=True)
    os.makedirs(FACTS, exist_ok=True)
    entries, written_files = [], []
    for release in sorted(by_release, key=lambda r: [int(x) for x in r.split(".")]):
        items = sorted(by_release[release], key=lambda r: r["api"])
        tag = release.replace(".", "")
        source = "UIKitConstants%s.m" % tag
        facts = "UIKitConstants%s.md" % tag
        images = collections.Counter(i["image"] for i in items).most_common(1)[0][0]
        header = [
            "// The UIKit constants first exported by iOS %s (%s)." % (release, facts),
            "//",
            "// Generated:  xmake l tools/corpus/gen-uikit-constants.py",
            "// from tools/corpus/uikit-constants.tsv. Do not edit this file by hand; regenerate it.",
            "//",
            "// One object carries one release: every symbol here is first exported by the oldest",
            "// held release that has it, so a band from %s on re-exports the release's own and the" % release,
            "// bands below keep this one.",
            "//",
            "// Every value below was read out of a real dyld shared cache, %s," % (images or "?")
            , "// never from a header and never from a host framework.",
            "",
            "#import <UIKit/UIKit.h>",
            "",
        ]
        lines = list(header)
        for item in items:
            written = literal(item)
            if written is None:
                print("the table's %s carries %r, which is not a C literal: a block or a function has "
                      "no value to carry, and its implementation is a hand-written file"
                      % (item["api"], item["value"]), file=sys.stderr)
                return 1
            if item.get("floor"):
                # A typedef the SDK being built against may not have: the release it arrived in is
                # the SDK's own API_AVAILABLE on the typedef, and the two spellings differ only in
                # the type, so the value is written once under a guard on __IPHONE_OS_VERSION_MAX_ALLOWED.
                declared = "%s %s = %s;" % (clean_type(item["c-type"]), item["api"], written)
                fallback = "%s %s = %s;" % (item["underlying"], item["api"], written)
                major, minor = (item["floor"].split(".") + ["0"])[:2]
                lines.append("#if __IPHONE_OS_VERSION_MAX_ALLOWED >= %d"
                             % (int(major) * 10000 + int(minor) * 100))
                lines.append(declared)
                lines.append("#else")
                lines.append(fallback)
                lines.append("#endif")
            else:
                lines.append("%s %s = %s;" % (clean_type(item["c-type"]), item["api"], written))
        if release in EXTRAS:
            lines.append("")
            lines.append(EXTRAS[release])
        lines.append("")
        with open(os.path.join(OUT, source), "w", encoding="utf-8") as out:
            out.write("\n".join(lines))
        written_files.append(source)
        for item in items:
            entries.append({
                "api": item["api"], "kind": "constant", "introduced": "", "minimum": "6.0",
                "status": "implemented", "facts": "facts/UIKit/" + facts,
                "source": "the value read out of the %s cache of iOS %s, the oldest held release that "
                          "exports the symbol (%s)"
                          % (os.path.basename(item["image"]), release, item["image"]),
            })
        with open(os.path.join(FACTS, facts), "w", encoding="utf-8") as out:
            out.write("# The UIKit constants first exported by iOS %s\n\n" % release)
            out.write("`UIKit/%s`, generated by `xmake l tools/corpus/gen-uikit-constants.py` from\n"
                      "`tools/corpus/uikit-constants.tsv`.\n\n" % source)
            out.write("| constant | the value |\n| --- | --- |\n")
            for item in items:
                out.write("| `%s` | `%s` |\n" % (item["api"], item["value"]))
    with open(os.path.join(REGISTRY, OWNED), "w", encoding="utf-8") as out:
        json.dump({"framework": "UIKit", "entries": entries}, out, indent=1)
        out.write("\n")
    for stale in sorted(glob.glob(os.path.join(OUT, "UIKitConstants*.m"))):
        if os.path.basename(stale) not in written_files:
            os.unlink(stale)
            print("removed the object with nothing left in it: %s" % os.path.basename(stale))
    print("%d constants in %d objects; %d left out, another registry file already names them"
          % (len(rows), len(written_files), len(skipped)))
    for source in written_files:
        print("  %s" % source)
    return 0


if __name__ == "__main__":
    sys.exit(main())
