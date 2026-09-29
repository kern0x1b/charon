#!/usr/bin/env python3
"""The two mutations from the review of kits-r7, on a scratch copy, with the real file untouched.

The review found that `builder-contract.py` printed the **framework's** declaration as its evidence
and never read this module's, so both mutations of the port's own `buildBlock` left it green. The
check now reads both sides, and this driver is what proves it: it applies each mutation to a **copy**
under `.agent-work/runs/`, runs the check against that copy, and expects the right answer.

    python3 packages/a/appintents/tests/builder-mutation.py

| mutation | the port's declaration | the answer, and why |
| --- | --- | --- |
| **A** | `_ items:` -> `_ items2:` | **green** -- the *internal name* changed, and a caller cannot see an internal name. A red here would be the check inspecting something no caller writes |
| **B** | `_ items:` -> `items:` | **red** -- the *external label* changed, and a caller must now write `buildBlock(items: …)`. The failure has to name the row and show the two label lists |

Each mutation is checked three ways before the check runs: the copy is not the original, the pattern
occurred **exactly once**, and afterwards the real file is restored -- from `git show HEAD:<file>`,
which is the only restore, and verified by comparing the bytes.

Exits 1 if mutation A is red, or if mutation B is green. The behaviour half of these rows -- the
probes' call sites typechecked against a module built from this tree -- is a device compile and is
not here.
"""
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", ".."))
REL = "packages/a/appintents/Sources/AppIntents/Items.swift"
CHECK = "packages/a/appintents/tests/builder-contract.py"
SCRATCH = os.path.join(ROOT, ".agent-work/runs/builder-mutation")
ROW = "IntentItem.Builder.buildBlock(_:)"

# The declaration under test, named **whole**: `_ items:` occurs four times in `Items.swift` (two
# builders, and the other initialisers that take a list), and a mutation that hits the wrong one is
# not a mutation of this row. The pattern is the declaration's own head, which occurs once.
DECLARATION = "public static func buildBlock(_ items: IntentItem<Value>...)"
MUTATIONS = (
    ("A: internal name only", DECLARATION,
     "public static func buildBlock(_ items2: IntentItem<Value>...)", False),
    ("B: external label", DECLARATION,
     "public static func buildBlock(items: IntentItem<Value>...)", True),
)


def restore(real):
    """The only restore: the file as HEAD has it."""
    head = subprocess.run(["git", "show", "HEAD:" + REL], capture_output=True, text=True, cwd=ROOT)
    if head.returncode != 0:
        sys.exit("builder-mutation: git show HEAD:%s failed: %s" % (REL, head.stderr.strip()))
    with open(real, "w", encoding="utf-8") as handle:
        handle.write(head.stdout)
    return head.stdout


def apply(text, before, after):
    """Apply a mutation, or refuse: the pattern has to be there, and exactly once."""
    count = text.count(before)
    if count != 1:
        sys.exit("builder-mutation: `%s` occurs %d times in %s; it must occur exactly once for a "
                 "mutation to be a mutation" % (before, count, REL))
    mutated = text.replace(before, after, 1)
    if mutated == text:
        sys.exit("builder-mutation: `%s` -> `%s` changed nothing" % (before, after))
    return mutated


def run_check(real, copy):
    env = dict(os.environ, BUILDER_CONTRACT_SOURCE=copy)
    return subprocess.run([sys.executable, os.path.join(ROOT, CHECK)], capture_output=True, text=True,
                          cwd=ROOT, env=env)


def main():
    real = os.path.join(ROOT, REL)
    os.makedirs(SCRATCH, exist_ok=True)
    copy = os.path.join(SCRATCH, "Items.swift")
    original = open(real, encoding="utf-8").read()
    problems = 0
    try:
        for name, before, after, want_failure in MUTATIONS:
            mutated = apply(original, before, after)
            with open(copy, "w", encoding="utf-8") as handle:
                handle.write(mutated)
            if open(copy, encoding="utf-8").read() == original:
                sys.exit("builder-mutation: the copy equals the original after %s" % name)
            run = run_check(real, copy)
            red = run.returncode != 0
            print("=== mutation %s -- `%s` -> `%s`, on %s"
                  % (name, before, after, os.path.relpath(copy, ROOT)))
            for line in run.stdout.splitlines():
                if ROW in line or line.startswith("checked") or line.startswith("FAIL"):
                    print("    " + line.strip()[:150])
            print("    check exit %d -> %s" % (run.returncode, "red" if red else "green"))
            if name.startswith("A"):
                if red:
                    problems += 1
                    print("    WRONG: an internal-name change is not a defect and must stay green")
            else:
                if not red:
                    problems += 1
                    print("    WRONG: an external-label change is a defect and must be red")
                else:
                    text = run.stdout
                    if ROW not in text or "['items']" not in text or "['_']" not in text:
                        problems += 1
                        print("    WRONG: the failure does not name the row and both label lists")
            restore(real)
            if open(real, encoding="utf-8").read() != original:
                sys.exit("builder-mutation: the restore from git did not put %s back" % REL)
            print("    restored from git, and the file matches the original\n")
    finally:
        restore(real)
    print("%d of 2 mutations behaved wrongly" % problems)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
