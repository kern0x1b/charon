#!/usr/bin/env python3
"""Are the inert rows' selector lists the tool's own, exactly?

    sh tests/backports/host/protocol-conformance.sh        # writes the sweep this compares against
    python3 tests/backports/host/check-inert-rows.py SWEEP.txt

Exits 0 when every inert row's `effect` holds EXACTLY the selectors protocol-conformance.sh measured
for it, and 1 on any difference - a selector the row has and the tool does not, or the other way. The
comparison is SET-EQUAL on the selector strings, split on commas and whitespace, so a colon inside a
selector (`-setObject:atIndexedSubscript:`) survives and a newline in the row does not.

This is a SCRIPT and not something an operator runs by hand, because the three failures it exists to
catch are all silent: a row that lost its list, a row whose list names a selector the class now has,
and a row whose list went stale when the criterion changed. A hand comparison finds none of them by
accident.
"""
import json
import os
import re
import sys

# The repository root from __file__, NOT from the working directory. A relative path here meant that
# run from any other directory compared ZERO rows - and a comparison of zero rows PASSED, printing
# "every list is the tool's", which is a success line for having checked nothing at all.
#
# And the path is packages/A/apple-backports/...: the TIER is part of it, and a version that said
# packages/apple-backports named a directory that does not exist anywhere, so the file list came back
# empty for the same reason.
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
REGISTRY = os.path.join(ROOT, "packages", "a", "apple-backports", "registry", "Metal")
FILES = ("ios8render.json", "ios11capturemanager.json")
MARKER = "tool's own list:"

if not os.path.isdir(REGISTRY):
    raise SystemExit("check-inert-rows: no registry at %s" % REGISTRY)



def tool_lists(sweep):
    """{protocol: [selectors]} from the sweep protocol-conformance.sh printed."""
    out, current = {}, None
    for line in open(sweep):
        matched = re.match(r"^  (MTL\w+)\s+via (\S+)\s+(\S+)", line)
        if matched:
            current = matched.group(1)
            out.setdefault(current, [])
            continue
        if current and "missing:" in line:
            out[current].append(line.split("missing:")[1].strip())
    return out


def row_selectors(effect):
    """{selectors} from a row's effect, after the marker, split on commas and whitespace."""
    if MARKER not in effect:
        return None
    tail = effect.split(MARKER, 1)[1]
    return {token.strip() for token in re.split(r"[,\s]+", tail) if token.strip() and
            token.strip() not in ("and", "these", "are", "NOT", "owed", "from", "the")}


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    sweep = sys.argv[1]
    if not os.path.isfile(sweep):
        print("check-inert-rows: %s is not a file; run protocol-conformance.sh first" % sweep)
        return 2
    measured = tool_lists(sweep)
    compared = 0
    problems = []
    missing = [n for n in FILES if not os.path.isfile(os.path.join(REGISTRY, n))]
    if missing:
        print("FAIL: 0 compared - the registry has no %s under %s" % (", ".join(missing), REGISTRY))
        return 1
    for name in FILES:
        path = os.path.join(REGISTRY, name)
        document = json.load(open(path))
        entries = document["entries"] if isinstance(document, dict) else document
        for entry in entries:
            api = entry.get("api")
            if api not in measured or not measured[api]:
                continue
            compared += 1
            want = set(measured[api])
            got = row_selectors(entry.get("effect", ""))
            if got is None:
                problems.append((api, "the effect carries no tool list at all", sorted(want)[:3]))
            elif got != want:
                problems.append((api, "only in the row: %s" % sorted(got - want)[:3],
                                 "only in the tool: %s" % sorted(want - got)[:3]))
    # ZERO COMPARED IS A FAILURE, and a DIFFERENT COUNT FROM THE SWEEP'S IS A FAILURE: the sweep says
    # how many rows have gaps, and a comparison that reaches fewer of them has silently checked
    # nothing for the rest. This is the defect that made a wrong directory a pass.
    swept = sum(1 for v in measured.values() if v)
    if compared == 0:
        print("FAIL: 0 inert rows compared, from %s" % REGISTRY)
        print("      a comparison of nothing is not a comparison; fix the directory or the registry path")
        return 1
    if compared != swept:
        print("FAIL: the sweep reports %d row(s) with gaps and the registry has %d of them"
              % (swept, compared))
        return 1
    for api, first, second in problems:
        print("  DIFFER %-26s %s%s" % (api, first, ("; " + second) if second else ""))
    verdict = ("check-inert-rows: %d inert row(s) compared from %s, %d differ%s"
               % (compared, os.path.relpath(REGISTRY, ROOT), len(problems),
                  "; every list is the tool's" if not problems else ""))
    print(verdict)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
