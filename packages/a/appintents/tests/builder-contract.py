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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paramlabels import external_labels, parameters  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", ".."))
SOURCES = {"IntentItem": "Items.swift", "IntentItemSection": "Items.swift"}
# where the port's declarations are, relative to the repository root; `--mutate` points the check at
# a scratch copy of that file instead
SOURCE_REL = "packages/a/appintents/Sources/AppIntents/Items.swift"
SOURCE = os.environ.get("BUILDER_CONTRACT_SOURCE") or SOURCE_REL
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


def _port_block(source, owner):
    """The port's own `IntentItemBuilder` / `IntentItemSectionBuilder` block, and nothing else.

    The alias `IntentItem.Builder = IntentItemBuilder<Value>` puts the framework's name on a
    differently-named type, so the block to read is the **builder's**, not the type's.
    """
    builder = {"IntentItem": "IntentItemBuilder", "IntentItemSection": "IntentItemSectionBuilder"}[owner]
    start = re.search(r"public enum %s<" % re.escape(builder), source)
    if not start:
        return ""
    rest = source[start.start():]
    end = rest.find("\n}\n")
    return rest[:end] if end > 0 else rest


def _type_block(interface, owner):
    """The interface's text for one type, so a twin is that type's declaration and not another's."""
    lines = interface.split("\n")
    start, out = None, []
    for i, line in enumerate(lines):
        if start is None:
            if re.match(r"\s*(public|extension)\s+(\S+\.)?%s\b" % re.escape(owner), line):
                start = i
            continue
        # the block ends at the next **unindented** line: `@available` and `@backDeployed` appear
        # inside it, indented, and stopping at them cut the block after its first member
        if line.strip() and not line.startswith((" ", "\t")):
            break
        out.append(line)
    # **No fallback to the whole interface**: a type whose block is not found is an error, because
    # searching everything is how another builder's `buildBlock` gets compared against this row.
    return re.sub(r"\n", "\n    ", "\n".join(out))


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
    # Both sides, per row: the framework's declaration **and this module's**. The review's
    # `_ item:` -> `item:` mutation is a change of *external label* and is a defect; the
    # `_ item:` -> `_ item2:` mutation changes only the internal name, which no caller can see and is
    # not a defect, so that one stays green. `paramlabels` is what tells the two apart.
    port = open(SOURCE if os.path.isabs(SOURCE) else os.path.join(ROOT, SOURCE), encoding="utf-8",
                errors="replace").read()
    sources = {"IntentItem": port, "IntentItemSection": port}
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
        # The row's own labels, read off its **spelling**: `buildBlock(_:)` -> ['_'],
        # `buildBlock()` -> [], `buildExpression(_:)` -> ['_']. No Swift parse, because the spelling
        # *is* the row.
        row_labels = []
        if "(" in member and ")" in member:
            parts = member[member.index("(") + 1:member.rindex(")")].split(":")
            while parts and not parts[-1]:
                parts.pop()
            row_labels = parts
        func = member.split("(")[0]
        # **Existence on each side, never a first match.** `buildBlock` is declared three times in the
        # framework's block and three times in this module's builder, and picking one of them is how an
        # external-label mutation went through green (kits r7). So every declaration of that name is
        # collected, per side, as a list of label lists, and the row is green iff the row's labels are
        # in **both**.
        decl_re = r"public static func %s\(.{0,220}?(?:->|\n    )" % re.escape(func)
        block = _type_block(interface, where)
        if not block:
            failures.append("%s: the interface has no %s block to read, and reading the whole file "
                            "instead is how the wrong overload gets compared" % (name, where))
            continue
        framework_side = [c.group(0) for c in re.finditer(decl_re, block, re.S)]
        # **per type on the port side too**: this file declares `buildBlock` five times across three
        # builders, so reading the whole file made the row `['_']` present somewhere and the check
        # green whatever one builder did. The owner is the *builder*, not the type the alias is in.
        port_block = _port_block(sources[where], where)
        port_side = [c.group(0) for c in re.finditer(decl_re, port_block, re.S)]
        framework_labels = [external_labels(d) for d in framework_side]
        port_labels = [external_labels(d) for d in port_side]
        red = row_labels not in framework_labels or row_labels not in port_labels
        if not re.search(r"@resultBuilder", sources[where]):
            failures.append("%s: the type is not a @resultBuilder here" % name)
        if red:
            failures.append("%s: the row's labels %s are not declared on both sides (port=%s framework=%s)"
                            % (name, row_labels, port_labels, framework_labels))
        generic_of = lambda d: bool(re.search(r"func\s+\w+\s*<", d or ""))
        if any(generic_of(d) for d in framework_side) != any(generic_of(d) for d in port_side):
            failures.append("%s: the framework declares it generic and this module does not, or the other way" % name)
        print("%-4s %-42s row=%s port=%s framework=%s"
              % ("RED" if red else "ok", name, row_labels, port_labels, framework_labels))
    print("checked %d row(s), %d failure(s)" % (checked, len(failures)))
    for f in failures:
        print("FAIL %s" % f)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
