#!/usr/bin/env python3
"""selftest-registry-absent.sh: the writer of a facts file's count block, checked the way a reader
would be misled if it were wrong.

    tools/selftest-registry-absent.sh            exit 0 and a line per case, or exit 1 and the failures

The reason this exists, measured: `--write-facts` took the framework from a marker line in the file
and only refused a framework the walk had never heard of. A framework that is in the walk with **no
absent rows** passed, and a marker planted to say `FileProvider` - which has 21 implemented rows and
none absent - got a block reading `FileProvider 0 absent ... 21 implemented` and exit 0. That is the
outcome this file's own comment calls worse than no block, and nothing in the tool noticed it.

So the cases are the five ways a generated block can be wrong or useless, and each is checked on both
what the tool printed and whether it rewrote the file:

  1. the right framework, asked for and marked: exit 0, the block written, and the block is the line
     the table mode prints - a block that disagrees with the tool's own table is its own drift;
  2. a planted marker naming a framework with no absent rows, asked for by its own name: refused,
     and the file untouched;
  3. a marker that disagrees with the argument: refused, and the file untouched;
  4. a file with no markers: refused;
  5. a registry path with no rows: the counting refusal, not a zero.

Each case writes its facts file into a scratch directory of its own and never into the tree.
"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "registry-absent.py")
ROOT = os.path.dirname(HERE)
# The scratch is inside this worktree and not the system temp path: the owner's rule, and a test that
# writes outside the tree is a test whose leftovers nobody sweeps.
SCRATCH = os.path.join(ROOT, ".agent-work", "selftest-registry-absent")

failures = []


def run(arguments, cwd=ROOT):
    return subprocess.run([sys.executable, TOOL] + arguments, capture_output=True, text=True, cwd=cwd)


def check(name, condition, detail=""):
    if condition:
        print("ok   %s" % name)
        return
    print("FAIL %s  %s" % (name, detail))
    failures.append(name)


def facts_file(directory, marker):
    path = os.path.join(directory, "facts.md")
    with open(path, "w") as f:
        f.write("<!-- framework: %s -->\n" % marker)
        f.write("<!-- count:begin -->\n```\nstale\n```\n<!-- count:end -->\n")
    return path


def block_of(path):
    text = open(path).read()
    head, _, rest = text.partition("<!-- count:begin -->")
    _, _, tail = rest.partition("<!-- count:end -->")
    return (head + "<!-- count:begin -->" + tail, text)


def main():
    if os.path.exists(SCRATCH):
        shutil.rmtree(SCRATCH)
    os.makedirs(SCRATCH)
    scratch = SCRATCH
    try:
        # 1. the right framework, asked for and marked
        path = facts_file(scratch, "Foundation")
        result = run(["--write-facts", path, "Foundation"])
        _, text = block_of(path)
        table = run([]).stdout.strip().splitlines()[-1]
        check("the marked framework is written",
              result.returncode == 0 and table in text, result.stderr.strip() or result.stdout.strip())
        check("the block is the tool's own table line", table in text, table)

        # 2. a marker naming a framework the walk knows but that has no absent rows
        path = facts_file(scratch, "FileProvider")
        result = run(["--write-facts", path, "FileProvider"])
        untouched, text = block_of(path)
        said = result.stderr + result.stdout
        check("a framework with no absent row is refused",
              result.returncode != 0 and "stale" in text and "no absent" in said,
              "exit %d, said: %s" % (result.returncode, said.strip()[:110]))

        # 3. a marker that disagrees with the argument
        path = facts_file(scratch, "FileProvider")
        result = run(["--write-facts", path, "Foundation"])
        _, text = block_of(path)
        said = result.stderr + result.stdout
        check("a marker that disagrees with the argument is refused",
              result.returncode != 0 and "stale" in text and "same framework" in said,
              "exit %d, said: %s" % (result.returncode, said.strip()[:110]))

        # 3b. and the framework is required at all
        path = facts_file(scratch, "Foundation")
        result = run(["--write-facts", path])
        _, text = block_of(path)
        said = result.stderr + result.stdout
        check("a writer with no framework named is refused",
              result.returncode != 0 and "stale" in text and "second argument" in said,
              "exit %d, said: %s" % (result.returncode, said.strip()[:110]))

        # 4. a file with no markers
        bare = os.path.join(scratch, "bare.md")
        open(bare, "w").write("# a facts file with nothing to fill\n")
        result = run(["--write-facts", bare, "Foundation"])
        said = result.stderr + result.stdout
        check("a file with no markers is refused",
              result.returncode != 0 and "markers" in said, "exit %d, said: %s" % (result.returncode, said.strip()[:110]))

        # 5. a registry path with no rows
        empty = os.path.join(scratch, "no-registry")
        os.makedirs(empty, exist_ok=True)
        result = run([empty])
        said = result.stdout + result.stderr
        check("a registry with no rows is refused, not counted as zero",
              result.returncode != 0 and "nothing was counted" in said,
              "exit %d, said: %s" % (result.returncode, said.strip()[:110]))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    print("%d checks, %d failures" % (7, len(failures)))
    if failures:
        raise SystemExit(1)


main()
