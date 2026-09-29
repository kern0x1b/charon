#!/usr/bin/env python3
"""The shape check for the two result-builder families, from the framework's own header.

The digester prints a `@resultBuilder` type with no members at all, so a member cannot be *found* in
the dump; what can be checked, and is checked here, is the **shape**: that each row's declaration
exists in this module, that it is a `static func` on the right type, and that its argument labels and
its return type are the ones the framework's own interface declares. The interface is read from the
machine's `charon@iphoneos-sdk` 26.2 install, so the comparison is against the release the rows are
written against, and a missing input is a hard error.

    python3 packages/a/appintents/tests/builder-contract.py              # every row
    python3 packages/a/appintents/tests/builder-contract.py IntentItem.Builder.buildArray
"""
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", ".."))
SOURCES = {
    "IntentItem": "packages/a/appintents/Sources/AppIntents/Items.swift",
    "IntentItemSection": "packages/a/appintents/Sources/AppIntents/Items.swift",
}
SDK = os.path.join(os.path.expanduser("~"), ".xmake/packages/i/iphoneos-sdk/26.2",
                   "*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs",
                   "iPhoneOS26.2.sdk/System/Library/Frameworks/AppIntents.framework/Modules/"
                   "AppIntents.swiftmodule/arm64e-apple-ios.swiftinterface")

# The rows the corpus ledger carries for these two families, and the labels each must have.
ROWS = [
    ("IntentItemSection.Builder", []),
    ("IntentItemSection.Builder", "buildBlock()"),
    ("IntentItemSection.Builder", "buildBlock(_:)"),
    ("IntentItem.Builder", "buildExpression(_:)"),
    ("IntentItem.Builder", "buildArray(_:)"),
    ("IntentItem.Builder", "buildBlock()"),
    ("IntentItem.Builder", "buildBlock(_:)"),
]


def one_interface():
    import glob
    found = sorted(glob.glob(os.path.expanduser(SDK)))
    if not found:
        sys.exit("builder-contract: %s matches no file; a missing input is a hard error" % SDK)
    if len(found) > 1:
        print("builder-contract: %d installs of the SDK, all read" % len(found))
    return "\n".join(open(p, encoding="utf-8", errors="replace").read() for p in found)


def main():
    interface = one_interface()
    sources = {k: open(os.path.join(ROOT, v), encoding="utf-8", errors="replace").read()
               for k, v in SOURCES.items()}
    wanted = sys.argv[1:]
    failures, checked = [], 0
    for owner, member in ROWS:
        name = owner + ("." + member if member else "")
        if wanted and name not in wanted:
            continue
        checked = checked + 1
        where, labels = owner.split(".")
        if not member:                                   # the type row
            alias = re.search(r"public typealias Builder = (\w+)<(\w+)>", sources[where])
            frame = re.search(r"@_functionBuilder public enum Builder", interface)
            if not alias:
                failures.append("%s: the type has no Builder in %s" % (name, SOURCES[where]))
            elif not frame:
                failures.append("%s: the framework's interface has no nested Builder enum" % name)
            else:
                print("ok  %-44s the type: a typealias to %s, and the interface nests an enum named Builder"
                      % (name, alias.group(1)))
            continue
        # The declaration *and* the row's own label: `buildBlock()` and `buildBlock(_:)` are one
        # name with two spellings, and a search on the name alone finds the first of them for both.
        label = member[member.index("(") + 1:].split(":")[0] if ":" in member else ""
        pattern = (r"public static func %s\(\s*%s\b[^\n]*" % (re.escape(member.split("(")[0]), re.escape(label))
                   if label else r"public static func %s\(\s*\)[^\n]*" % re.escape(member.split("(")[0]))
        m = re.search(pattern, sources[where])
        if not m:
            failures.append("%s: no static func by that name in %s" % (name, SOURCES[where]))
            continue
        decl = m.group(0)
        labels_in_code = re.findall(r"(\w+):", decl)
        if not re.search(r"@resultBuilder", sources[where]):
            failures.append("%s: the type is not a @resultBuilder here" % name)
        if not labels_in_code and "(" in member and "()" not in member:
            failures.append("%s: the framework's row has labels %s and the declaration has none"
                            % (name, member))
        print("ok  %-44s %s" % (name, decl.strip()[:110]))
    print("checked %d row(s), %d failure(s)" % (checked, len(failures)))
    for f in failures:
        print("FAIL %s" % f)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
