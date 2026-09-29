#!/usr/bin/env python3
"""Write the mutants the driver needs into the build directory, from the tree's own sources.

Kept as a script rather than as a copy in the run dir so the mutant is derived from the CURRENT port
source every run, and a port change that moves the anchor is a failed run rather than a stale mutant.

    python3 make-mutants.py <build dir>
"""
import os, sys

build = sys.argv[1]
here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(here, "..", "..", "..", "..", "packages", "a", "apple-backports", "Security")
blocks = open(os.path.join(src, "SecProtocolOptionsBlocks13_0.m")).read()
old = """    _challenge = block;
    _challengeQueue = queue;
}"""
new = """    // MUTANT: the challenge block into the KEY UPDATE slot. This must NOT COMPILE.
    _keyUpdate = block;
    _keyUpdateQueue = queue;
}"""
if blocks.count(old) != 1:
    sys.exit("make-mutants: the blocks anchor matched %d times, not once" % blocks.count(old))
open(os.path.join(build, "mutant-blocks-challenge-into-keyupdate.m"), "w").write(blocks.replace(old, new))
print("  mutant blocks-challenge-into-keyupdate.m: the challenge block into the key-update slot")
