#!/usr/bin/env python3
"""Print this package's host-suite counts, and check the facts files against them.

The counts in the facts must come from a run, not from a hand. This runs the suite, reads what it
printed, and reports:

  * the per-suite counts and the total, in the order the runner prints them;
  * **the control**: every number a facts file states for a suite, and whether this run agrees - so a
    stale number cannot survive a green run unnoticed.

    $ python3 tests/backports/host/creematl/suite-counts.py            # run the suite and report
    $ python3 tests/backports/host/createml/suite-counts.py --from-run FILE   # parse a saved run
"""
import re
import subprocess
import sys
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
RUNNER = HERE / "run.sh"
# The runner prints "<n> checks, <m> failures" once per suite, in the order it runs them.
SUITES = ["differential", "tabularframe", "linearmodels", "transformers",
          "metrics", "preprocessing", "l1", "model"]
# The facts that state a count, and what each one is about.
CLAIMED = {
    "packages/a/apple-backports/facts/CreateML/TabularData.md": ("port's own suite", None),
    "packages/a/apple-backports/facts/CoreML/ShapedArray.md": ("the suite", "tabularframe"),
    "packages/a/apple-backports/facts/CreateML/Metrics.md": ("suite", "metrics"),
    "packages/a/apple-backports/facts/CreateML/Preprocessing.md": ("suite", "preprocessing"),
}

COUNT = re.compile(r"\b(\d+) checks, (\d+) failures\b")
NUM = re.compile(r"\*\*(\d+) checks")


def counts_from(text):
    found = COUNT.findall(text)
    return [(int(c), int(f)) for c, f in found]


def run():
    out = subprocess.run([str(RUNNER)], capture_output=True, text=True, cwd=str(HERE)).stdout
    return out


def main():
    text = open(sys.argv[sys.argv.index("--from-run") + 1]).read() if "--from-run" in sys.argv else run()
    got = counts_from(text)
    if not got:
        print("no '<n> checks, <m> failures' lines in the run - the suite did not get that far")
        return 1
    print("per-suite, in the runner's order:")
    for suite, (checks, failures) in zip(SUITES, got):
        print("  %-14s %4d checks, %d failures" % (suite, checks, failures))
    total_checks = sum(c for c, _ in got)
    total_failures = sum(f for _, f in got)
    print("  %-14s %4d checks, %d failures  across %d suites"
          % ("TOTAL", total_checks, total_failures, len(got)))
    per = dict(zip(SUITES, [c for c, _ in got]))

    print()
    print("the control - what the facts claim, against this run:")
    # HERE is <repo>/tests/backports/host/createml, so the root is three parents up.
    root = HERE.parents[3]
    problems = 0
    for rel, (what, suite) in sorted(CLAIMED.items()):
        path = root / rel
        if not path.is_file():
            print("  MISSING  %s" % rel)
            problems += 1
            continue
        for claimed in NUM.findall(path.read_text()):
            n = int(claimed)
            # A file may cite several suites and the total, so a number is stale when the run
            # produced no such number at all - not merely when it is not this file's one suite.
            which = "the total" if n == total_checks else next(
                (s for s, c in per.items() if c == n), None)
            ok = which is not None
            verdict = "agrees (%s)" % which if ok else "STALE - this run produced %s" % (
                sorted(set(list(per.values()) + [total_checks])))
            print("  %-58s claims %-5d (%s)  %s" % (path.name, n, what, verdict))
            if not ok:
                problems += 1
        for stale in ("425 checks", "17 checks"):
            if stale in path.read_text():
                print("  %-58s still contains the string %r" % (path.name, stale))
                problems += 1
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
