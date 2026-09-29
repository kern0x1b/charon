#!/usr/bin/env python3
"""Check that every registry row leaves the bands at the release that has its API.

A row is carried from its `minimum` and drops out at its `maximum`: `in_range` in
modules/apple/backports.lua is `deployment >= minimum and deployment < maximum`. So the last band a row
belongs in is the one before `maximum`, and the band after that is the first in which the release has
the API -- which is `introduced`, the SDK's own availability. A `maximum` below `introduced` therefore
drops the row a band early, and the band it drops it in is the one band where the release does *not*
have the API and the port is the only source of it; and a `maximum` above `introduced` keeps it in a
band the release already answers for itself.

That rule is exact for a member of a class **the release carries**, and this check is blind to the two
other cases the schema allows, so a red here means the row is a release-carried member and a green
does not prove the rest:

- a member of a class **the backports carry** leaves the bands where the *class* stops being the
  port's, not where the member arrived. NSURLSessionTaskTransactionMetrics' two header byte counts
  are the case in the tree: `introduced 13.0` (the 16.4 header's own annotation) and
  `maximum 10.0`, because the release ladder gives the class its first release at 10.0.1. Those two
  rows are correct and this check has nothing to say about them.
- a member of a class the backports carry **and the release lays out itself** may go earlier still:
  registry/README.md allows `maximum` to name the release that took the API away, and
  NSURLSessionStreamTask's `-init`, `+new` and `-stopSecureConnection` sit at `introduced 7.0,
  maximum 7.0` against a class the port carries to 9.0. This check calls them right; whether they
  should be at 9.0 is a question about the class, not about the member.

What this cannot catch, and what does: `introduced` is itself written by hand (registry/README.md:
"the release the SDK's availability gives"), so a row whose `introduced` is one release too low
satisfies this check and hides the API in exactly the band a low `maximum` would. Reading the
availability out of the SDK's own headers is tools/corpus/sdk-introduced.py's walk. The gate does not
catch it either: modules/apple/backports.lua's `ours = in_range(entry, deployment)` gates the
"listed as implemented, but nothing of that name is built" report, so a wrong `maximum` is only
noticed in a band where the row is off, and a wrong `introduced` is noticed by nothing in the tree.

A run that read no row is a run that proved nothing, so a path with no registry under it exits 1 and
says so, rather than reporting zero of zero and passing.

    tools/registry-maximum.py [registry-root]     exit 0 and a count, or exit 1 and the rows
    tools/registry-maximum.py --write-facts F      rewrite F's generated block from this run

The generated block is the only number in a facts file about *this* tree that does not have to be
pasted by hand: `<!-- maximum:begin -->` / `<!-- maximum:end -->` around it, and a
`<!-- maximum -->` line naming what the block is about. A number that says "this tree" and is typed by
a porter is a number that goes stale the next time anything lands, and this has now been the third
defect of that family in this facts area.
"""
import collections
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_REGISTRY = os.path.join(ROOT, "packages/a/apple-backports/registry")
WRITE_FACTS = None
REGISTRY = DEFAULT_REGISTRY
BEGIN = "<!-- maximum:begin -->"
END = "<!-- maximum:end -->"
for argument in sys.argv[1:]:
    if argument == "--write-facts":
        WRITE_FACTS = ""
    elif WRITE_FACTS == "":
        WRITE_FACTS = argument
    elif not argument.startswith("--"):
        REGISTRY = argument


def version(text):
    # dyld.lua's parts() takes every run of digits and its compare() pads the shorter side with
    # zeros, so "8" and "8.0" are one release to the build and a row written either way is not a
    # defect; 10.0 and 10.0.1 stay apart because the third component differs.
    return [int(piece) for piece in re.findall(r"\d+", str(text))]


def same_release(one, other):
    left, right = version(one), version(other)
    for index in range(max(len(left), len(right))):
        if (left[index] if index < len(left) else 0) != (right[index] if index < len(right) else 0):
            return False
    return True


def owner_of(api):
    """The class that owns a member row's api, or None for a row that names no class.

    `NSStream.first` and `-[NSStream open]` both name NSStream; a constant row
    (`NSURLRequestAttributeName`) names none and is left to the plain rule.
    """
    if not isinstance(api, str):
        return None
    method = re.match(r"^[-+]\[(\w+) ", api)
    if method:
        return method.group(1)
    property_name = re.match(r"^(\w+)\.(\w+)$", api)
    return property_name.group(1) if property_name else None


def main():
    rows = 0
    with_maximum = 0
    wrong = []
    by_class = []
    every = []
    for path in sorted(glob.glob(os.path.join(REGISTRY, "**", "*.json"), recursive=True)):
        document = json.load(open(path))
        entries = document["entries"] if isinstance(document, dict) else document
        for entry in entries:
            every.append((entry, os.path.basename(path)))
            rows += 1
    # A class the backports carries is a class whose own row says implemented, whatever file that
    # row is in; a member of one leaves the bands with the class, so the rule below cannot judge
    # it. Those are counted apart, never counted as right: a green run with a large number here is
    # saying "not judged", not "checked".
    carried = {entry.get("api") for entry, _ in every
               if entry.get("kind") == "class" and entry.get("status") == "implemented"}
    for entry, where in every:
        maximum, introduced = entry.get("maximum"), entry.get("introduced")
        if not maximum or not introduced:
            continue
        with_maximum += 1
        owner = owner_of(entry.get("api"))
        if entry.get("kind") != "class" and owner and owner in carried:
            by_class.append((entry.get("api"), owner, maximum))
            continue
        if not same_release(maximum, introduced):
            wrong.append((entry.get("api"), maximum, introduced, where))
    for api, maximum, introduced, where in wrong:
        print("%-64s maximum %-8s introduced %-8s  %s" % (api, maximum, introduced, where))
    if rows == 0:
        print("no registry row under %s: nothing was checked, so nothing is claimed" % REGISTRY)
        return 1
    line = ("%d rows, %d with a maximum, %d not at the release that has the API, "
            "%d members of a class the backports carries this rule does not judge"
            % (rows, with_maximum, len(wrong), len(by_class)))
    print(line)
    if WRITE_FACTS:
        text = open(WRITE_FACTS).read()
        if BEGIN not in text or END not in text:
            raise SystemExit("%s has no %s / %s markers" % (WRITE_FACTS, BEGIN, END))
        if "<!-- maximum -->" not in text:
            raise SystemExit("%s has no <!-- maximum --> line naming what the block is about" % WRITE_FACTS)
        head, _, rest = text.partition(BEGIN)
        _, _, tail = rest.partition(END)
        open(WRITE_FACTS, "w").write(head + BEGIN + "\n```\n" + line + "\n```\n" + END + tail)
        print("rewrote the generated block in %s: %s" % (WRITE_FACTS, line))
    return 1 if wrong else 0


sys.exit(main())
