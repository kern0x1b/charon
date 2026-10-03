#!/usr/bin/env python3
# emit-intents-constants.py LEDGER VALUES OUTDIR
#
# The Intents extern constants the ledger says the port has to export, one object file per
# release rung, the way the tree already carries the AVFoundation metadata key-spaces
# (AVFoundation/MetadataKeyspacesNN.m).  Read with csv.DictReader and a tab, so no column is
# addressed by its number: the ledger's own header names them and a row that moves a column
# cannot be misread.
#
# Three inputs and what each is for:
#
#   LEDGER  coordination/corpus/ledger/Intents.tsv, rows kind == "constant", status == "missing"
#           and "code" in needs.  83 of them, and every one's reason is the same sentence:
#           "declared extern in the lifted headers and there is no such symbol in the built
#           libraries or the 6.1.3 cache -- the port has to export it".
#   VALUES  the values.json dump-consts wrote: every name looked up in the host's own
#           /System/Library/Frameworks/Intents.framework with dlsym and dereferenced once.  A
#           value is what the host holds, not what a header spells.
#   OUTDIR  packages/a/apple-backports/Intents, where the files are written.
#
# A file is named IntentsConstants<NN>.m for the rung its names first appear in, and it holds
# only that rung: backports.lua's band() raises on an object that mixes a name a band already
# exports with one it does not, and a single-band 6.1.3 gate cannot see that, which is why
# AVFoundation's own key-space objects are split the same way.  A constant whose introduced is
# later than the highest rung this package carries would be a claim no release can answer, and
# the tool refuses it rather than writing it.
#
# The values are facts about the host, so the file says where each came from and the
# differential in tests/backports/host/intents/constants reads the same table out of two builds -
# Apple's Intents on its own, and these files beside it in one binary with the names renamed -
# and diffs them.

import csv
import json
import os
import sys
from collections import defaultdict

HEADER = '''\
#import <Intents/Intents.h>

// %(count)d %(kind)s, the %(rung)s names first exported in that release, and nothing else: a name
// this file does not define is a name the corpus's gate asks for and the link cannot find, so the
// list below is the whole of this file's claim and the registry names each one of them.
//
// Every value was read out of the host's own Intents at runtime - dlsym over
// /System/Library/Frameworks/Intents.framework, the NSString *const dereferenced once - and the
// differential in tests/backports/host/intents/constants reads the same table out of two builds:
// Apple's framework on its own, and this file beside it in one binary with the names renamed.
//
// The object is split by the release each name first appears in, not by a version string:
// backports.lua's band() raises on an object mixing a name a band already exports with one it
// does not, and a single-band 6.1.3 gate cannot see it.  AVFoundation's metadata key-space
// objects are split the same way.
//
// The ledger's reason for every one of these, which is what this slice answers:
// "declared extern in the lifted headers and there is no such symbol in the built libraries or
// the 6.1.3 cache -- the port has to export it".
'''


def rung_of(text):
    return tuple(int(part) for part in text.split("."))


def main():
    ledger, values_path, outdir = sys.argv[1], sys.argv[2], sys.argv[3]
    values = json.load(open(values_path, encoding="utf-8"))

    wanted = [row for row in csv.DictReader(open(ledger, encoding="utf-8"), delimiter="\t")
              if row["kind"] == "constant" and row["status"] == "missing" and "code" in row["needs"]]

    missing = sorted(row["api"] for row in wanted if row["api"] not in values)
    if missing:
        for name in missing:
            print("refusing: %s has no value in the host dump" % name)
        return 1

    by_rung = defaultdict(list)
    for row in wanted:
        by_rung[rung_of(row["introduced"])].append(row)

    written = []
    for rung, rows in sorted(by_rung.items()):
        rows.sort(key=lambda r: r["api"])
        # the file name is the first component of the rung, 10_0 for 10.0, 16_2 for 16.2
        tag = "_".join(str(part) for part in rung)
        name = "IntentsConstants%s.m" % tag
        body = [HEADER % {"count": len(rows), "kind": "constants", "rung": ".".join(str(p) for p in rung)}]
        body.append("")
        for row in rows:
            value = values[row["api"]]
            if "\n" in value or '"' in value:
                print("refusing: the value of %s has a quote or a newline in it: %r" % (row["api"], value))
                return 1
            body.append('NSString *const %s = @"%s";' % (row["api"], value))
        path = os.path.join(outdir, name)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(body) + "\n")
        written.append((name, len(rows), ".".join(str(p) for p in rung)))

    # The MANIFEST. gen-registry.py skips every kind == "constant", on the reasoning that an enum case
    # and its type are the header's own and the compiler writes them into the application. That is true
    # of an enum case and FALSE of these 83: the package DEFINES each one and the 6.1.3 cache has no such
    # symbol, so the port has to export it and the registry has to say so. Without this file a
    # regeneration drops the rows, and the gate that reads the link reports every one of them as
    # "built, but no entry in registry/" - which is what it did.
    #
    # The manifest is this tool's own output rather than a hand-written list, so the names that get a
    # row and the names that got compiled are the same set by construction and cannot drift.
    manifest = {row["api"]: {"introduced": row["introduced"], "rung": ".".join(str(p) for p in rung_of(row["introduced"]))}
                for row in wanted}
    # The manifest is this script's own output and sits beside it. It was written one level above OUTDIR,
    # into registry/Intents, where a registry reader walked it and saw 0 of its rows: the document has no
    # array part, so ipairs(held.entries or held) at modules/apple/backports.lua:1609 makes 0 iterations.
    # OUTDIR is where the .m go and nothing here depends on it any more.
    manifest_dir = os.path.dirname(os.path.abspath(__file__))
    os.makedirs(manifest_dir, exist_ok=True)
    manifest_path = os.path.join(manifest_dir, "constants.json")
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump({"source": "tools/intents/emit-intents-constants.py",
                   "note": "the extern Intents constants this package DEFINES and exports, with the "
                           "release each first appears in; gen-registry.py reads this so a regeneration "
                           "does not drop their rows",
                   "constants": manifest}, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print("  manifest %s (%d names)" % (manifest_path, len(manifest)))

    for name, count, rung in written:
        print("  %-28s %2d constants (first exported in %s)" % (name, count, rung))
    print("  %d files, %d constants" % (len(written), sum(c for _, c, _ in written)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
