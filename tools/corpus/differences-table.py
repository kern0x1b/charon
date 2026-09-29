#!/usr/bin/env python3
# differences-table.py CI-DIFF MODELIO-DIFF [--page PATH] [--write]
#
# The two differential runs, read as compare.py wrote them, turned into the group tables
# facts/CoreImage/Differences.md carries.  The tables are generated here and not written by
# hand, because a hand-written count is a number nobody checks: the last pass had a table that
# contradicted its own run in five places and three of the forty-one lines in no row at all.
#
# What it prints per group: the count, the first differing key, and the two lines that key
# produced.  What it refuses to do: a table that does not add up.  The sum of the counts is
# compared with the "N different" the run itself printed, and a difference is an error - so a
# group that loses a key, a group that gains one, and a row that describes a family the run no
# longer has are all caught by the same arithmetic.
#
#   differences-table.py ci-diff.txt modelio-diff.txt
#       prints both tables and the arithmetic, exit 0 only if both add up
#   differences-table.py ci-diff.txt modelio-diff.txt --page <markdown>
#       also reads the page and reports every count in it that this run does not produce
#
# The key of a line is compare.py's key: the text up to the first number, and the n-th
# occurrence of a key is the n-th of that key.  Groups are the key prefixes below, and a key
# that matches no group is a failure of this script rather than a group of its own - a new
# family of differences must be given a name here before the page can say where it belongs.

import argparse
import re
import sys

# The group a key belongs to, by the first words of the key.  Longest prefix first, so
# "share cylinder" is not swallowed by a rule that would match "cylinder".
CIIMAGE_GROUPS = [
    ("shape", ("shape",)),
    ("repr", ("repr",)),
    ("ctx", ("ctx",)),
    ("imp", ("imp",)),
    ("odd set", ("odd set",)),
    ("alg", ("alg", "premul")),
]
MODELIO_GROUPS = [
    ("cube mesh", ("cube mesh",)),
    ("share cylinder", ("share cylinder",)),
    ("cylinder", ("cylinder vertices", "cylinder min")),
    ("voxrule", ("voxrule",)),
    ("voxels after", ("voxels after",)),
    ("voxel extent", ("voxel extent",)),
    ("voxel indices", ("voxel indices",)),
    ("mesh attributes", ("mesh attributes",)),
    ("mesh min", ("mesh min",)),
    ("tri mesh", ("tri mesh", "tribin mesh")),
    ("stack matrix", ("stack matrix",)),
    ("canImport obj", ("canImport obj",)),
]
KEY = re.compile(r'^(.*?)(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)(\s|$)')


def read_differences(path):
    """Every `different:` line compare.py wrote, as (key, host line, port line), in order."""
    out, host, port = [], None, None
    for line in open(path, encoding="utf-8"):
        line = line.rstrip("\n")
        if line.startswith("different: "):
            host = line[len("different: "):]
        elif line.startswith("        the port: "):
            port = line[len("        the port: "):]
            if host is not None:
                m = KEY.match(host)
                out.append((m.group(1) if m else host, host, port))
                host = port = None
    return out


def read_total(path):
    """The `N different` of the run itself, which is what the table has to add up to."""
    for line in open(path, encoding="utf-8"):
        m = re.search(r': (\d+) measurements, (\d+) the same, (\d+) different, (\d+) one side only', line)
        if m:
            return tuple(int(g) for g in m.groups())
    return None


def group_of(key, groups):
    for name, prefixes in groups:
        for prefix in prefixes:
            if key.startswith(prefix):
                return name
    return None


def table(differences, groups, label):
    rows, unattributed = [], []
    for key, host, port in differences:
        name = group_of(key, groups)
        if name is None:
            unattributed.append(key)
        rows.append((name, key, host, port))
    by_group = {}
    for name, key, host, port in rows:
        by_group.setdefault(name, []).append((key, host, port))
    print("### %s: %d groups from %d differences" % (label, len(by_group), len(differences)))
    print()
    print("| group | n | the first key | the system | the port |")
    print("| --- | --- | --- | --- | --- |")
    total = 0
    for name, _ in groups:
        entries = by_group.get(name)
        if not entries:
            print("| `%s` | 0 | - | - | - |" % name)
            continue
        total += len(entries)
        key, host, port = entries[0]
        print("| `%s` | %d | `%s` | %s | %s |" % (name, len(entries), key.strip(),
                                                   host[:70], port[:70]))
    for name in sorted(set(by_group) - set(n for n, _ in groups)):
        print("| `%s` | %d | UNATTRIBUTED - give this key a group in this script | | |" % (name, len(by_group[name])))
    print()
    print("    the table's counts add up to %d" % total)
    if unattributed:
        print("    keys in no group: %d  %s" % (len(unattributed), sorted(set(unattributed))[:5]))
    return total, unattributed


def page_counts(path):
    """Every `| `group` | n |` row of the page, so a stale one can be named."""
    out = {}
    for line in open(path, encoding="utf-8"):
        m = re.match(r'\|\s*`([^`]+)`\s*\|\s*(\d+)\s*\|', line)
        if m:
            out[m.group(1)] = int(m.group(2))
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ci")
    parser.add_argument("modelio")
    parser.add_argument("--page")
    opts = parser.parse_args()

    failed = False
    for path, groups, label, want in ((opts.ci, CIIMAGE_GROUPS, "CoreImage", 40),
                                      (opts.modelio, MODELIO_GROUPS, "ModelIO", 41)):
        total, unattributed = table(read_differences(path), groups, label)
        run = read_total(path)
        if run is None:
            print("    FAIL %s: the run printed no verdict line, so there is nothing to add up to" % label)
            failed = True
            continue
        print("    the run says            %d different, %d measurements, %d the same, %d one side only"
              % (run[2], run[0], run[1], run[3]))
        if total != run[2]:
            print("    FAIL %s: the table adds up to %d and the run has %d different" % (label, total, run[2]))
            failed = True
        if total != want:
            print("    FAIL %s: the table adds up to %d and the page claims %d" % (label, total, want))
            failed = True
        if unattributed:
            print("    FAIL %s: %d difference lines are in no group" % (label, len(unattributed)))
            failed = True
        print()

    if opts.page:
        for path, groups, label in ((opts.ci, CIIMAGE_GROUPS, "CoreImage"),
                                    (opts.modelio, MODELIO_GROUPS, "ModelIO")):
            differences = read_differences(path)
            by_group = {}
            for key, host, port in differences:
                by_group.setdefault(group_of(key, groups) or "UNATTRIBUTED", []).append(key)
            written = page_counts(opts.page)
            for name, entries in sorted(by_group.items()):
                if name == "UNATTRIBUTED":
                    continue
                if name not in written:
                    print("FAIL %s: the page has no row for %r, which holds %d differences"
                          % (label, name, len(entries)))
                    failed = True
                elif written[name] != len(entries):
                    print("FAIL %s: the page says %r is %d and the run has %d"
                          % (label, name, written[name], len(entries)))
                    failed = True
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
