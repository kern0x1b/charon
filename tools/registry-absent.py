#!/usr/bin/env python3
"""Count the registry's rows by status, per framework, and name the ones that are still absent.

    tools/registry-absent.py [registry-root]     a table, and the absent rows; exit 1 if no row
    tools/registry-absent.py --list Foundation    api/kind/introduced for that framework's absent rows
    tools/registry-absent.py --write-facts F NAME  rewrite F's generated count block for NAME

The count a report quotes has to come from a run somebody can repeat, and "131 absent Foundation
rows, 116 remain" does not: it was read off a corpus export of an older tip, and the export's
framework column is empty for every file whose JSON carries no `framework` key, so counting by
framework there silently drops rows. This counts the registry files themselves, by path, which is
where a framework's rows live.

A path with no registry under it prints nothing and says so, and exits 1: a count that examined
nothing is not a count.
"""
import collections
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_REGISTRY = os.path.join(ROOT, "packages/a/apple-backports/registry")

# The three ways in, so that one walk answers all of them: the table, the list a host probe reads, and
# the generated block of a facts file. A number that comes from anywhere else is a number that drifts,
# which has now happened three times in this facts area.
MODE = "table"
REGISTRY = DEFAULT_REGISTRY
LIST_FRAMEWORK = None
WRITE_FACTS = None
WRITE_FRAMEWORK = None
BEGIN = "<!-- count:begin -->"
END = "<!-- count:end -->"
for argument in sys.argv[1:]:
    if argument == "--list":
        MODE = "list"
    elif argument == "--write-facts":
        MODE = "write"
    elif argument.startswith("--"):
        raise SystemExit("unknown option %s" % argument)
    elif MODE == "table":
        REGISTRY = argument
    elif MODE == "list":
        LIST_FRAMEWORK = argument
    elif WRITE_FACTS is None:
        WRITE_FACTS = argument
    else:
        WRITE_FRAMEWORK = argument


def framework_of(path):
    # registry/<Framework>.json and registry/<Framework>/<part>.json are the two shapes the
    # registry's own README gives; the key inside the file is not consulted, because five files
    # under registry/AVFoundation/ name AVFAudio and the path is what a reader counts.
    relative = os.path.relpath(path, REGISTRY)
    head = relative.split(os.sep)[0]
    return head[:-len(".json")] if head.endswith(".json") else head


def walk():
    """Every row, by framework, with the absent ones kept whole."""
    by_framework = collections.Counter()
    absent = collections.defaultdict(list)
    rows = 0
    for path in sorted(glob.glob(os.path.join(REGISTRY, "**", "*.json"), recursive=True)):
        document = json.load(open(path))
        entries = document["entries"] if isinstance(document, dict) else document
        framework = framework_of(path)
        for entry in entries:
            rows += 1
            by_framework[(framework, entry.get("status"))] += 1
            if entry.get("status") == "absent":
                absent[framework].append((entry.get("api"), entry.get("kind"), entry.get("introduced")))
    return by_framework, absent, rows


def main():
    by_framework, absent, rows = walk()
    if rows == 0:
        print("no registry row under %s: nothing was counted, so nothing is claimed" % REGISTRY)
        return 1
    if MODE == "list":
        if LIST_FRAMEWORK not in absent and LIST_FRAMEWORK not in {f for f, _ in by_framework}:
            print("no row for %s under %s" % (LIST_FRAMEWORK, REGISTRY))
            return 1
        for api, kind, introduced in absent.get(LIST_FRAMEWORK, []):
            print("%s\t%s\t%s" % (api, kind or "", introduced or ""))
        print("# %d absent %s rows" % (len(absent.get(LIST_FRAMEWORK, [])), LIST_FRAMEWORK), file=sys.stderr)
        return 0
    if MODE == "write":
        if not WRITE_FACTS:
            raise SystemExit("--write-facts needs the path of the facts file to rewrite")
        if not WRITE_FRAMEWORK:
            raise SystemExit(
                "--write-facts needs the framework the block is about, as a second argument: a writer "
                "that takes it from the file alone rewrites a block about whatever name that file "
                "mentions")
        text = open(WRITE_FACTS).read()
        if BEGIN not in text or END not in text:
            raise SystemExit("%s has no %s / %s markers" % (WRITE_FACTS, BEGIN, END))
        # The framework the file is about, named next to the markers AND named on the command line,
        # and the two have to agree. Guessing it from the text picks the wrong one the moment the
        # file mentions another framework, and a block about the wrong framework is worse than no
        # block: a planted marker naming FileProvider wrote "0 absent" there and exited 0.
        framework = None
        for line in text.splitlines():
            if line.strip().startswith("<!-- framework:"):
                framework = line.split(":", 1)[1].split("-->")[0].strip()
                break
        if framework is None:
            raise SystemExit("%s has no <!-- framework: NAME --> line next to the markers" % WRITE_FACTS)
        if framework != WRITE_FRAMEWORK:
            raise SystemExit(
                "%s is marked as about %s and was asked about %s: the marker and the argument have "
                "to name the same framework" % (WRITE_FACTS, framework, WRITE_FRAMEWORK))
        if framework not in {f for f, _ in by_framework}:
            raise SystemExit("%s is about %s, which this walk did not count" % (WRITE_FACTS, framework))
        # A block whose whole content is "0 absent" says nothing and reads like a count, so a
        # framework with no absent rows is refused rather than written.
        if not absent.get(framework):
            raise SystemExit(
                "%s has no absent row: a block saying 0 absent is not a count, so nothing is "
                "written" % framework)
        statuses = sorted({status for _, status in by_framework})
        line = "%s   %s   %s   (%d rows, %d absent, over %d frameworks)" % (
            framework,
            "   ".join("%d %s" % (by_framework.get((framework, status), 0), status) for status in statuses),
            "", rows, sum(len(v) for v in absent.values()), len({f for f, _ in by_framework}))
        block = "%s\n```\n%s\n```\n%s" % (BEGIN, line, END)
        head, _, rest = text.partition(BEGIN)
        _, _, tail = rest.partition(END)
        open(WRITE_FACTS, "w").write(head + block + tail)
        print("rewrote the generated count in %s: %s" % (WRITE_FACTS, line))
        return 0
    frameworks = sorted({framework for framework, _ in by_framework})
    statuses = sorted({status for _, status in by_framework})
    print("%-26s %s %8s" % ("framework", " ".join("%-11s" % s for s in statuses), "absent"))
    for framework in frameworks:
        counts = [by_framework.get((framework, status), 0) for status in statuses]
        print("%-26s %s %8d" % (framework, " ".join("%-11d" % c for c in counts), len(absent[framework])))
    print("%d rows, %d absent, over %d frameworks"
          % (rows, sum(len(v) for v in absent.values()), len(frameworks)))
    return 0


sys.exit(main())
