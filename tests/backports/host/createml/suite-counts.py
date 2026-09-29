#!/usr/bin/env python3
"""Print this package's host-suite counts, and check every facts file that quotes one.

    $ python3 tests/backports/host/createml/suite-counts.py
    $ python3 tests/backports/host/createml/suite-counts.py --from-run FILE

The control is the point. It does not take a list of files - it **scans the facts tree for every file
that quotes a suite figure**, so a file it was not told about cannot be missed. The earlier version did
take a list, and it had two holes that the review found: it named `facts/CreateML/Preprocessing.md`
where the file is `facts/CreateMLComponents/Preprocessing.md` - the same basename in a different
directory, so the check passed on the wrong file - and it never listed
`facts/TabularData/Columns.md` at all. A hand-typed list cannot catch either, and a scan can catch both.

A number is judged against **every** number the run produced, per suite and the total, so a file may
cite several suites. The exit status is the check: 0 when every quoted figure is one this run produced,
1 otherwise.
"""
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[3]                      # <repo>/tests/backports/host/createml -> <repo>
FACTS = ROOT / "packages/a/apple-backports/facts"
SUITES = ["differential", "tabularframe", "linearmodels", "transformers",
          "metrics", "preprocessing", "l1", "model"]
COUNT = re.compile(r"\b(\d+) checks, (\d+) failures\b")
# A figure a facts file quotes: "**89 checks**" or "17 checks" in prose.
FIGURE = re.compile(r"(\d+)\s+checks?\b")


def run():
    return subprocess.run([str(HERE / "run.sh")], capture_output=True, text=True, cwd=str(HERE)).stdout


def in_scope(path):
    """Is this facts file about *this* package?

    Derived from the file's own text - it must mention `createml` or `CreateML` - and not from a list of
    paths. The scan has to be wide enough that a file nobody remembered is still in scope: the two the
    earlier version missed were `facts/CreateMLComponents/Preprocessing.md` and
    `facts/TabularData/Columns.md`, and both mention this package. A scan with no scope at all is also
    wrong, because every other package's facts quote their **own** suite's figures, and those are not
    stale - they belong to a different run.
    """
    text = path.read_text(errors="replace")
    return ("createml" in text or "CreateML" in text) and FIGURE.search(text) is not None


def fact_files():
    """Every in-scope facts file that quotes a figure - found by scanning, never by a list."""
    return sorted(p for p in FACTS.rglob("*.md") if in_scope(p))


def main():
    text = open(sys.argv[sys.argv.index("--from-run") + 1]).read() if "--from-run" in sys.argv else run()
    got = [(int(c), int(f)) for c, f in COUNT.findall(text)]
    if not got:
        print("no '<n> checks, <m> failures' lines in the run - the suite did not get that far")
        return 1
    per = dict(zip(SUITES, [c for c, _ in got]))
    total = sum(c for c, _ in got)
    print("per-suite, in the runner's order:")
    for suite, (c, f) in zip(SUITES, got):
        print("  %-14s %4d checks, %d failures" % (suite, c, f))
    print("  %-14s %4d checks, %d failures  across %d suites" % ("TOTAL", total, sum(f for _, f in got), len(got)))

    print()
    print("the control - every facts file that quotes a figure, found by scanning the tree:")
    produced = sorted(set(list(per.values()) + [total]))
    problems = 0
    for path in fact_files():
        rel = path.relative_to(ROOT).as_posix()
        body = path.read_text(errors="replace")
        # **A number this run produced is not enough.** 86 is the metrics suite's figure and it is also
        # what `facts/TabularData/Columns.md` quotes about the *frame* suite, so judging against every
        # produced number passes a figure that is real and mislabelled. A file that names one suite must
        # quote that suite's figure or the total - that is the control per file class.
        # A suite is named by its **path** - `host/createml/<suite>` - which is how a facts
        # file cites one. A bare word is not enough: "model" and "l1" appear in ordinary prose,
        # and matching them would put a file in the wrong class and hide a mislabelled figure.
        named = [s for s in SUITES if "host/createml/" + s in body]
        allowed = set()
        if len(named) == 1:
            allowed = {per[named[0]], total}
            label = named[0]
        else:
            allowed = set(produced)
            label = "any suite"
        for m in FIGURE.finditer(body):
            n = int(m.group(1))
            if n in allowed:
                which = "the total" if n == total and n not in [per[s] for s in named] \
                    else next((s for s in named if per[s] == n), "another suite's")
                print("  %-62s claims %-5d  agrees (%s)" % (rel, n, which))
            else:
                print("  %-62s claims %-5d  STALE for %s - it may quote %s"
                      % (rel, n, label, sorted(allowed)))
                problems += 1
    print()
    print("  %d facts file(s) quote a figure; %d stale" % (len(fact_files()), problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
