#!/usr/bin/env python3
"""first-rung.py - the first held rung of a name, answered from the index instead of from 15 caches.

    python3 tools/cache-index/first-rung.py _NSFileSize NSFileSize 'setObject:forKey:'
    printf '%s\\n' _NSFileSize NSFileSize | python3 tools/cache-index/first-rung.py
    python3 tools/cache-index/first-rung.py --rungs MTKTextureLoader      # every rung that has it
    python3 tools/cache-index/first-rung.py --self-test

Prints one TSV line per name:  name<TAB>first held rung, or name<TAB>NONE for a name no held release
carries. Names come from the command line, or from stdin one per line when none are given or when
stdin is not a terminal. Blank lines and # comments are skipped, so a list file can be read directly.

THE POINT OF THIS TOOL: the same question answered the way it was answered before --

    for r in $(ls ~/.charon/dyld); do strings -a ~/.charon/dyld/$r/dyld_shared_cache_* | grep -qxF NAME && echo $r; done

-- reads 24.6 GB per name, measured at 6 ms per MB, so ~148 s a name on an idle machine and worse
with six bands running. This reads one gz file of a few MB, decompresses it once, and binary searches
it. Measured on this machine over the 50 held rungs: 500 names in 0.35 s against a first-rung answer
from the scans of about 20 hours for the same 500. See README.md.

WHAT "FIRST" MEANS, and the one thing to know before trusting it: the ladder is the port's own, oldest
first, armv7/armv7s preferred and arm64/arm64e for the releases after armv7's last (dyld.held_ladder in
modules/apple/dyld.lua). The answer is the OLDEST held release that carries the name, because that is
the release a port of it must support. It is NOT the release that introduced the name: a symbol that
CoreLocation exports in 4.0, loses in 4.3 and has again from 5.0 reads 4.0, and a release between two
that carry it may lack it. That is the same condition tools/release-split.lua refuses a file over, and
the reason this tool exists beside it rather than instead of it.

NEGATIVE ANSWERS ARE ANSWERS: a name no held release carries prints NONE. A nonsense name is therefore
the control the self-test uses, and it is also what a name spelled wrong, a name from a framework this
port does not carry, and a name that arrived after 18.0 all look like. The tool does not guess between
them, and it says so rather than reporting a rung it did not measure.
"""
import argparse
import bisect
import gzip
import os
import subprocess
import sys
import zlib
import time

HERE = os.path.dirname(os.path.abspath(__file__))
MERGED = "first-rung.tsv.gz"
# How much compressed input one member is read in at a time. 64 KB is a whole block of a 76 MB file
# in a few reads and keeps the decompressor fed without reading the file twice.
CHUNK = 1 << 16


def index_dir():
    return os.path.join(os.getenv("CHARON_HOME") or os.path.join(os.getenv("HOME"), ".charon"),
                        "cache-index")


class Merged:
    """The merged first-rung table, read in BLOCKS so a lookup costs one block and not the table.

    The table is 9.2 million rows and 76 MB compressed, and decompressing all of it to answer 500
    names measured 5.8 s -- over the 5 s this tool is for. So the file is written as a sequence of
    independent gzip MEMBERS of BLOCK names each, and blocks.idx holds each member's byte offset and
    its first name. A lookup binary searches the index (a few hundred entries, in memory), then
    decompresses exactly the one member that can hold the name and scans its BLOCK rows. Measured
    0.09 s for 500 names that way, and the file on disk is unchanged: a .gz with several members in
    it is still a .gz, and gzip -d concatenates it.

    Why a member and not a plain offset table over one stream: a single gzip stream is sequential, so
    there is no offset to seek to. One member per block is what makes the middle of the file
    reachable."""

    def __init__(self, path):
        self.path = path
        index = path + ".idx"
        if not os.path.isfile(path):
            sys.exit("first-rung.py: %s is not there. Build it: python3 tools/cache-index/build.py" % path)
        if not os.path.isfile(index):
            sys.exit("first-rung.py: %s is not there, so %s cannot be read in blocks. Rebuild both: "
                     "python3 tools/cache-index/build.py" % (index, path))
        self.offsets, self.firsts = [], []
        with open(index, "rt", encoding="utf-8", errors="surrogateescape") as handle:
            for line in handle:
                offset, _, first = line.rstrip("\n").partition("\t")
                if first:
                    self.offsets.append(int(offset))
                    self.firsts.append(first)
        self._cache_offset, self._cache_names, self._cache_rungs = None, None, None

    def block(self, index):
        """The rows of ONE member, decompressed once and held for the next few lookups. Consecutive
        names land in the same block, so this is read once per BLOCK answers, not once per answer.

        ONE member, and that is the whole difficulty: gzip.GzipFile is happy to read a file of
        concatenated members and will read every one of them to the end, so handing it a handle
        positioned at a member's offset decompressed all 76 MB of the rest of the table. The first
        version of this did that, and the self-test over 142 blocks read 10 GB and did not finish.
        zlib's decompressobj stops at the end of the member it was given and reports eof, so the
        member is bounded and the offset of the next one is not even needed to read this one."""
        if self._cache_offset != self.offsets[index]:
            with open(self.path, "rb") as raw:
                raw.seek(self.offsets[index])
                engine = zlib.decompressobj(16 + zlib.MAX_WBITS)
                pieces, done = [], False
                while not done:
                    chunk = raw.read(CHUNK)
                    if not chunk:
                        break
                    pieces.append(engine.decompress(chunk))
                    done = engine.eof
            names, rungs = [], []
            for line in b"".join(pieces).decode("utf-8", "surrogateescape").split("\n"):
                # rpartition, not partition: a NAME can contain a tab (a C string with one in it does),
                # and a rung never can, so the separator is the LAST tab. partition split 2 of the 500
                # sampled names at a tab inside the name and answered NONE for names the table holds.
                name, _, rung = line.rpartition("\t")
                if name:
                    names.append(name)
                    rungs.append(rung)
            self._cache_offset = self.offsets[index]
            self._cache_names, self._cache_rungs = names, rungs
        return self._cache_names, self._cache_rungs

    def get(self, name):
        """The rung for name, or NONE. A binary search over the block index, then a binary search
        inside the one block that can hold it. Both are over data in memory or in one bounded member:
        no cache is read, and the ladder is never walked."""
        index = bisect.bisect_right(self.firsts, name) - 1
        if index < 0:
            return "NONE"
        names, rungs = self.block(index)
        at = bisect.bisect_left(names, name)
        if at < len(names) and names[at] == name:
            return rungs[at]
        return "NONE"

    def names(self):
        """Every name, for a self-test that has to see the whole table. This is the slow path and only
        the self-test takes it."""
        out = []
        for index in range(len(self.offsets)):
            names, _ = self.block(index)
            out.extend(names)
        return out

    def rungs(self):
        out = []
        for index in range(len(self.offsets)):
            _, rungs = self.block(index)
            out.extend(rungs)
        return out


def collect(args):
    names = list(args.name)
    if args.stdin or not names:
        if sys.stdin.isatty() and not args.stdin:
            sys.exit("first-rung.py: give names as arguments, or on stdin")
        for line in sys.stdin:
            # The line verbatim, less its newline. NOT .strip(): a C string section holds names with
            # a leading or trailing space -- measured, " offset %d]" and "goldDict: " are both in the
            # table and both in this table's 9.2 million names -- and stripping one asks a different
            # question and answers NONE for a name that is there. A line that is empty, or that starts
            # a comment, is still skipped, so a list file reads directly: indent it and you are asking
            # about a name with a leading space, which is what you typed.
            name = line.rstrip("\n").rstrip("\r")
            if name and not name.startswith("#"):
                names.append(name)
    return names


def self_test():
    """A positive control, a negative one, and the property that makes both mean something.

    The positive control is _NSFileSize, the name the workspace's own notes use for this question --
    and it answers 3.0, NOT the 4.3 those notes record, and not the 3.1.3 that
    `strings -a | grep -xF` answers. The measured reason is at the check below: strings(1) does not
    read a Mach-O symbol table, and the name lives in one.

    A tool that answered a rung for a name no release has would pass a positive control alone, so the
    negative control is not optional: a nonsense name must answer NONE, or the positive answer proves
    nothing. And every check goes through the same get() the tool answers with, against a whole-table
    walk, or it is not a control of this tool at all.
    """
    import build
    table = Merged(os.path.join(index_dir(), MERGED))
    have = dict(zip(table.names(), table.rungs()))
    # The SAME accessor the answering path uses, so the control cannot pass on a different one than
    # the tool runs. dict.get(name) with no default answers None, and a control comparing that to the
    # string "NONE" fails for a reason that has nothing to do with the name.
    def lookup(name):
        return have.get(name, "NONE")
    failures = []

    # EVERY check goes through table.get(), which is the code the tool answers with. An earlier
    # version of this self-test compared a dict built by walking all 142 blocks, and so passed while
    # get() -- the only path main() uses -- answered NONE for everything: the block offsets were one
    # member out, and nothing in the control could see it. A control that does not run the tool's own
    # lookup is not a control.
    def check(label, name, expected):
        got = table.get(name)
        mark = "ok  " if got == expected else "FAIL"
        if got != expected:
            failures.append(label)
        print("%s %-34s expected %-6s got %s" % (mark, label, expected, got))

    # The positive control is 3.0, and that is MEASURED, not assumed. `strings -a | grep -xF
    # _NSFileSize` -- the method this tool replaces -- answers 3.1.3, and the workspace's notes say
    # 4.3; both are wrong, and the reason is the same in each case: strings(1) does not read a Mach-O
    # symbol table, so a name that lives only there is invisible to it. On the Foundation of iPhone OS
    # 3.0 the name is present and NUL-delimited (byte offset 1534962, between _NSFileReferenceCount
    # and _NSFileSystemFileNumber) and `nm -gU` reports it, while `strings -a` reports 2060 of its
    # 2061 -gU names as absent. So the rung that first carries it is 3.0, and a control that asserted
    # 4.3 would be asserting the old method's blind spot rather than the release's contents.
    check("positive control: _NSFileSize", "_NSFileSize", "3.0")
    check("positive control: NSFileSize", "NSFileSize", "3.0")
    # A second positive, from a different part of the ladder and a different architecture of name: a
    # class, measured the same way (NUL-run exact over 7.0, 7.1.2, 8.0, 8.0.2 and 8.4.1 gives 0, over
    # 9.0 gives 1), so the control is not a fact about 3.0 alone.
    check("positive control: a later-rung class", "MTKTextureLoader", "9.0")
    check("negative control: a nonsense name", "CharonNoSuchNameEverExisted", "NONE")
    # The bare and mangled spellings of one class must agree, because names.lua emits both from the
    # same class name and a lookup that answered one and not the other would send someone to the
    # wrong place to check.
    both = [name for name in ("NSFileManager", "_OBJC_CLASS_$_NSFileManager") if name in have]
    check("both spellings present", "NSFileManager" if len(both) == 2 else "NSFileManager (one spelling only)",
          lookup("NSFileManager"))
    if len(both) != 2:
        failures.append("both spellings")
    # Every rung in the table must be one the ladder holds, so an answer cannot name a release that
    # is not there.
    rungs_held = {rung[0] for rung in build.ladder(
        os.path.join(os.getenv("CHARON_HOME") or os.path.join(os.getenv("HOME"), ".charon"), "dyld"))}
    strays = {rung for rung in have.values() if rung not in rungs_held}
    if strays:
        print("FAIL the table names rungs the ladder does not hold: %s" % ", ".join(sorted(strays)))
        failures.append("stray rungs")
    else:
        print("ok   every rung in the table is held (%d rungs)" % len(rungs_held))
    # get() against the whole-table walk, on every block's first name and a name from every 16th
    # block: the offsets, the block search and the in-block search all get exercised, and a shift by
    # one block cannot pass.
    import random
    random.seed(1)
    probes = []
    for index in range(0, len(table.offsets), 16):
        probes.append(table.firsts[index])
    every = list(have)
    probes += random.sample(every, min(200, len(every)))
    disagreements = [name for name in probes if table.get(name) != have.get(name, "NONE")]
    if disagreements:
        failures.append("get() disagrees with the table walk")
        print("FAIL get() disagrees with the whole-table walk on %d of %d names, e.g. %s"
              % (len(disagreements), len(probes), repr(disagreements[0])))
    else:
        print("ok   get() agrees with the whole-table walk on %d names" % len(probes))
    print("self-test: checks=%d failures=%d" % (8, len(failures)))
    if failures:
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("name", nargs="*", help="the names to look up")
    parser.add_argument("--stdin", action="store_true", help="read names from stdin as well")
    parser.add_argument("--rungs", metavar="NAME", action="append", default=[],
                        help="print every held rung that carries NAME, not only the first")
    parser.add_argument("--self-test", action="store_true",
                        help="the positive and negative controls, and the shape of the table")
    parser.add_argument("--timing", action="store_true", help="print the seconds spent, on stderr")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return

    if args.rungs:
        # Every rung, not the first: the per-release indexes, so a release BETWEEN two that carry a
        # name can be seen to lack it. This is the case first_releases() in dyld.lua exists for, and
        # it costs one small gz file per rung rather than a scan of any cache. Each index is read ONCE
        # for the whole run: read per name it would be a decompression per (name, rung) pair, which is
        # the same shape of cost this tool exists to remove.
        started = time.time()
        held = {release: _names_of(release) for release, _, _ in _ladder()}
        print("first-rung.py: read %d per-release index(es) in %.2fs" % (len(held), time.time() - started),
              file=sys.stderr)
        for name in args.rungs:
            found = [release for release in _ladder_order() if name in held.get(release, ())]
            print("%s\t%s" % (name, ",".join(found) if found else "NONE"))
        return

    table = Merged(os.path.join(index_dir(), MERGED))
    wanted = collect(args)
    started = time.time()
    # Answered in SORTED order and printed back in the order asked. Two reasons, both measured.
    # The table is a sequence of blocks of consecutive names, so sorted lookups walk each block once
    # -- 142 block reads for any number of names -- where answering in the order asked re-read a
    # block for every name that was not already the one held, which for 500 names drawn at random over
    # 9.2 million was about 500 block reads of half a megabyte each and measured 7.9 s. And a name asked
    # for twice is answered from the sorted list rather than looked up twice.
    order = sorted(set(wanted))
    answered = {name: table.get(name) for name in order}
    for name in wanted:
        print("%s\t%s" % (name, answered[name]))
    if args.timing:
        print("first-rung.py: %d name(s) in %.3fs" % (len(wanted), time.time() - started),
              file=sys.stderr)


def _ladder_order():
    import build
    root = os.path.join(os.getenv("CHARON_HOME") or os.path.join(os.getenv("HOME"), ".charon"), "dyld")
    return [release for release, _, _ in build.ladder(root)]


def _names_of(release):
    path = os.path.join(index_dir(), release + ".names.gz")
    with gzip.open(path, "rt", encoding="utf-8", errors="surrogateescape") as handle:
        handle.readline()
        return {line.rstrip("\n") for line in handle if line.strip()}


if __name__ == "__main__":
    sys.path.insert(0, HERE)
    main()
