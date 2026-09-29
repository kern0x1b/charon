#!/usr/bin/env python3
"""Check that every file the README cites matches the digest the README states for it.

    python3 check-digests.py

The paths the README cites are written from the repository root, and the README is read from this
script's own directory, so the two are resolved from __file__ and not from the working directory:
run from here, from the repository root or from anywhere else, and the result is the same. The first
version resolved both from the process's working directory, so the invocation in this docstring - the
one a reader copies out of it - died with FileNotFoundError from this very directory.

EXITING 0 IS THE WHOLE POINT, and a check that finds nothing to check must NOT exit 0: an earlier
version printed "NO DIGEST LINES" and returned success, so a tree with no digests at all passed the
check that exists to catch a README out of step with its files. Four ways this FAILS on purpose:

  * the README carries no digest lines            -> exit 1
  * fewer digest lines than files cited           -> exit 1
  * any file whose sha256 does not match          -> exit 1
  * the README or a cited file cannot be read     -> exit 1

The cited files are read out of the README's own shasum block, so the check and the thing being checked
cannot disagree about what is cited.
"""
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# four levels up: this directory is tests/backports/host/security
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(HERE))))
README = os.path.join(HERE, "README.md")

if not os.path.isfile(README):
    print("FAIL  %s does not exist - there is no README to check" % README)
    sys.exit(1)

text = open(README).read()
pairs = re.findall(r'^\s+([0-9a-f]{64})\s+(\S+)$', text, re.M)
if not pairs:
    print("NO DIGEST LINES in %s - the README cites nothing, so there is nothing to check" % README)
    print("and that is a FAILURE, not a pass: this script exists to catch a README out of step with its files")
    sys.exit(1)

# the command block names the files the digests are for; the two must be the same set
# ONLY INSIDE A CODE FENCE. The prose also contains the words "shasum -a 256" - a sentence about how the
# block was computed - and a regex that starts there captures every path mentioned until the next fence,
# including this script's own name. The command block is what the digests are for, so only a fenced one
# counts.
fenced = re.findall(r'```(.*?)```', text, re.S)
cited = [b for b in fenced if 'shasum -a 256' in b]
wanted = re.findall(r'(\S+\.(?:m|py|c|h))', ' '.join(cited)) if cited else []
if wanted:
    missing = [w for w in wanted if w not in [p for _, p in pairs]]
    if missing:
        print("FAIL  %d of the %d files the command block cites carry no digest: %s"
              % (len(missing), len(wanted), ", ".join(missing)))
        sys.exit(1)
    print("the command block cites %d file(s) and %d carry a digest" % (len(wanted), len(pairs)))

bad = 0
for digest, path in pairs:
    try:
        actual = hashlib.sha256(open(os.path.join(ROOT, path), 'rb').read()).hexdigest()
    except OSError as exc:
        print("FAIL  %s cannot be read: %s" % (path, exc))
        bad += 1
        continue
    if actual == digest:
        print("OK       %s" % path)
    else:
        print("MISMATCH %s  README %s  actual %s" % (path, digest, actual))
        bad += 1
print("%d file(s) checked, %d mismatch" % (len(pairs), bad))
sys.exit(1 if bad else 0)
