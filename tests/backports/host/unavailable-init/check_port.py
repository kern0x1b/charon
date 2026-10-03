#!/usr/bin/env python3
"""check_port.py - the port's -init and +new for every class the host answers, in the source and in
the compiled armv7 objects.

    python3 check_port.py <the port's package directory> <the directory holding the compiled objects>

Held to expectations.tsv, which is the transcription of what the HOST answered, so nothing here is an
expectation taken from the code under test. For each class two things are asked, and they fail
differently, which is why both are:

  * the SOURCE. The class's own @implementation block must raise the exception the host raises with
    the reason the host gives, or - for the four whose own class carries neither selector - must spell
    out NSObject's pair. A source check alone would pass on a method the compiler dropped.

  * the OBJECT. The compiled object must carry -init in the class's instance list and +new in its
    metaclass list. An object check alone would pass on a pair that raises the wrong thing, so the two
    are asked together.

The class's method list is read with otool, from the object the table names, and the sign of each
selector is what the corpus asks: -init is an instance method and +new a class one.
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
    # row needs - not a crash: the control of this harness IS an empty object, and a check that dies on
    # it has proved that it runs, not that it notices.
    out = done.stdout if done.returncode == 0 else ""
    found = {}
    for line in out.split("\n"):
        parts = line.rstrip("\n").split("\t")
        if len(parts) != 7 or parts[0] != "class":
            continue
        found[parts[1]] = {"instance": set(parts[4].split(",")) - {""},
                           "class": set(parts[5].split(",")) - {""}}
    return found


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


def block_of(text, cls):
    """The class's own @implementation block, never a category's."""
    match = re.search(r"^@implementation %s\n(.*?)^@end" % re.escape(cls), text, re.S | re.M)
    return match.group(1) if match else None


def main():
    if len(sys.argv) != 4:
        sys.exit("check_port.py: pass the package directory, the compiled objects directory and the "
                 "repository root")
    package, objdir, root = sys.argv[1], sys.argv[2], sys.argv[3]
    expected = [r for r in rows_of(os.path.join(HERE, "expectations.tsv")) if r["framework"] == "SensorKit"]
    failures, ok = [], 0
    for row in expected:
        name, problems = row["class"], []
        source = os.path.join(package, row["port-source"])
        obj = os.path.join(objdir, row["port-object"])
        body = block_of(open(source, encoding="utf-8").read(), name) if os.path.exists(source) else None
        if body is None:
            problems.append("no @implementation %s in %s" % (name, row["port-source"]))
        else:
            # The block names the macro, so the macro's own definition is part of what is being checked:
            # a macro that stopped raising, or that raised something else, has to be caught too.
            call = re.search(r"%s(?:\(@\"(?P<reason>[^\"]*)\"\))?" % re.escape(row["port-macro"]), body)
            if not call:
                problems.append("the block does not answer with %s, which is what the table names"
                                % row["port-macro"])
            else:
                if row["answer"] == "raises":
                    if (call.group("reason") or None) != (row["reason"] or None):
                        problems.append("the host's reason is %r and the block raises with %r"
                                        % (row["reason"], call.group("reason")))
                    definition = macro_definition(package, row["port-macro"])
                    if definition is None:
                        problems.append("%s is used but defined nowhere under %s"
                                        % (row["port-macro"], package))
                    elif row["exception"] not in definition:
                        problems.append("the host raises %s and the macro raises something else"
                                        % row["exception"])
                else:
                    definition = macro_definition(package, row["port-macro"])
                    if definition is None:
                        problems.append("%s is used but defined nowhere under %s"
                                        % (row["port-macro"], package))
                    elif "[super init]" not in definition or "[[self alloc] init]" not in definition:
                        problems.append("the host's own class carries neither selector, so this macro "
                                        "must spell out NSObject's pair, and it does not")
        carried = {}
        if not os.path.exists(obj):
            problems.append("%s does not exist" % obj)
        else:
            carried = methods(obj, root).get(name, {"instance": set(), "class": set()})
            if "-init" not in carried["instance"]:
                problems.append("-init is not in the class's instance list of %s" % row["port-object"])
            if "-new" not in carried["class"]:
                problems.append("+new is not in the class's metaclass list of %s" % row["port-object"])
        line = "%-42s source=%-34s object=%s" % (
            name, ("the host's raise" if row["answer"] == "raises" else "NSObject's pair")
            if not [p for p in problems if ".m" in p or "macro" in p] else "MISSING",
            "-init +new" if not [p for p in problems if "object" in p or ".o" in p] else "SELECTOR ABSENT")
        print(line)
        if problems:
            failures.extend("%s: %s" % (name, problem) for problem in problems)
        else:
            ok += 1
    for failure in failures:
        print("FAIL " + failure)
    print("sensorkit-init-port: %d of %d classes the host's answer, in the source and in the object, "
          "%d failures%s" % (ok, len(expected), len(failures), "" if not failures else "  <- SEE FAIL"))
    return 1 if failures else 0


sys.exit(main())
