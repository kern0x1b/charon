#!/usr/bin/env python3
"""Write the mutants the driver needs into the build directory, from the tree's own sources.

Kept as a script rather than as a copy in the run dir so the mutant is derived from the CURRENT port
source every run, and a port change that moves the anchor is a failed run rather than a stale mutant.

    python3 make-mutants.py <build dir>
"""
import os, sys

build = sys.argv[1]
os.makedirs(build, exist_ok=True)
here = os.path.dirname(os.path.abspath(__file__))
src = os.path.join(here, "..", "..", "..", "..", "packages", "a", "apple-backports", "Security")
WRITTEN = []

def wrote(name, text):
    """Write a mutant AND REMEMBER IT, so a later failure can take back what this run put on disk. A
    failed run that leaves earlier mutants behind is how a stale one got built between two of my runs and
    was reported as NOT BUILT for a reason that had nothing to do with the script."""
    open(os.path.join(build, name), "w").write(text)
    WRITTEN.append(os.path.join(build, name))

def fail(message):
    for path in WRITTEN:
        if os.path.exists(path):
            os.remove(path)
    sys.exit(message)
# A MISSING ANCHOR IS A NON-ZERO EXIT AND NO MUTANT FILES. The script used to exit on the first bad
# anchor while the driver ran on with 2>/dev/null || true, so a mutant that was never written was
# reported by the driver as "refused by the compiler" - which reads as a PASS.
blocks = open(os.path.join(src, "SecProtocolOptionsBlocks13_0.m")).read()
old = """    _challenge = block;
    _challengeQueue = queue;
}"""
new = """    // MUTANT: the challenge block into the KEY UPDATE slot. This must NOT COMPILE.
    _keyUpdate = block;
    _keyUpdateQueue = queue;
}"""
if blocks.count(old) != 1:
    fail("make-mutants: FAILED - the blocks anchor matched %d times, not once" % blocks.count(old))
wrote("mutant-blocks-challenge-into-keyupdate.m", blocks.replace(old, new))
print("  mutant blocks-challenge-into-keyupdate.m: the challenge block into the key-update slot")

# Two more mutants, for the two cases whose crash was the whole point of F3. Without setvbuf their output
# was lost at the segfault and the comparator said the rows "did not measure" - naming a truncated buffer
# instead of the crash - so the case now dies WITH its last assertion printed.
data_src = open(os.path.join(src, "SecProtocolOptionsData13_0.m")).read()
old_pair = """    if (!psk || !identity)
        return;
    // appended TOGETHER, so the two halves cannot fall out of step"""
new_pair = """    // MUTANT: the pair is stored with only ONE half. A key without an identity names nothing, and the
    // reader is handed a whole that is not whole.
    if (!psk)
        return;
    if (!identity)
        identity = psk;
    // appended TOGETHER, so the two halves cannot fall out of step"""
if data_src.count(old_pair) != 1:
    fail("make-mutants: FAILED - the data anchor matched %d times, not once" % data_src.count(old_pair))
wrote("mutant-data-halfpair.m", data_src.replace(old_pair, new_pair))
print("  mutant data-halfpair.m: the pair is stored with one half standing in for the other")

# ARC COPIES A BLOCK ON ASSIGNMENT TO A __strong IVAR, so changing the ASSIGNMENT removes nothing: the
# qualifier is what copies. The one edit that removes the copy is the STORAGE. The anchor below is the
# ivar declaration VERBATIM, indentation included - the two earlier anchors did not match and the script
# exited, which is why this one is pasted from the file rather than typed.
held_src = open(os.path.join(src, "SecProtocolOptions13_0.m")).read()
old_block = """    __strong sec_protocol_pre_shared_key_selection_t _pskSelection;"""
new_block = """    __unsafe_unretained sec_protocol_pre_shared_key_selection_t _pskSelection;   // MUTANT: not strong,
    // so assigning the block CANNOT copy it. A stack block is dead when the setter returns, and the
    // block-survives-dead-frame row is what should catch this: either it crashes or it reads garbage."""
if held_src.count(old_block) != 1:
    fail("make-mutants: FAILED - the held anchor matched %d times, not once" % held_src.count(old_block))
wrote("mutant-held-nocopy.m", held_src.replace(old_block, new_block))
print("  mutant held-nocopy.m: the block is stored by pointer, so the stack frame it lived in is gone")
