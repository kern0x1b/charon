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

REGISTRY = "packages/a/apple-backports/registry/Metal"
FILES = ("ios8render.json", "ios11capturemanager.json")
MARKER = "tool's own list:"


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
    for name in FILES:
        path = os.path.join(REGISTRY, name)
        if not os.path.isfile(path):
            continue
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
    for api, first, second in problems:
        print("  DIFFER %-26s %s%s" % (api, first, ("; " + second) if second else ""))
    verdict = ("check-inert-rows: %d inert row(s) compared, %d differ; every list is the tool's"
               % (compared, len(problems)))
    print(verdict)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
