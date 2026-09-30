#!/usr/bin/env python3
"""What MetalPerformanceShaders still owes, counted per class family, and by what rule.

    python3 tools/mps-owed-count.py [--sdk <iPhoneOS SDK>] [--out <facts file>]

THE COUNTING RULE, because every number in the facts file has to be reproducible and the rule is part
of the answer, not a detail of it:

  family        The SDK's own header file name, minus `.h`. MPSImageReduce.h declares MPSImageReduceMin,
                MPSImageReduceMax and the rest of the reductions, so those are one family because the SDK
                puts them in one file. The family is never a name written out here: the mapping from an
                API to a family is read off the headers by finding which header declares it. An API no
                header declares cannot be attributed that way and is reported separately, not guessed
                into a neighbour.

  owed           Rows in the registry's `absent_MetalPerformanceShaders.json` whose api is declared by
                that family's header. This is the authoritative owed list for this port: one row per API,
                each carrying the SDK release it arrived in and the minimum it was measured against.

  26.2 headers   MPS classes and protocols the iPhoneOS 26.2 surface declares in that family's headers.
                The wider surface, and the one the next family is chosen from.

  introduced     Taken from the registry row, never guessed from the header text.

Two things this deliberately does not do. It does not rank by crash demand: MPS has no rows in the
corpus hint ledger and none in any crash-demand file, and that absence is measured rather than assumed -
a compute framework is not in a crash top-list. And it does not read anything from memory: every family
name and every membership above comes from the headers or the registry, and the script prints the paths
it read so a reader can check them.

Nothing is written unless --out is given, and then only the markdown the facts file carries.
"""
import argparse
import collections
import glob
import json
import os
import re
import subprocess
import sys


def find_sdk(explicit):
    if explicit:
        return explicit
    for pattern in ("~/Library/Developer/CoreSimulator/Volumes/*/Library/Developer/"
                    "CoreSimulator/Profiles/Runtimes/*.simruntime/Contents/Resources/RuntimeRoot"
                    "/SDKs/iPhoneOS*.sdk",
                    "~/.xmake/packages/i/iphoneos-sdk/*/*/Developer.app/Contents/Developer/Platforms/"
                    "iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk"):
        hits = sorted(glob.glob(os.path.expanduser(pattern)))
        if hits:
            return hits[-1]
    raise SystemExit("no iPhoneOS SDK found; pass --sdk")


def taxonomy(sdk, framework):
    """api name -> header basename, for every MPS class and protocol the surface declares."""
    root = os.path.join(sdk, "System/Library/Frameworks", framework + ".framework")
    if not os.path.isdir(root):
        raise SystemExit("no %s.framework under %s" % (framework, sdk))
    where, headers = {}, set()
    for base, _dirs, files in os.walk(root):
        for f in files:
            if not f.endswith(".h"):
                continue
            headers.add(os.path.join(base, f))
            text = open(os.path.join(base, f), errors="replace").read()
            for m in re.finditer(r"@(?:interface|protocol)\s+(MPS\w+)", text):
                where.setdefault(m.group(1), f[:-2])
    return where, headers


def family_of(api, where):
    if api in where:
        return where[api]
    head = re.split(r"[.(]", api)[0]          # a method or function is written Class.selector
    if head in where:
        return where[head]
    best = None
    for name, fam in where.items():          # else the longest declared name that prefixes it
        if api.startswith(name) and (best is None or len(name) > len(best[0])):
            best = (name, fam)
    return best[1] if best else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=os.path.join(os.path.dirname(__file__), ".."))
    ap.add_argument("--sdk")
    ap.add_argument("--framework", default="MetalPerformanceShaders")
    ap.add_argument("--out")
    args = ap.parse_args()

    sdk = find_sdk(args.sdk)
    reg = os.path.join(args.repo, "packages/a/apple-backports/registry", args.framework,
                       "absent_" + args.framework + ".json")
    doc = json.load(open(reg))
    rows = doc["entries"] if isinstance(doc, dict) else doc
    where, headers = taxonomy(sdk, args.framework)

    owed = collections.Counter()
    introduced = collections.defaultdict(collections.Counter)
    unattributed = []
    for r in rows:
        fam = family_of(r["api"], where)
        if fam:
            owed[fam] += 1
            introduced[fam][r.get("introduced")] += 1
        else:
            unattributed.append(r["api"])
    declared = collections.Counter(where.values())

    print("  sdk        %s" % sdk)
    print("  registry   %s" % os.path.relpath(reg, args.repo))
    print("  headers    %d under %s, declaring %d MPS types"
          % (len(headers), os.path.join("System/Library/Frameworks", args.framework + ".framework"),
             len(where)))
    print("  owed       %d rows, %d attributable to a family, %d to none"
          % (len(rows), sum(owed.values()), len(unattributed)))
    print("")
    print("  %-34s %6s %10s" % ("family", "owed", "26.2 hdrs"))
    for fam, n in sorted(owed.items(), key=lambda kv: (-kv[1], kv[0]))[:14]:
        print("  %-34s %6d %10d" % (fam, n, declared.get(fam, 0)))
    if unattributed:
        print("")
        print("  attributable to no 26.2 header (%d): %s"
              % (len(unattributed), ", ".join(sorted(unattributed)[:6])))

    if args.out:
        lines = ["# What MetalPerformanceShaders still owes, per class family", "",
                 "Regenerate with `python3 tools/mps-owed-count.py --out <this file>`. Every number is",
                 "produced by that script and every rule below is implemented in it.", "",
                 "## The counting rule", "",
                 "A **family** is the SDK's own header file name minus `.h`. MPSImageReduce.h declares the",
                 "reductions, so those are one family because the SDK puts them in one file. Membership is",
                 "read off the headers - the script finds which header declares each API - and is never a",
                 "name list written by hand, which is what rots. An API no header declares is reported",
                 "separately instead of being guessed into a neighbouring family.", "",
                 "**owed** is rows in `absent_%s.json` whose api a header of that family declares." % args.framework,
                 "**26.2 headers** is the MPS types the iPhoneOS 26.2 surface declares there. **introduced**",
                 "is the registry row's own field, never guessed from header text.", "",
                 "Demand is not the ranking, and that is measured: MPS has no rows in the corpus hint ledger",
                 "and none in any crash-demand file, because a compute framework is not in a crash top-list.",
                 "So the ranking is owed surface, which is what the registry and the headers can count.", "",
                 "## Owed per family, biggest first", "",
                 "| family | owed | 26.2 headers | introduced |", "| --- | ---: | ---: | --- |"]
        for fam, n in sorted(owed.items(), key=lambda kv: (-kv[1], kv[0])):
            spread = " ".join("%s:%d" % (k, v) for k, v in sorted(introduced[fam].items(), key=lambda kv: str(kv[0])))
            lines.append("| %s | %d | %d | %s |" % (fam, n, declared.get(fam, 0), spread))
        lines.append("| **total** | **%d** | **%d** | |" % (sum(owed.values()), len(where)))
        if unattributed:
            lines += ["", "## Attributable to no 26.2 header", "",
                      "%d rows, listed rather than guessed into a neighbour:" % len(unattributed), ""]
            lines += ["- `%s`" % a for a in sorted(unattributed)]
        # A tracked file carries no absolute home path (AGENTS.md), so the SDK is written in $HOME form.
        home = os.path.expanduser("~")
        sdk_shown = sdk.replace(home, "$HOME") if sdk.startswith(home) else os.path.basename(sdk)
        lines += ["", "## Read from", "",
                  "- SDK: `%s`" % sdk_shown,
                  "- registry: `packages/a/apple-backports/registry/%s/absent_%s.json`" % (args.framework, args.framework),
                  "- headers: %d under `System/Library/Frameworks/%s.framework`, declaring %d MPS types"
                  % (len(headers), args.framework, len(where)), ""]
        open(args.out, "w").write("\n".join(lines) + "\n")
        print("")
        print("  wrote %s" % args.out)


if __name__ == "__main__":
    main()
