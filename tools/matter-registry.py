#!/usr/bin/env python3
"""The registry rows for the Matter clusters, written from the objects the generator emitted.

The rows are not written by hand and not written from the header: they are read back out of the emitted
objects, the same way the other generated families are, because the registry has to describe the objects
that are BUILT and the only thing that knows what those are is the emitted text.

One row per class the objects define and one per method, spelled the way the registry's reader expects:
a class is `MTRBaseClusterIdentify`, an instance method is `-[MTRBaseClusterIdentify selector:]` and a
class method `+[MTRBaseClusterIdentify selector]`.

The classes come from the objects, not from a list of cluster names, and that is the whole fix for four
classes that had no row at all: an object the run wrote and the gate builds needs a row under its own name
or the gate cannot say which release its API arrived in. The three the SDK spells two ways are never
emitted - the generator refuses them from tests/backports/host/matter/excluded.txt - so they are in no
object and need no row, and nothing is skipped here: the generator compiles every object it writes and
fails its run if one does not, so an emitted object that does not build is a run that never reached this
step. A run that finds an object it cannot name exits non-zero rather than writing rows for the rest.
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
# What is named here is what the run checks. The differential against the system framework is NOT: it does
# not build on this host - facts/Matter/Matter.md carries the measurement and the reason - so a row claiming
# its verdict would be a claim nobody made.
EFFECT_CLASS = ("every member the class's own @interface declares has a body in the emitted object, and the"
                " generator's own two-way check holds over the file: every selector the header declares is"
                " in the object, every selector the object defines is in the contract, and each direction has"
                " a planted control. The initializer keeps the device, the endpoint and the queue the caller"
                " gave it in three ivars of its own")
# The two classes the 142 cluster classes sit on, each with its own prose. The name of a row comes from the
# object that implements the class, so the prose beside it is keyed on that name too and not on "is this one
# of the shared bases": the two differ, and one boolean for both gave MTRCluster's row MTRGenericBaseCluster's
# text, which said the port declares MTRCluster - the opposite of the generator's reason for withholding its
# @interface.
REASON_BASE = ("the base class every cluster of this family sits on: the SDK this library compiles against"
               " (16.4) declares MTRCluster and not MTRGenericBaseCluster, so the port declares and"
               " implements it, and a cluster object whose superclass nothing defines does not link")
EFFECT_BASE = ("no member and no state of its own: the SDK declares MTRGenericBaseCluster with an empty"
               " @interface, and each cluster class above it keeps its own device, endpoint and queue in its"
               " own storage")
REASON_SDK_BASE = ("the class below every cluster of this family, which the SDK this library compiles"
                    " against (16.4) DECLARES and the port IMPLEMENTS: the release this family is carried"
                    " into has no Matter.framework at all, so a declaration is a compile-time fact and nothing"
                    " else would define the class - 61 of the 144 objects name _OBJC_CLASS_$_MTRCluster, and"
                    " without it the library does not link. Its header in 16.4 declares -init and +new"
                    " NS_UNAVAILABLE and no member, so that is what its object carries: the class and nothing"
                    " else")
EFFECT_SDK_BASE = ("no member and no state of its own: 16.4's MTRCluster.h declares none, and the one member"
                   " 26.2 adds to the class - endpointID, at 17.4 - is not carried, is owed with the *Params"
                   " family, and is named in facts/Matter/Matter.md. Each cluster class above keeps its own"
                   " device, endpoint and queue in its own storage")
BASE_ROWS = {
    "MTRCluster": (REASON_SDK_BASE, EFFECT_SDK_BASE),
    "MTRGenericBaseCluster": (REASON_BASE, EFFECT_BASE),
}

# What a row says when the SDK names no release for the API it describes. Not a measurement and not
# pretending to be one: the header annotates those declarations with MTR_PROVISIONALLY_AVAILABLE, which
# expands to an export or to NS_UNAVAILABLE and names no iOS release at all (MTRDefines.h), so there is
# nothing to read. It is the value this file already carries for 29 sibling classes of exactly that shape and
# it is above every band that exists. What actually decides the band an object is carried from is
# `minimum`, and that is measured.
#
# The .unannotated sidecar is a SUPERSET of the rows that take it: it lists every declaration the header
# leaves undated, and a method row of those takes its class's release - one the header does state - unless
# the class is undated too. The two sets are counted apart below, because they are two different claims.
FALLBACK = "16.0"


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
CLASS_TIERS = collections.Counter()


def class_release(lines, block):
    """The release the header states for the CLASS itself, read from the line above its @interface.

    Apple writes a class's availability attribute on the line above the @interface and nowhere else, so
    that one line is the class's own statement about when it arrived. It is read only where no member of
    the block carries an annotation, which is the case that has nothing else to read: MTRGenericBaseCluster
    declares no member at all, and the annotation that dates it is on the line above its @interface and
    nowhere in its block. Not a window over the lines above: a window reaches the PREVIOUS class's
    annotation and reads a release this class never had.
    """
    index = lines.index(block[0])
    return re_available(lines[index - 1]) if index else None


def releases_of(sdk, cluster):
    """The iOS release each selector of a cluster arrived in, by Apple's own semantic.

    A member with no annotation of its own INHERITS the one on its enclosing declaration, and a member whose
    enclosing declaration carries none inherits the file's: that is what the runtime does, so it is what the
    row must say. Three tiers, taken in order - the member's own annotation, then the @interface, category
    or @protocol it sits in, then a file-level one - and only when none of the three exists does the release
    fall back to the cluster's, which is counted rather than passed off as measured.

    The class's own row takes the cluster's first annotated member where there is one, and the annotation
    above the @interface where there is none. The header's (block, header) is where both are read from, so
    a class the cluster headers do not declare - the base class, which lives in MTRCluster.h - is dated from
    the header that declares it.
    """
    block, header = GENERATE.declaration_of(sdk, cluster)
    if block is None:
        return {}, None, None
    lines = lines_of(os.path.join(sdk, header))
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
    if first is None:
        first = class_release(lines, block)
        CLASS_TIERS["the annotation above its @interface, no member carries one" if first
                    else "nothing in the header dates it"] += 1
    else:
        CLASS_TIERS["a member's own annotation"] += 1
    return per_selector, first, header


def lines_of(path):
    with open(path) as handle:
        return handle.read().splitlines()


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--objects", help="the directory holding the emitted objects")
    parser.add_argument("--sdk", help="the SDK the headers are read from, for the releases")
    parser.add_argument("--out", help="the registry file to write")
    arguments = parser.parse_args()

    # The classes are the objects, one class each: what the generator wrote, read back with the
    # generator's own reader. Four classes had no row because the class list was a list of CLUSTERS and
    # three of them were passed in with --skip on a claim - that they do not build - which stopped being
    # true when the params family was forward-declared, and the fourth is the shared base class, which is
    # not a cluster and so was never on the list at all.
    emitted = sorted(name for name in os.listdir(arguments.objects) if name.endswith(".m"))
    classes, unnamed = [], []
    for name in emitted:
        found = GENERATE.implemented_class(os.path.join(arguments.objects, name))
        if found is None:
            unnamed.append(name)
        else:
            classes.append((name, found))
    if unnamed:
        print("OBJECTS THAT DO NOT NAME ONE CLASS: %d of %d; no rows written, because a row under a name"
              " the object does not define is a row the gate cannot place" % (len(unnamed), len(emitted)))
        for name in unnamed:
            print("  %s" % name)
        return 1

    entries = []
    counts = collections.Counter()
    undated, fell_back = [], []
    for name, cluster in classes:
        path = os.path.join(arguments.objects, name)
        releases, introduced, header = releases_of(arguments.sdk, cluster)
        source = SOURCE % (os.path.basename(header) if header else "MTRBaseClusters.h")
        reason, effect = BASE_ROWS.get(cluster, (REASON_CLASS, EFFECT_CLASS))
        if introduced is None:
            fell_back.append(cluster)
            undated.append(cluster)
        entries.append(collections.OrderedDict([
            ("api", cluster), ("kind", "class"),
            ("introduced", introduced or FALLBACK), ("minimum", "6.0"),
            ("status", "implemented"), ("source", source), ("facts", FACTS),
            ("reason", reason), ("effect", effect)]))
        counts["class"] += 1
        for head, text in methods_of(path):
            selector = selector_of(text)
            if not selector:
                continue
            # The port's OWN members are not the framework's API and get no row: the storage table and the
            # error a member with no node answers with are ours, named in the generator's PORT_OWNED.
            if selector in GENERATE.PORT_OWNED:
                continue
            dated = releases.get(selector)
            if dated is None:
                # Two different things, counted apart: a method the header dates nowhere takes FALLBACK
                # when its class is dated nowhere either, and its CLASS's release - which the header does
                # state - when it is not.
                undated.append("%s[%s %s]" % (head, cluster, selector))
                if introduced is None:
                    fell_back.append("%s[%s %s]" % (head, cluster, selector))
            entries.append(collections.OrderedDict([
                ("api", "%s[%s %s]" % (head, cluster, selector)),
                ("kind", "method"),
                ("introduced", dated or introduced or FALLBACK), ("minimum", "6.0"),
                ("status", "implemented"), ("source", source), ("facts", FACTS),
                ("reason", "a member of a cluster class the release does not have, carried whole"),
                ("effect", "the member answers without reaching a fabric: the value the caller set, or no "
                           "value and the error the release documents for a cluster it cannot reach")]))
            counts["method"] += 1
    document = collections.OrderedDict([("framework", "Matter"), ("entries", entries)])
    with open(arguments.out, "w") as out:
        out.write(json.dumps(document, indent=2) + "\n")
    print("wrote %s: %d entries (%d class, %d method) over %d objects, every object one class"
          % (arguments.out, len(entries), counts["class"], counts["method"], len(classes)))
    for tier, count in sorted(CLASS_TIERS.items()):
        print("  class row from %s: %d" % (tier, count))
    # Said out loud rather than left as a silent fallback, and the two sets counted apart, because they are
    # two different things: only the rows in the first take a release the header states NOWHERE, while the
    # second inherit one the header does state.
    classes_fell = [each for each in fell_back if "[" not in each]
    methods_fell = [each for each in fell_back if "[" in each]
    inherited = [each for each in undated if "[" in each and each not in set(methods_fell)]
    print("  %d row(s) take the %s fallback, which the header states nowhere: %d class, %d method"
          % (len(fell_back), FALLBACK, len(classes_fell), len(methods_fell)))
    print("  %d further method row(s) carry no annotation of their own and take their class's release, which"
          " the header does state" % len(inherited))
    if undated:
        with open(arguments.out + ".unannotated", "w") as out:
            for api in undated:
                out.write(api + "\n")
        print("  every declaration the header leaves undated is listed in %s.unannotated: %d of them, a bare"
              " class name for a class row and the row's own spelling for a method row"
              % (arguments.out, len(undated)))
    else:
        print("  the header dates every declaration: nothing is listed in %s.unannotated" % arguments.out)
    # The invariant the gate checks and this file used to be able to break quietly: a built class with no
    # row is what "neither the SDK, the registry nor a held release's own cache says which iOS release X
    # arrived in" is made of.
    listed = {entry["api"] for entry in entries if entry["kind"] == "class"}
    defined = {cluster for _, cluster in classes}
    if defined - listed or listed - defined:
        print("INVARIANT FAILED: %d class(es) an object defines with no row, %d row(s) for a class no object"
              " defines" % (len(defined - listed), len(listed - defined)))
        return 1
    print("every class an emitted object defines has a row: %d of %d" % (len(defined), len(defined)))
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
