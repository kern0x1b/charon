#!/usr/bin/env python3
"""check_host.py - the host's own SensorKit against the transcription of what it answered once.

    ./probe /System/Library/Frameworks/SensorKit.framework/SensorKit < classes.txt | python3 check_host.py

Reads expectations.tsv and the probe's output, and prints one line per class: what the host says now
against what it said when the table was written. A difference is not a failure of the port, it is the
oracle having moved - which is the one thing this table exists to notice, because a table that is never
re-read is a table that has stopped being evidence.

Exits non-zero on any difference, and on a class the host no longer declares at all.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LINE = re.compile(r"^CLASS (\S+) own-init=(\d) own-new=(\d) "
                  r"init=(ok \S+|raises \S+ \([^)]*\)) new=(ok \S+|raises \S+ \([^)]*\))$")


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


def main():
    expected = [r for r in rows_of(os.path.join(HERE, "expectations.tsv")) if r["framework"] == "SensorKit"]
    if len(sys.argv) != 2:
        sys.exit("check_host.py: pass the probe's output on stdin")
    found, failures, ok = {}, [], 0
    for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
        line = line.rstrip("\n")
        if line.startswith("NOFRAMEWORK"):
            print("SKIP %s - this host has no SensorKit, so the oracle is not there to ask"
                  % line.split()[1])
            return 0
        match = LINE.match(line)
        if not match:
            failures.append("unparsed probe line: %s" % line)
            continue
        name, own_init, own_new, _, new = match.groups()
        found[name] = (own_init, own_new, new)
    for row in expected:
        name = row["class"]
        if name not in found:
            failures.append("%s: the host does not declare it any more" % name)
            print("%-42s ABSENT on the host" % name)
            continue
        own_init, own_new, new = found[name]
        want_new = ("raises %s (%s)" % (row["exception"], row["reason"])) if row["answer"] == "raises" \
            else None
        same = own_init == row["own-init"] and own_new == row["own-new"] and \
            (new.split(" ", 1)[1] == want_new.split(" ", 1)[1] if want_new else new.startswith("ok"))
        if same:
            ok += 1
            print("%-42s own-init=%s own-new=%s  %s" % (name, own_init, own_new, new.split(" ", 1)[1]))
        else:
            failures.append("%s: the host answers own-init=%s own-new=%s %s, and the table says "
                            "own-init=%s own-new=%s %s" % (name, own_init, own_new, new.split(" ", 1)[1],
                                                           row["own-init"], row["own-new"],
                                                           want_new.split(" ", 1)[1] if want_new else "ok"))
            print("%-42s DIFFERS from the table: %s" % (name, new.split(" ", 1)[1]))
    for name in sorted(set(found) - {r["class"] for r in expected}):
        failures.append("%s is answered by the host and is not in the table" % name)
    for failure in failures:
        print("FAIL " + failure)
    print("sensorkit-init-host: %d of %d classes as the table says, %d failures%s"
          % (ok, len(expected), len(failures), "" if not failures else "  <- SEE FAIL"))
    return 1 if failures else 0


sys.exit(main())
