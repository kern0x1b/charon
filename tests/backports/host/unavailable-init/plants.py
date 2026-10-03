#!/usr/bin/env python3
"""plants.py - the mutations that must turn check_port.py red, chosen from the table.

    python3 plants.py <expectations.tsv> <package dir> <framework>...

Prints one TSV line per plant: label, framework, file (relative to the package), needle, replacement,
with a newline in either of the last two written as the two characters \n so that one plant is one line.
Nothing here
is written by hand: the file is the one the table names for the class, the needle is that class's own
call of the macro the table names, and the replacement is the mistake. A plant written by hand stops
applying the moment a row moves, and a plant that does not apply proves nothing.

Three mistakes, one per framework that owes anything:

  1. a class that must refuse is left to NSObject instead - the macro's call commented out;
  2. a class that must NOT be defined gets a definition anyway - the macro's call added;
  3. the macro raises an exception that was not measured - the name in its own raise replaced.
"""
import os
import re
import sys


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


def anchor_line(source, cls):
    """The two lines a definition goes between: the class's own @implementation line and the one after
    it, or the brace that closes its ivar block and the one after that, because a macro inside the
    braces is not a method.

    TWO lines and not one, because a one-line needle of a closing brace matches the first brace in the
    file rather than this class's - measured: a plant anchored on `}` rewrote an unrelated brace and the
    mutant did not build, which is not the same as the check noticing."""
    lines = open(source, encoding="utf-8").read().split("\n")
    for index, line in enumerate(lines):
        if not line.startswith("@implementation %s" % cls):
            continue
        if not line.rstrip().endswith("{"):
            return line + "\n" + lines[index + 1]
        depth = 1
        scan = index + 1
        while scan < len(lines) and depth:
            depth += lines[scan].count("{") - lines[scan].count("}")
            scan += 1
        if scan >= len(lines):
            return None
        pair = lines[scan - 1] + "\n" + lines[scan]
        # The pair has to be in the file as it stands, or the needle matches nothing and the plant
        # reports that it did not apply rather than quietly checking nothing.
        return pair if pair in "\n".join(lines) else lines[scan]
    return None


def header_of(package, macro):
    """The header that defines the macro, so the third plant edits the macro's own body."""
    for folder, _, files in os.walk(package):
        for entry in sorted(files):
            if not entry.endswith(".h"):
                continue
            path = os.path.join(folder, entry)
            if re.search(r"^#define %s\b" % re.escape(macro), open(path, encoding="utf-8").read(), re.M):
                return os.path.relpath(path, package)
    return None


def raise_line(package, header, exception):
    """The macro's raise, as the one piece of it that is on one line: `raise:<exception>`.

    Not the whole statement - a raise spans two or three continued lines in these macros, and a needle
    that swallowed the continuations would not compile when it was replaced. The exception name is the
    part the check reads, so it is the part the plant moves.
    """
    body = open(os.path.join(package, header), encoding="utf-8").read()
    needle = "raise:%s" % exception
    return needle if needle in body else None


def main():
    table, package = sys.argv[1], sys.argv[2]
    wanted = sys.argv[3:] or sorted({r["framework"] for r in rows_of(table)})
    for framework in wanted:
        mine = [r for r in rows_of(table) if r["framework"] == framework]
        owes = [r for r in mine if r["port-init"] == "raise"]
        none = [r for r in mine if r["port-init"] == "none"]
        if not owes and not none:
            continue
        macro = owes[0]["port-macro"] if owes else "-"
        # The call as the class writes it: with the literal reason when the measurement gave one.
        call = None
        for row in owes:
            # The call as the class writes it. A row whose reason is the empty string still writes it
            # out - `MACRO(@"")` - because that is the measured reason; only a reason the framework
            # builds from the class name is written as the bare macro.
            candidate = row["port-macro"] + ("" if row.get("reason-template")
                                             else '(@"%s")' % row["reason"])
            source = os.path.join(package, row["port-source"])
            if candidate in open(source, encoding="utf-8").read():
                call, owner = candidate, row
                break
        if call:
            # Commented out rather than deleted: a delete leaves a file the compiler is then asked about
            # for a different reason, and a mutant that does not build has proved nothing about the
            # check. What the check has to notice is that the class no longer answers with the macro.
            print("\t".join(["a class that must refuse is left to NSObject instead", framework,
                             owner["port-source"].split("/")[-1], call, "/* %s */" % call]))
        if none:
            anchor = anchor_line(os.path.join(package, none[0]["port-source"]), none[0]["class"])
            insert = (macro + ("" if owes[0].get("reason-template") else '(@"%s")' % owes[0]["reason"])
                     if owes else
                     # Nothing in this framework is owed, so there is no macro to call and the mistake
                     # has to be written out: NSObject's pair spelled into a class whose own class
                     # carries neither selector.
                     "-(instancetype)init { return [super init]; }")
            if anchor:
                print("\t".join(["a class that must NOT be defined gets a definition anyway", framework,
                                 none[0]["port-source"].split("/")[-1],
                                 anchor.replace("\n", "\\n"),
                                 (anchor + "\n" + insert).replace("\n", "\\n")]))
        if not owes:
            continue
        header = header_of(package, macro)
        other = "NSGenericException" if owes[0]["exception"] != "NSGenericException" else "NSRangeException"
        line = raise_line(package, header, owes[0]["exception"]) if header else None
        if header and line:
            print("\t".join(["the macro raises an exception that was not measured", framework,
                             os.path.basename(header), line, "raise:" + other]))


main()
