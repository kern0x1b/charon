#!/usr/bin/env python3
"""The 111 Swift constant rows of the UIKit checklist, as declarations in the port's UIKit overlay.

Each of the 28 enclosing types becomes either

  - a namespace type of our own, with an extension on the enclosing Objective-C class carrying a
    `typealias` for it, where the root is a class the lifted headers declare
    (`UIButton.Configuration.CornerStyle.capsule`), or
  - a plain namespace type, where the root is one the lifted headers do not declare at all
    (`UICellAccessory.AccessoryType.checkmark`).

The split is not a judgement: it is what the typecheck says. `.agent-work/runs/uikit-c/roots.txt`
holds the roots the lifted headers do not have, taken from the errors of the 111 single-name
typecheck. The case names and their payloads are the SDK's own, from
`UIKit.framework/Modules/UIKit.swiftmodule/arm64e-apple-ios.swiftinterface`.

Only the cases this checklist names are declared. A type's other members - its `==`, its
`hash(into:)`, its `init(rawValue:)`, the types its payloads point at - are other rows of the
surface and other bands' work, so nothing here claims them.
"""
import csv
import os

# Where the two inputs are: the SDK's own swiftinterface (the case names and payloads) and this
# band's checklist (which rows of the surface are wanted). Both from the environment, so the file
# carries no path of this machine.
INTERFACE = os.environ["UIKIT_SWIFTINTERFACE"]
HERE = os.environ["UIKIT_CHECKLIST_DIR"]
SWIFT_KEYWORDS = {"default", "Type", "Protocol", "Self", "super", "nil", "true", "false", "let",
                  "var", "func", "class", "enum", "struct", "case", "where", "in", "is", "as"}


def spell(case):
    """A case name the compiler accepts: a Swift keyword needs backticks, and the interface prints
    `case default` bare where the SDK's own source writes `case `default``."""
    return "`%s`" % case if case in SWIFT_KEYWORDS else case


import re
import sys


# The roots the lifted headers do not declare, from the 111 single-name typecheck's errors.
ABSENT_ROOTS = set()
for line in open(HERE + "/roots.txt", encoding="utf-8"):
    name = line.strip()
    if name:
        ABSENT_ROOTS.add(name)


INTERFACE_LINES = open(INTERFACE, encoding="utf-8").read().split("\n")


def index_declarations():
    """{qualified name: (start line, end line)} for every enum/struct/class in the interface.

    The stack of open braces is the type path: an `enum` one brace deep is a top-level type, one
    two deep is a member of the last, and so on, which is exactly the nesting the surface's names
    use. `UIButton` in the interface is a class, and `CornerStyle` inside it is a member, so
    `UIButton.CornerStyle` is a key and `UIButton.Configuration.CornerStyle` is another.
    """
    found, stack = {}, []
    for index, line in enumerate(INTERFACE_LINES):
        match = re.search(r"\b(enum|struct|class) ([A-Za-z_]\w*)", line)
        if not match:
            continue
        kind, name = match.group(1), match.group(2)
        if kind == "class" and not line.rstrip().endswith("{"):
            continue                      # a reference to a class, not its declaration
        path = [n for n in stack if n] + [name]
        # The block runs to the line its own closing brace is on, counted from this declaration.
        depth, cursor = 0, index
        while cursor < len(INTERFACE_LINES):
            depth += INTERFACE_LINES[cursor].count("{") - INTERFACE_LINES[cursor].count("}")
            if depth == 0 and cursor > index:
                break
            cursor += 1
        for inner in INTERFACE_LINES[index:cursor]:
            if re.search(r"\b(enum|struct) ([A-Za-z_]\w*)", inner):
                stack.append(re.search(r"\b(enum|struct) ([A-Za-z_]\w*)", inner).group(2))
            elif inner.strip() == "}":
                if stack:
                    stack.pop()
        found[".".join(path)] = (index, cursor)
    return found


DECLARATIONS = None


def cases_of(swift_type, wanted):
    """The case declarations of the enumeration the surface names swift_type.

    Anchored on a case name rather than on the type's short name: three unrelated types declare a
    member called `Content`, and a type's own short name is not unique in the interface either. The
    block is the one that declares the case, found by walking back to the enumeration above it.
    """
    lines = INTERFACE_LINES
    def block_above(anchor):
        # The declaration the case belongs to is the nearest `enum`/`struct` *less indented* than
        # the case: a case declared after a nested type closes that nested type first, and walking
        # back to the nearest declaration of any kind would land in the nested one (UIPointerEffect
        # declares its cases after TintMode).
        column = len(lines[anchor]) - len(lines[anchor].lstrip())
        start = None
        for index in range(anchor, -1, -1):
            if re.search(r"\b(enum|struct) [A-Za-z_]\w*", lines[index]):
                here = len(lines[index]) - len(lines[index].lstrip())
                if here < column:
                    start = index
                    break
        if start is None:
            return None
        depth, cursor = 0, start
        while cursor < len(lines):
            depth += lines[cursor].count("{") - lines[cursor].count("}")
            if depth == 0 and cursor > start:
                break
            cursor += 1
        return start, cursor

    def split_cases(text):
        """The cases of one `case` line, payloads kept whole.

        `case hover(_: UITargetedPreview, preferredTintMode: UIPointerEffect.TintMode = .overlay, ...)`
        is one case, so a comma inside its parentheses does not end it: the parentheses are balanced
        before anything is split.
        """
        parts, depth, start = [], 0, 0
        for index, char in enumerate(text):
            if char in "([":
                depth += 1
            elif char in ")]":
                depth -= 1
            elif char == "," and depth == 0:
                parts.append(text[start:index])
                start = index + 1
        parts.append(text[start:])
        found = []
        for part in parts:
            part = part.strip()
            if not part:
                continue
            match = re.match(r"`?([A-Za-z_]\w*)`?(\((.*)\))?$", part, re.S)
            if match:
                found.append((match.group(1), match.group(2) or ""))
        return found

    def cases_in(span):
        start, cursor = span
        found, pending = {}, []
        for line in lines[start:cursor + 1]:
            stripped = line.strip()
            if stripped.startswith("case "):
                pending.extend(split_cases(stripped[5:]))
            elif stripped.startswith(("func ", "var ", "let ", "static ", "public ", "}")):
                for entry in pending:
                    found[entry[0]] = entry[1]
                pending = []
        for entry in pending:
            found[entry[0]] = entry[1]
        return found

    for wanted_case in sorted(wanted, key=lambda c: sum(1 for line in lines if c in line)):
        pattern = re.compile(r"\bcase `?%s\b" % re.escape(wanted_case))
        for index, line in enumerate(lines):
            if not pattern.search(line):
                continue
            span = block_above(index)
            if not span:
                continue
            found = cases_in(span)
            if set(wanted) <= set(found):
                return {name: found[name] for name in wanted}
    return None

    found, pending = {}, []
    for line in lines[start:cursor + 1]:
        stripped = line.strip()
        if stripped.startswith("case "):
            for part in stripped[5:].split(","):
                part = part.strip()
                if not part:
                    continue
                match = re.match(r"`?([A-Za-z_]\w*)`?(\((.*)\))?$", part)
                if match:
                    pending.append((match.group(1), match.group(2) or ""))
        elif stripped[:1] in ("f", "v", "l", "s", "c", "p", "i", "t", "}"):
            if stripped.startswith(("func ", "var ", "let ", "static ", "public ", "case ")) or stripped == "}":
                for entry in pending:
                    found[entry[0]] = entry[1]
                pending = []
    for entry in pending:
        found[entry[0]] = entry[1]
    return {name: found[name] for name in wanted if name in found}


def main():
    with open(HERE + "/checklist.tsv", newline="", encoding="utf-8") as handle:
        rows = [r for r in csv.DictReader(handle, delimiter="\t")
                if r["lang"] == "swift" and r["kind"] == "constant"]
    types = {}
    for row in rows:
        types.setdefault(row["api"].rsplit(".", 1)[0], []).append(row["api"].rsplit(".", 1)[1])

    out = ["""// The UIKit types and cases of the SDK 26.2 Swift surface that the port's UIKit overlay does
// not carry, from the surface's own checklist (`coordination/corpus/ledger/UIKit.tsv`).
//
// Two shapes, and which one a type takes is not a judgement: it is what the typecheck says. Where
// the lifted headers declare the enclosing Objective-C class, the overlay carries a namespace type
// of its own and a `typealias` on the class, so `UIButton.Configuration.CornerStyle.capsule`
// resolves as the SDK's own overlay makes it resolve. Where the headers declare no such class at
// all - the enumeration is native Swift in UIKitCore and has no Objective-C spelling - the
// namespace is declared outright.
//
// The case names and their payloads are the SDK's own, read from
// `UIKit.framework/Modules/UIKit.swiftmodule/arm64e-apple-ios.swiftinterface`. Only the cases this
// checklist names are declared: a type's `==`, its `hash(into:)`, its `init(rawValue:)` and the
// types its payloads point at are other rows of the surface.
"""]
    aliases, unresolved, leaf_cases = [], [], {}
    for swift_type in sorted(types):
        wanted = types[swift_type]
        parts = swift_type.split(".")
        root, chain = parts[0], parts[1:]
        # UIPointerEffect and UIPointerShape are the type itself, not a member of one.
        payloads = cases_of(swift_type, wanted)
        if payloads is None or set(payloads) != set(wanted):
            unresolved.append((swift_type, sorted(set(wanted) - set(payloads or {}))))
            continue
        leaf_cases[swift_type] = payloads
        if chain and root not in ABSENT_ROOTS:
            # One typealias per level, each naming the namespace type nested at that level.
            for depth, level in enumerate(chain):
                owner = root if depth == 0 else "Charon" + "".join(
                    q[:1].upper() + q[1:] for q in parts[:depth]) + "".join(
                    "." + q[:1].upper() + q[1:] for q in parts[1:depth])
                target = "Charon" + "".join(q[:1].upper() + q[1:] for q in parts[:depth + 1]) + "".join(
                    "." + q[:1].upper() + q[1:] for q in parts[1:depth + 1])
                aliases.append("extension %s {" % owner)
                aliases.append("    public typealias %s = %s" % (level, target))
                aliases.append("}")
    # One namespace type per level, each nested in the level above it, so a chain of two
    # typealiases reaches the leaf and the leaf's cases sit where the surface's name looks for them.
    tree = {}
    for swift_type in sorted(types):
        node = tree
        for part in swift_type.split("."):
            node = node.setdefault(part, {"cases": None})
    for swift_type, payloads in leaf_cases.items():
        node = tree
        for part in swift_type.split("."):
            node = node[part]
        node["cases"] = payloads

    def emit(node, path, depth):
        name = path[-1] if depth else "Charon" + path[-1]
        pad = "    " * depth
        out.append("%spublic enum %s {" % (pad, name))
        if node["cases"] is not None:
            for case in sorted(node["cases"]):
                out.append("%s    case %s%s" % (pad, spell(case), node["cases"][case]))
        for part in sorted(node):
            if part == "cases":
                continue
            out.append("%s    public enum %s {" % (pad, part))
            if node[part]["cases"] is not None:
                for case in sorted(node[part]["cases"]):
                    out.append("%s        case %s%s" % (pad, spell(case), node[part]["cases"][case]))
            for inner in sorted(node[part]):
                if inner == "cases":
                    continue
                emit(node[part][inner], path + [part, inner], depth + 2)
            out.append("%s    }" % pad)
        out.append("%s}" % pad)

    for root in sorted(tree):
        if root == "cases":
            continue
        emit(tree[root], [root], 0)
        out.append("")

    if aliases:
        out.append("")
        out.extend(aliases)
    print("\n".join(out))
    for swift_type, missing in unresolved:
        print("// UNRESOLVED %s: %s" % (swift_type, ", ".join(missing)), file=sys.stderr)
    return 1 if unresolved else 0


if __name__ == "__main__":
    sys.exit(main())
