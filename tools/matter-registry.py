#!/usr/bin/env python3
"""The registry rows for the Matter clusters, written from the objects the generator emitted.

The rows are not written by hand and not written from the header: they are read back out of the emitted
objects, the same way the other generated families are, because the registry has to describe the objects
that are BUILT and the only thing that knows what those are is the emitted text.

One row per class the objects define and one per method, spelled the way the registry's reader expects:
a class is `MTRBaseClusterIdentify`, an instance method is `-[MTRBaseClusterIdentify selector:]` and a
class method `+[MTRBaseClusterIdentify selector]`.

A cluster that is not compared gets no row: a row for an object the check never looked at is a claim
nobody made. The three the SDK spells two ways are excluded before this runs, and the three that do not
build are passed in with --skip, because they are OWED, not absent, and an `absent` row would say the port
does not carry something it has not been given yet.
"""
import argparse
import collections
import re
import json
import os

import importlib.util

_spec = importlib.util.spec_from_file_location(
    "matter_generate", os.path.join(os.path.dirname(os.path.abspath(__file__)), "matter-generate.py"))
GENERATE = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(GENERATE)

AVAILABLE = re.compile(r"MTR_AVAILABLE\(\s*ios\(([0-9.]+)\)")


def re_available(line):
    """The iOS release a declaration says it arrived in, or None."""
    found = AVAILABLE.search(line)
    return found.group(1) if found else None


FACTS = "facts/Matter/Matter.md"
SOURCE = ("SDK 26.2, iPhoneOS26.2.sdk, System/Library/Frameworks/Matter.framework/Headers/%s, "
          "read for arm64 and carried from the armv7 release caches (tools/corpus/built-exports.py)")
REASON_CLASS = ("a cluster class the release has no framework for at all: iOS 6.1.3 has no Matter.framework,"
                " so nothing can be shadowed and the class is carried whole, generated from the SDK's own"
                " declarations rather than written by hand")
EFFECT_CLASS = ("every member the header declares for this class has a body in the emitted object, and the"
                " differential over the class reports its member set identical to the system framework's")


def methods_of(path):
    """(kind, selector) for every method the emitted object defines, read back out of the emitted text.

    Read from the OBJECTS and not from the header, so a row exists for exactly what is built. The read is
    a declaration per line up to the lone `{` under it, which is the shape the generator writes.
    """
    first, parts = None, []
    for line in open(path):
        stripped = line.lstrip()
        if first is None:
            if not (stripped.startswith("- (") or stripped.startswith("+ (")):
                continue
            first = stripped[0]
            parts = [stripped]
        else:
            parts.append(stripped)
        if line.rstrip().endswith(";") or line.strip() == "{":
            text = " ".join(parts)
            parts = []
            head = first
            first = None
            yield head, text


def selector_of(declaration):
    """The selector of an emitted declaration, from the generator's OWN parser.

    Reused, not rewritten: matter-generate.py has a parser for exactly this with a self-test over four
    declarations, and the first version of this file grew a second one that got `initWithDevice:endpointID:
    queue:` wrong - a selector that splits at depth-zero colons sees the colons inside a parameter's type as
    selector parts. One parser, tested once.
    """
    return GENERATE.selector_of(GENERATE.signature(declaration))


TIERS = collections.Counter()


def releases_of(sdk, cluster):
    """The iOS release each selector of a cluster arrived in, by Apple's own semantic.

    A member with no annotation of its own INHERITS the one on its enclosing declaration, and a member whose
    enclosing declaration carries none inherits the file's: that is what the runtime does, so it is what the
    row must say. Three tiers, taken in order - the member's own annotation, then the @interface, category
    or @protocol it sits in, then a file-level one - and only when none of the three exists does the release
    fall back to the cluster's, which is counted rather than passed off as measured.
    """
    headers = os.path.join(sdk, "System/Library/Frameworks/Matter.framework/Headers")
    block, _ = GENERATE.cluster_block(lines_of(os.path.join(headers, "MTRBaseClusters.h")), cluster)
    if block is None:
        return {}, None
    # The file's own level: an annotation on a line before the first @interface applies to everything after.
    file_release = None
    for line in block:
        if GENERATE.INTERFACE.match(line) or line.lstrip().startswith("@protocol"):
            break
        file_release = file_release or re_available(line)
    per_selector, first, cursor = {}, None, 0
    for first_line, text in GENERATE.declarations(block):
        try:
            index = block.index(first_line, cursor)
        except ValueError:
            index = cursor
        cursor = index + 1
        # The enclosing declaration: the last @interface, category or @protocol at or before this member.
        enclosing = None
        for earlier in reversed(block[:index + 1]):
            stripped = earlier.lstrip()
            if stripped.startswith("@interface") or stripped.startswith("@protocol"):
                enclosing = re_available(earlier)
                break
        own = re_available(text)
        release = own or enclosing or file_release
        if own:
            TIERS["the member's own annotation"] += 1
        elif enclosing:
            TIERS["the enclosing @interface, category or @protocol"] += 1
        elif file_release:
            TIERS["a file-level annotation"] += 1
        else:
            TIERS["none: left to the cluster"] += 1
        if release and first is None:
            first = release
        selector = GENERATE.selector_of(GENERATE.signature(text))
        if selector and release and selector not in per_selector:
            per_selector[selector] = release
    return per_selector, first


def lines_of(path):
    with open(path) as handle:
        return handle.read().splitlines()


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--objects", help="the directory holding the emitted objects")
    parser.add_argument("--clusters", help="clusters-emitted.txt: the clusters the generator wrote")
    parser.add_argument("--skip", nargs="*", default=[], help="clusters the differential did not compare")
    parser.add_argument("--sdk", help="the SDK the headers are read from, for the releases")
    parser.add_argument("--emitted-files", help="a name=file list the generator wrote, so a row names the FILE that holds the class")
    parser.add_argument("--out", help="the registry file to write")
    arguments = parser.parse_args()

    with open(arguments.clusters) as handle:
        clusters = [line.strip() for line in handle if line.strip()]
    skipped = set(arguments.skip)
    entries = []
    counts = collections.Counter()
    fell_back = []
    for cluster in clusters:
        if cluster in skipped:
            continue
        path = os.path.join(arguments.objects, files.get(cluster, "CharonMatter%s.m" % cluster))
        releases, introduced = releases_of(arguments.sdk, cluster)
        source = SOURCE % "MTRBaseClusters.h"
        entries.append(collections.OrderedDict([
            ("api", cluster), ("kind", "class"),
            ("introduced", introduced or "16.0"), ("minimum", "6.0"),
            ("status", "implemented"), ("source", source), ("facts", FACTS),
            ("reason", REASON_CLASS), ("effect", EFFECT_CLASS)]))
        counts["class"] += 1
        for head, text in methods_of(path):
            selector = selector_of(text)
            if not selector:
                continue
            # The port's OWN members are not the framework's API and get no row: the storage table and the
            # error a member with no node answers with are ours, named in the generator's PORT_OWNED.
            if selector in GENERATE.PORT_OWNED:
                continue
            if selector not in releases:
                fell_back.append("%s[%s %s]" % (head, cluster, selector))
            entries.append(collections.OrderedDict([
                ("api", "%s[%s %s]" % (head, cluster, selector)),
                ("kind", "method"),
                ("introduced", releases.get(selector) or introduced or "16.0"), ("minimum", "6.0"),
                ("status", "implemented"), ("source", source), ("facts", FACTS),
                ("reason", "a member of a cluster class the release does not have, carried whole"),
                ("effect", "the member answers without reaching a fabric: the value the caller set, or no "
                           "value and the error the release documents for a cluster it cannot reach")]))
            counts["method"] += 1
    document = collections.OrderedDict([("framework", "Matter"), ("entries", entries)])
    with open(arguments.out, "w") as out:
        out.write(json.dumps(document, indent=2) + "\n")
    print("wrote %s: %d entries (%d class, %d method) over %d clusters; %d skipped as owed"
          % (arguments.out, len(entries), counts["class"], counts["method"],
             len(clusters) - len(skipped), len(skipped)))
    # Said out loud rather than left as a silent fallback: a declaration the header carries no availability
    # annotation for takes the cluster's own first release, which is an assumption and not a measurement.
    print("  %d method row(s) took the cluster's first release because the header annotates none for that"
          " selector" % len(fell_back))
    if fell_back:
        with open(arguments.out + ".unannotated", "w") as out:
            for api in fell_back:
                out.write(api + "\n")
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
