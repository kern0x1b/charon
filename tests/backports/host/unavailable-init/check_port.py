#!/usr/bin/env python3
"""check_port.py - the port's -init and +new for every class of one framework, in the source and in the
compiled armv7 objects.

    python3 check_port.py <package dir> <compiled objects dir> <repository root> <framework> [...]

Held to expectations.tsv, which is the transcription of what Apple's own class was measured to do, so
nothing here is an expectation taken from the code under test. Where each row's answer came from is the
table's own `oracle` column: `host` for the host's framework, `ios16` for a class read out of a real
release's own cache. Both are measurements of Apple's class; neither is a reading of the header.

THE RULE, and it is per selector rather than per class: where Apple's own class defines -init, the port
defines -init with the measured body; where Apple's own class inherits +new, the port does not define
+new either. A definition where Apple's class has none would put the selector in the port's metadata
where Apple's has none, changing what the class IS and answering the caller exactly what NSObject's
already answers. That is the rule the coordinator settled on 2026-10-03
(coordination/wave-2026-10-03/QUEUE.md), and the two differ per framework: SensorKit's classes define
both selectors, HealthKit's define -init and inherit +new.

For each class two things are asked, and they fail differently, which is why both are:

  * THE SOURCE. The class's @implementation block must carry the macro the table names for every selector
    the table says is owed, with the reason that was measured, and must not define a selector the table
    says is not owed. The macro's own body is read too, so a macro that stopped raising, or that raised
    something else, is caught. A source check alone would pass on a method the compiler dropped.

  * THE OBJECT. Every selector the table says is owed must be in the class's own list of the compiled
    object - -init in the instance list, +new in the metaclass list - and every selector the table says
    is not owed must NOT be there. An object check alone would pass on a pair that raises the wrong
    thing, so the two are asked together.

The class's method list is read with the repository's own reader, tools/corpus/objc-inventory.lua, which
is the one the corpus reads a built library with.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def rows_of(path):
    header, rows = None, []
    for line in open(path, encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        fields = line.rstrip("\n").split("\t")
        if header is None:
            header = fields
            continue
        rows.append(dict(zip(header, fields)))
    return rows


def macro_definition(package, name):
    """A macro's own body, out of the headers of the package, so a macro that changed is part of the
    check. The body runs from the `#define` to the first line that does not end in a backslash."""
    for folder, _, files in os.walk(package):
        for entry in sorted(files):
            if not entry.endswith(".h"):
                continue
            lines = open(os.path.join(folder, entry), encoding="utf-8", errors="replace").read().split("\n")
            for index, line in enumerate(lines):
                if not re.match(r"#define %s\b" % re.escape(name), line):
                    continue
                body = [line]
                while body[-1].rstrip().endswith("\\") and index + 1 < len(lines):
                    index += 1
                    body.append(lines[index])
                return "\n".join(body)
    return None


def methods(obj, root):
    """The object's own selectors, instance and class, keyed by class name.

    Read with the repository's own reader - tools/corpus/objc-inventory.lua, the same one the corpus
    reads a built library with - and not with a second opinion parsed out of `otool -ov` here: a class's
    own method list is the question, and one reader that answers it is enough.
    """
    env = dict(os.environ, CHARON_ROOT=root)
    done = subprocess.run(["xmake", "l", os.path.join(root, "tools", "corpus", "objc-inventory.lua"),
                           obj, "armv7"], cwd=root, env=env, capture_output=True, text=True)
    # An object the reader cannot read carries no selector this check can find, which is the answer the
    # row needs - not a crash: the control of this harness IS an empty object, and a check that died on
    # it would have proved that it runs, not that it notices.
    found = {}
    if done.returncode != 0:
        return found
    for line in done.stdout.split("\n"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 7 or parts[0] != "class":
            continue
        found[parts[1]] = {"instance": set(parts[4].split(",")) - {""},
                           "class": set(parts[5].split(",")) - {""}}
    return found


def block_of(text, cls):
    """The class's own @implementation block, never a category's."""
    match = re.search(r"^@implementation %s\n(.*?)^@end" % re.escape(cls), text, re.S | re.M)
    return match.group(1) if match else None


def check_source(body, row, package, problems):
    """Both selectors of one class, in the source, against what the table says is owed."""
    for selector, sign, owed in (("init", "-", row["port-init"]), ("new", "+", row["port-new"])):
        defined_by_hand = re.search(r"^\s*[-+]\s*\(instancetype\)\s*%s\b" % selector, body, re.M)
        if owed == "none":
            if defined_by_hand:
                problems.append("%s is defined here and Apple's own class carries neither: a definition "
                                "would answer the caller what NSObject's already answers" % selector)
            continue
        if row["port-macro"] == "-":
            problems.append("the table says %s is owed and names no macro for it" % selector)
            continue
        # Which selector the macro defines is read out of the macro's own body, not guessed here: the
        # macro is one pair for SensorKit and one method for HealthKit, and the table says per selector.
        definition = macro_definition(package, row["port-macro"])
        if definition is None:
            problems.append("%s is owed but %s is defined nowhere under %s"
                            % (selector, row["port-macro"], package))
            continue
        macro_has = re.search(re.escape("%s(instancetype)%s" % (sign, selector)), definition)
        if not macro_has:
            problems.append("%s is owed but %s does not define %s"
                            % (selector, row["port-macro"], selector))
            continue
        if not re.search(r"\b%s\b" % re.escape(row["port-macro"]), body):
            problems.append("%s is owed and the block does not answer with %s"
                            % (selector, row["port-macro"]))
            continue
        if row["exception"] not in definition:
            problems.append("the measured exception is %s and the macro raises something else"
                            % row["exception"])
        # A reason the measurement gives as a literal has to appear in the macro or at the call site. A
        # reason the framework builds from the class name carries no literal, and this is what tells the
        # two apart.
        literal = row["reason"] if "%" not in row["reason"] else ""
        if literal and ('@"' + literal + '"') not in body and ('@"' + literal + '"') not in definition:
            problems.append("the reason measured is %r and neither the block nor the macro carries it"
                            % literal)


def check_object(carried, row, selector, problems):
    kind = "instance" if selector == "init" else "class"
    there = ("-" + selector) in carried[kind]
    if row["port-" + selector] == "raise" and not there:
        problems.append("%s is not in the class's %s list of %s" % (selector, kind, row["port-object"]))
    elif row["port-" + selector] == "none" and there:
        problems.append("%s is in the class's %s list of %s, and Apple's own class carries neither"
                        % (selector, kind, row["port-object"]))


def main():
    if len(sys.argv) < 5:
        sys.exit("check_port.py: pass the package directory, the compiled objects directory, the "
                 "repository root and at least one framework")
    package, objdir, root = sys.argv[1:4]
    wanted = sys.argv[4:]
    rows = [r for r in rows_of(os.path.join(HERE, "expectations.tsv")) if r["framework"] in wanted]
    if not rows:
        sys.exit("check_port.py: expectations.tsv holds no row for %s" % ", ".join(wanted))
    failures, ok = [], 0
    for row in rows:
        name, problems = row["class"], []
        source = os.path.join(package, row["port-source"])
        obj = os.path.join(objdir, row["port-object"])
        body = block_of(open(source, encoding="utf-8").read(), name) \
            if os.path.exists(source) else None
        if body is None:
            problems.append("no @implementation %s in %s" % (name, row["port-source"]))
        else:
            check_source(body, row, package, problems)
        carried = {}
        if not os.path.exists(obj):
            problems.append("%s does not exist" % obj)
        else:
            carried = methods(obj, root).get(name, {"instance": set(), "class": set()})
            check_object(carried, row, "init", problems)
            check_object(carried, row, "new", problems)
        print("%-44s source: init=%-5s new=%-5s   object: %s"
              % (name, row["port-init"], row["port-new"],
                 ("agrees" if not [p for p in problems if "list of" in p or "does not exist" in p]
                  else "DIFFERS")))
        if problems:
            failures.extend("%s: %s" % (name, problem) for problem in problems)
        else:
            ok += 1
    for failure in failures:
        print("FAIL " + failure)
    print("unavailable-init-port %s: %d of %d classes as measured, in the source and in the object, "
          "%d failures%s" % (",".join(wanted), ok, len(rows), len(failures),
                             "" if not failures else "  <- SEE FAIL"))
    return 1 if failures else 0


sys.exit(main())
