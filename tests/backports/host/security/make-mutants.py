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
    sys.exit("make-mutants: the data anchor matched %d times" % data_src.count(old_pair))
open(os.path.join(build, "mutant-data-halfpair.m"), "w").write(data_src.replace(old_pair, new_pair))
print("  mutant data-halfpair.m: the pair is stored with one half standing in for the other")

held_src = open(os.path.join(src, "SecProtocolOptions13_0.m")).read()
old_block = """    _keyUpdate = block;
    _keyUpdateQueue = queue;"""
new_block = """    // MUTANT: the POINTER is stored, not the block. A stack block is dead when this returns, so calling
    // it later is a silent wrong answer at best.
    _keyUpdate = (__bridge sec_protocol_key_update_t)(__bridge id)block;
    _keyUpdateQueue = queue;"""
if held_src.count(old_block) != 1:
    sys.exit("make-mutants: the held anchor matched %d times" % held_src.count(old_block))
open(os.path.join(build, "mutant-held-nocopy.m"), "w").write(held_src.replace(old_block, new_block))
print("  mutant held-nocopy.m: the block is stored by pointer, so the stack frame it lived in is gone")
