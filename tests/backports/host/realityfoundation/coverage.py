#!/usr/bin/env python3
"""Which of the registry's implemented rows the host differential actually measures.

The registry's `source` field says what backs a row, and for a long time it said one blanket thing
about all of them, which was false: the review of this series measured it with a grep and found the
differential touching no gesture at all. A blanket is not a source, so every row gets the one that is
true, and this is the script that decides which of the two it is.

The rule, and it is deliberately crude so that it cannot overclaim: a row is *covered* when a check
subject in the differential names the row - its leaf, or the part after the first dot of a member,
with Swift's argument labels stripped. Everything else is `declaration only`: the declaration is
there and the swiftregistry check holds it to a name, and nothing measures its behaviour.

A row can be covered and still not be *well* covered, and the table shows the subject that matched,
so a reader can judge that for themselves rather than take this script's word.

    usage: coverage.py <registry.json>... > coverage.txt
"""
import json
import os
import re
import sys

# The differential whose subjects decide it, and the other suite that measures the SceneKit backports
# rather than these rows.
DIFFERENTIAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "main.swift")

# check("subject", ...) - the first string literal, and the line it is on
SUBJECT = re.compile(r'check\(\s*"((?:[^"\\]|\\.)*)"')


def subjects(path):
    if not os.path.isfile(path):
        return []
    out = []
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        for found in SUBJECT.findall(line):
            out.append((number, found.replace('\\"', '"')))
    return out


def tokens(api):
    """The names a check subject could use for this row."""
    body = api.split(".")[-1]
    body = re.sub(r"\(.*", "", body)          # drop the argument labels: (rawValue), (lhs:rhs:)
    body = re.sub(r"[:].*$", "", body)         # and anything after a colon
    body = body.strip()
    if not body:
        return []
    words = [body]
    if "." in api:                              # a member: try the part after the first dot too
        words.append(api.split(".", 1)[1])
    if body.endswith("()"):                    # a method: its bare name reads better in a subject
        words.append(body[:-2])
    return [w for w in dict.fromkeys(words) if len(w) > 3]


def main(argv):
    if not argv:
        sys.exit("usage: coverage.py <registry.json>...")
    if not os.path.isfile(DIFFERENTIAL):
        sys.exit("coverage.py: no differential at %s" % DIFFERENTIAL)
    checks = subjects(DIFFERENTIAL)
    covered = declaration_only = 0
    for registry in argv:
        entries = [e for e in json.load(open(registry, encoding="utf-8"))["entries"]
                   if e.get("status") == "implemented"]
        print("# %s: %d implemented rows, against %d check subjects in %s"
              % (os.path.basename(registry), len(entries), len(checks), os.path.basename(DIFFERENTIAL)))
        for entry in entries:
            hit = None
            for token in tokens(entry["api"]):
                for number, subject in checks:
                    if token.lower() in subject.lower():
                        hit = (token, number, subject)
                        break
                if hit:
                    break
            if hit:
                covered += 1
                print("covered  %-64s by check at main.swift:%d  %s" % (entry["api"][:64], hit[1], hit[2][:58]))
            else:
                declaration_only += 1
                print("decl only %-64s -" % entry["api"][:64])
        print()
    print("# covered %d, declaration only %d" % (covered, declaration_only))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
