#!/usr/bin/env python3
"""Mutate one of the port's MPMediaItem files, and refuse to write a mutation that changed nothing.

The isPreorder mutant of the 10.3 group came out green once, and the reason was not the port: the
substitution did not match the file, so the "mutant" was the source and the contract passed on it. A
mutation that does not mutate is worse than no mutation, because it is counted as one. So this writes
the mutant, **compares it with the source, and fails if they are the same** - the same `cmp` gate the
other harnesses use - and prints the difference so what was mutated is on the record.

    python3 tests/backports/host/mediaplayeritem/mutate.py <file> <from> <to> <scratch>
    python3 tests/backports/host/mediaplayeritem/mutate.py <file> <from> <to> <scratch>

**A mutation that changes the bytes is not yet a mutant.** Removing an @synthesize
changes the file and leaves ARC synthesising the same property, and a check that
correctly stays green is not a failure of the check - that is how one of these
mutants was nearly reported as a red line here. So the gate above is a `cmp` on
the file, and **it is not enough on its own**: a caller must also show that the
check's verdict moved. There was a `--check` mode that ran the check against the
source tree and against the mutated copy and compared the two verdicts, and it
was dropped rather than shipped half-working - it refused every mutation,
because the run it made of the check could not find the stand-in header, and a
control that refuses everything is worse than none. Until it comes back, the
verdict change is printed by hand:

    # with the mutation, the check must answer differently than it does without
    xcrun clang -fobjc-arc -framework Foundation -I tests/backports/host/mediaplayeritem \
        -I <the tree carrying the mutation> -o .agent-work/runs/mutate/mutant <the check>.m
    .agent-work/runs/mutate/mutant | grep -E "RED|: OK"      # and the same against the source tree
"""
import difflib
import os
import pathlib
import shutil
import sys

LIBRARY = os.path.join("packages", "a", "apple-backports", "MediaPlayer")
GROUPS = ("MPMediaItem70.m", "MPMediaItem80.m", "MPMediaItem92.m", "MPMediaItem100.m", "MPMediaItem103.m")


def verdict(command, directory, tag):
    """Run the check against one tree and return (exit status, its own verdict lines).

    Each run gets its own output path under this worktree's .agent-work/runs, not /tmp and not a shared
    name: one path for both meant the second run clobbered the first's binary, and the baseline the
    comparison is made against was whatever the previous run left there.
    """
    import os as _os
    import subprocess as _subprocess
    # the worktree root, from git, and its own run directory - two levels up from this script is
    # tests/backports/runs, which is neither the worktree's .agent-work nor gitignored.
    top = _subprocess.check_output(["git", "rev-parse", "--show-toplevel"],
                                  text=True, cwd=_os.path.dirname(_os.path.abspath(__file__))).strip()
    runs = _os.path.join(top, ".agent-work", "runs", "mutate")
    _os.makedirs(runs, exist_ok=True)
    out = os.path.join(runs, "check-%s" % tag)
    environment = dict(_os.environ, MUTANT_DIR=directory, MUTANT_OUT=out)
    done = _subprocess.run(["/bin/sh", "-c", command], capture_output=True, text=True, env=environment)
    lines = [line for line in (done.stdout + done.stderr).splitlines() if "RED" in line or ": OK" in line]
    # every line, for a run that produced no verdict at all: a check that crashes says so here, and
    # swallowing its output is what made the first two attempts of this undiagnosable.
    return done.returncode, lines, (done.stdout + done.stderr).splitlines()


def main(argv):
    if len(argv) != 5:
        sys.stderr.write(__doc__)
        return 2
    name, before, after, scratch = argv[1], argv[2], argv[3], argv[4]
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
    source = pathlib.Path(root, LIBRARY, name)
    text = source.read_text()
    if before not in text:
        sys.stderr.write("FAIL: %s does not contain %r, so this is not a mutation of the port's code and "
                         "the contract would have passed on the source\n" % (name, before))
        return 1
    if text.count(before) != 1:
        sys.stderr.write("FAIL: %s contains %r %d times, so a mutation here would not say which getter "
                         "changed\n" % (name, before, text.count(before)))
        return 1
    shutil.rmtree(scratch, ignore_errors=True)
    os.makedirs(scratch)
    for group in GROUPS:
        shutil.copy(os.path.join(root, LIBRARY, group), os.path.join(scratch, group))
    mutant = pathlib.Path(scratch, name)
    mutant.write_text(text.replace(before, after))
    if mutant.read_bytes() == source.read_bytes():
        sys.stderr.write("FAIL: the mutant is byte for byte the source, so nothing was mutated\n")
        return 1
    print("mutated %s: %r -> %r" % (name, before, after))
    for line in difflib.unified_diff(text.splitlines(), mutant.read_text().splitlines(),
                                     fromfile="source/" + name, tofile="mutant/" + name, lineterm="", n=1):
        print("  " + line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
