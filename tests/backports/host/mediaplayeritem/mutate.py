#!/usr/bin/env python3
"""Mutate one of the port's MPMediaItem files, and refuse to write a mutation that changed nothing.

The isPreorder mutant of the 10.3 group came out green once, and the reason was not the port: the
substitution did not match the file, so the "mutant" was the source and the contract passed on it. A
mutation that does not mutate is worse than no mutation, because it is counted as one. So this writes
the mutant, **compares it with the source, and fails if they are the same** - the same `cmp` gate the
other harnesses use - and prints the difference so what was mutated is on the record.

    python3 tests/backports/host/mediaplayeritem/mutate.py <file> <from> <to> <scratch>
"""
import difflib
import os
import pathlib
import shutil
import sys

LIBRARY = os.path.join("packages", "a", "apple-backports", "MediaPlayer")
GROUPS = ("MPMediaItem70.m", "MPMediaItem80.m", "MPMediaItem92.m", "MPMediaItem100.m", "MPMediaItem103.m")


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
