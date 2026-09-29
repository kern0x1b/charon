#!/usr/bin/env python3
"""What a digester dump does not print under the name a ledger row gives it.

Reads a `-dump-sdk` JSON and a `<F>-missing.tsv`, and sorts every row into: printed under another
name, owner not printed at all, member not printed, or a row with no owner (a top-level function or
a macro). `.agent-work/handoffs/2026-09-28-ledger-swift-digester-naming.md` is the writeup, and
`packages/a/appintents/facts/AppIntents/ShapeChecks.md` is the current one.

**The invocation, with the three arguments it needs** -- the dump, the TSV, the module name:

    DIG=$HOME/.xmake/packages/s/swift/6.4.0/f1d0e4f9eebe477396350986a88081e5/bin/swift-api-digester
    RT=$HOME/.xmake/packages/s/swift-runtime/6.4.0/0731ba0aad3e4c26b4fb904a6012cd24
    SDK=$HOME/.xmake/packages/i/iphoneos-sdk/16.4/109415a4ec3443eb8ba96fc960304cbc/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS16.4.sdk
    cd <this worktree>
    mkdir -p .agent-work/runs/classify
    "$DIG" -dump-sdk -module AppIntents -I <the module built for armv7-apple-ios6.1.3> \
        -I "$RT/lib/swift/iphoneos" -Xcc -fmodule-map-file="$RT/lib/swift/shims/module.modulemap" \
        -target armv7-apple-ios6.1.3 -sdk "$SDK" -Xcc -Wno-incompatible-sysroot \
        -o .agent-work/runs/classify/AppIntents.json
    python3 packages/a/appintents/tests/classify-rows.py \
        .agent-work/runs/classify/AppIntents.json            # the dump above
        .agent-work/runs/kits/AppIntents-missing.tsv          # this band's measured missing rows
        AppIntents                                           # the module's name

Run once, as written, on 2026-09-28 (the dump is 5914763 bytes, the TSV is the 261 rows the last
measurement left):

    $ python3 packages/a/appintents/tests/classify-rows.py .agent-work/runs/classify/AppIntents.json \
        .agent-work/runs/kits/AppIntents-missing.tsv AppIntents
    AppIntents {'member not printed': 128, 'bare (macro or top-level function)': 16,
                'digester naming': 97, 'owner not printed': 20} unexplained: 164
        IntentItemSection.Builder
        AppEntity(schema:)
        AppEnum(schema:)
        AppIntent(schema:)
        AssistantEntity(schema:)

The dump is scratch by construction -- it is the toolchain's own output for a module built here -- so
it is written under `.agent-work/runs/` and the command that makes it is in this header, rather than
the file being committed.
"""
import collections, json, os, re, sys

dump, tsv, module = sys.argv[1], sys.argv[2], sys.argv[3]

def walk(node, path=""):
    here = path + node.get("name", "")
    yield here, node
    for child in node.get("children") or []:
        yield from walk(child, here + ".")

printed = collections.defaultdict(set)
for path, node in walk(json.load(open(dump))["ABIRoot"]):
    owner = path.rsplit(".", 1)[0] if "." in path else path
    printed[owner].add(node.get("printedName", ""))

def same(a, b):
    """The five normalisations, each measured: see the handoff."""
    for name, normal in (("init?", lambda s: re.sub(r"init\?\((.*)\)", r"init(\1)", s)),
                         ("==", lambda s: re.sub(r"^==\(.*\)$", "==(_:_:)", s)),
                         ("~=", lambda s: re.sub(r"^~=.*", "~=", s)),
                         ("subscript", lambda s: re.sub(r"^subscript\((.*)\)$",
                                                        lambda m: "subscript(_:)" if ":" in m.group(1) else m.group(0), s)),
                         # a generic initialiser's row carries the type's own generic parameter
                         # list inside its argument list; the digester prints none
                         ("generic list", lambda s: re.sub(r":?<[^()]*>", "", s))):
        if normal(a) == normal(b):
            return name
    return None

buckets = collections.Counter()
unexplained = []
for line in open(tsv):
    if not line.strip():
        continue
    _kind, row, _release = line.rstrip("\n").split("\t")
    if "." not in row:
        buckets["bare (macro or top-level function)"] += 1
        unexplained.append(row)
        continue
    # The owner is the longest prefix the dump has, not everything before the last dot: a generic
    # initialiser's row carries `.<Value.UnwrappedType>` and that dot is the last one in the string.
    # Splitting on it gave an owner no type has, and every such row counted as "owner not printed".
    owner, member, got = None, row, set()
    for cut in [i for i, c in enumerate(row) if c == "."]:
        head, tail = row[:cut], row[cut + 1:]
        if module + "." + head in printed:
            owner, member, got = head, tail, printed[module + "." + head]
            break
    if owner is None:
        owner, member = row.rsplit(".", 1)
        got = printed.get(module + "." + owner, set())
    if not got:
        buckets["owner not printed"] += 1
        unexplained.append(row)
    elif any(same(member, x) for x in got):
        buckets["digester naming"] += 1
    else:
        buckets["member not printed"] += 1
        unexplained.append(row)

print(module, dict(buckets), "unexplained:", len(unexplained))
for row in unexplained:
    print("   ", row)
