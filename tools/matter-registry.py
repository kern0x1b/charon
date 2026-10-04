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
# The release out of a CLASS's own annotation, whichever of the two macros carries one. They are spelled
# differently and the difference matters: an availability names one release, `MTR_AVAILABLE(ios(16.1), ...)`,
# and a deprecation names a range, `MTR_DEPRECATED("Please use X", ios(16.1, 16.4), ...)`, so the reader
# takes the FIRST number and stops there - the release the declaration is available from, which is the
# question a class row asks. `MTR_PROVISIONALLY_AVAILABLE` is deliberately not in it: it expands to an
# export or to NS_UNAVAILABLE and names no iOS release at all (MTRDefines.h), and the 315 classes the SDK
# annotates that way keep the FALLBACK below, which says so.
CLASS_RELEASE = re.compile(r"(?:MTR_|API_)(?:AVAILABLE|DEPRECATED)\(.*?ios\(([0-9.]+)")


def re_available(line):
    """The iOS release a declaration says it arrived in, or None."""
    found = AVAILABLE.search(line)
    return found.group(1) if found else None


def re_class_available(annotation):
    """The iOS release a CLASS's own annotation states, or None."""
    found = CLASS_RELEASE.search(annotation or "")
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

# The plain data classes get their own prose, for the same reason the two bases do: a row that says
# "a cluster class the release has no framework for at all" of MTRDoorLockClusterSetUserParams names a
# cluster that does not exist, and the row's `effect` claims a two-way member check over a file whose
# members are @synthesize lines and one -copyWithZone:.
REASON_DATA = ("a plain data class of the Matter framework: the release this family is carried into has no"
               " Matter.framework at all, so nothing can be shadowed and the class is carried whole, generated"
               " from the SDK's own payload declarations rather than written by hand")
EFFECT_DATA = ("every property the SDK's own header declares for the class is an ivar of the object's own,"
               " with the header's attribute deciding the setter, and -copyWithZone: is written out over"
               " those ivars so a copy never shares storage with the original. A property the SDK declares in"
               " a CATEGORY of the class keeps its accessors written out by hand over the port's own storage,"
               " because a category cannot hold an ivar")
EFFECT_DATA_EVENT = ("every property the SDK's own header declares for the class is an ivar of the object's"
                     " own, with the header's attribute deciding the setter. The class carries no <NSCopying>"
                     " and has no superclass that does, so it has no -copyWithZone:, which is what the header"
                     " says about it")

# The 60 classes the framework declares as a deprecated SPELLING of another one. Read back out of the emitted
# objects, not from the SDK and not from a list: an object that writes `@dynamic` IS an alias-shaped object,
# and that is the only claim these three rows make. The framework's own @implementation for one of these is
# `@dynamic` and nothing else - no ivar, no accessor, no -init, no -copyWithZone: - so every member lives in
# the superclass's storage and ONE storage serves both names, where a port that gave the alias an ivar per
# member has two and reading a member written through one name through the other reads a different value.
EFFECT_ALIAS_CLASS = ("this class is the DEPRECATED SPELLING of another one - its own header carries"
                      " MTR_DEPRECATED(\"Please use <the other>\") and it is declared as a subclass of it -"
                      " and the object carries the framework's own shape rather than one of its own: no"
                      " storage, no accessor, no -init, no -copyWithZone: and no -description. Every member is"
                      " answered by the class it is a spelling of, so the two names share ONE set of storage,"
                      " which is what writing a member through this class and reading it through that one"
                      " shows. tests/backports/host/matter/params-diff.sh is what measures it")
EFFECT_ALIAS_PROPERTY = ("the property is answered by the class this one is a deprecated spelling of, and the"
                         " storage it reads and writes is that class's: the object declares it @dynamic and"
                         " holds no ivar of its own, so a value written through this name is the value read"
                         " through the other one. Nothing here reaches a fabric")
EFFECT_ALIAS_FORWARDED = ("the superclass does not declare a member of this name, so the object's getter and"
                          " setter are written out and forward to the differently named member of that class"
                          " the framework's own source names - the header's deprecation text says 'Please use"
                          " the storage property' for one of them and prose is not a place to read a member"
                          " name from. The value therefore lives in the superclass's storage and not here,"
                          " which is the framework's own shape. Nothing here reaches a fabric")

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


PROPERTY_LINE = re.compile(r"^@property\s*\(([^)]*)\)\s*(.+);\s*$")
SYNTHESIZED = re.compile(r"^@synthesize\s+(\w+)\s*=\s*_\w+\s*;\s*$")
DYNAMIC = re.compile(r"^@dynamic\s+(\w+)\s*;\s*$")


def properties_of(path):
    """(name, declaration) for every property the emitted object declares, read back out of the emitted text.

    Three spellings, and all of them are in the objects: `@synthesize status = _status;` for a property the
    object holds an ivar for, `@dynamic a;` for a property whose accessor and storage belong to the
    superclass - a deprecated alias class carries the member and declares that it answers with the
    superclass's, so the member IS built and the row exists - and a getter the object writes out by hand
    for a property the SDK declares in a CATEGORY of its class, which a category cannot hold an ivar for. A
    getter is read back out of the emitted declaration, so a row exists for exactly what is built.
    """
    found, lines = {}, None

    for line in open(path):
        stripped = line.lstrip()
        synth = SYNTHESIZED.match(stripped)
        if synth:
            found[synth.group(1)] = ""
            continue
        dynamic = DYNAMIC.match(stripped)
        if dynamic:
            found.setdefault(dynamic.group(1), "")
            continue
        if stripped.startswith("- (") or stripped.startswith("+ ("):
            lines = stripped
        elif lines is not None:
            lines += " " + stripped
        if lines is None:
            continue
        if lines.rstrip().endswith(";") or stripped.rstrip() == "{":
            selector = GENERATE.selector_of(GENERATE.signature(lines))
            lines = None
            if selector and ":" not in selector and not selector.startswith(
                    ("init", "copyWithZone", "set", "get", "is", "has", "will", "did")):
                found.setdefault(selector, "")
    return found


def dynamic_of(path):
    """The members an emitted object declares `@dynamic`, read back out of the emitted text.

    One predicate rather than a shape list: an object that writes `@dynamic` for a member is saying that the
    member is answered by its superclass and that the superclass's storage holds it, and 60 of the 1,068
    objects do. Which of them is a deprecated alias of another class is not decided here - the class's own
    header says that, and the row that says it is the class's row.
    """
    found = set()
    for line in open(path):
        dynamic = DYNAMIC.match(line.lstrip())
        if dynamic:
            found.add(dynamic.group(1))
    return found


def property_declarations_of(block):
    """(name, the property's own declaration) for every @property line in a class's block.

    Joined over several lines before it is read, because the SDK writes
    `@property (nonatomic, copy, nullable)` on one line and the type and the name on the next, and a
    reader that took one line at a time counted 2 properties for
    MTRContentLauncherClusterLauncherResponseParams where there are 3.
    """
    pending = None
    for line in block:
        stripped = line.strip()
        if pending is not None:
            pending = pending + " " + stripped
            if pending.endswith(";"):
                kind, declared, _ = GENERATE.payload_line(PROPERTY_LINE.match(pending).group(2))
                if declared:
                    yield declared, pending
                pending = None
            continue
        if stripped.startswith("@property") and not stripped.endswith(";"):
            pending = stripped
            continue
        if stripped.startswith("@property"):
            kind, declared, _ = GENERATE.payload_line(PROPERTY_LINE.match(stripped).group(2))
            if declared:
                yield declared, stripped


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
    that one line is the class's own statement about when IT arrived. It is read off the JOINED lines and
    at the class's own position there, which are two things this used to get wrong: `lines.index(block[0])`
    searched the RAW lines, which do not contain the head at all for a class the SDK writes with the colon
    on the next line, and it found the FIRST line equal to it anywhere in the header rather than the one
    above this class.

    `releases_of()` reads this FIRST and only falls through to a member's own annotation when it says
    nothing, so the reader is here and not inlined.
    """
    name = GENERATE.interface_head(block[0]).group(1)
    return re_class_available(GENERATE.own_announcement(lines, name))


def releases_of(sdk, cluster):
    """The iOS release each selector of a cluster arrived in, by Apple's own semantic.

    A member with no annotation of its own INHERITS the one on its enclosing declaration, and a member whose
    enclosing declaration carries none inherits the file's: that is what the runtime does, so it is what the
    row must say. Three tiers, taken in order - the member's own annotation, then the @interface, category
    or @protocol it sits in, then a file-level one - and only when none of the three exists does the release
    fall back to the cluster's, which is counted rather than passed off as measured.

    The class's own row takes ITS OWN annotation - the one on the line above its @interface - and the member
    rules above fill in only for the members, never for the class. The two are different questions and the
    order is the whole fix: `MTRCluster.h:40` says `MTR_AVAILABLE(ios(16.1))` above `@interface MTRCluster`
    and the row said 17.4, because the rule used to read the block's FIRST annotated member and the first
    one MTRCluster has is `endpointID` at 17.4 - a member that arrived two releases after the class holding
    it. A member with no annotation of its own now inherits the CLASS's own release rather than the first
    member's, which is the same statement one level up.
    """
    block, header = GENERATE.declaration_of(sdk, cluster)
    if block is None:
        return {}, None, None
    lines = GENERATE.joined_heads(lines_of(os.path.join(sdk, header)))
    # The CLASS's own release, read FIRST and off the line above its own @interface. It is one value and
    # both tiers use it: the class row, and the member that carries no annotation of its own. A member's own
    # annotation still wins for that member, and it is the only thing that can date a class whose own
    # annotation names no release at all - `MTR_PROVISIONALLY_AVAILABLE` is 315 of them.
    first = class_release(lines, block)
    CLASS_TIERS["the annotation above its own @interface" if first
                else "nothing above the @interface names a release"] += 1
    # The file's own level: an annotation on a line before the first @interface applies to everything after.
    file_release = None
    for line in block:
        if GENERATE.INTERFACE.match(line) or line.lstrip().startswith("@protocol"):
            break
        file_release = file_release or re_available(line)
    per_selector, cursor = {}, 0
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
        elif first:
            TIERS["none of the three, and its class's own annotation"] += 1
        else:
            TIERS["none: left to the fallback"] += 1
        # A class whose own annotation names no release is dated by its first annotated member, which is
        # the tier this rule had for EVERY class before the class's own annotation was read first.
        if release and first is None:
            first = release
        selector = GENERATE.selector_of(GENERATE.signature(text))
        if selector and release and selector not in per_selector:
            per_selector[selector] = release
    # The properties, by their own annotation, in the same three tiers and read out of the same block. A
    # property row's release is a property of the property, and most of the plain data classes' properties
    # carry one of their own - 2,230 of the 3,260 the generator synthesizes. A class the SDK declares
    # declares no method at all, so this loop is what dated 923 of the 1,067 objects before the class's own
    # annotation was read at all, and it still dates the classes whose own annotation names no release.
    for declared, text in property_declarations_of(block):
        release = re_available(text)
        if release:
            TIERS["a property's own annotation"] += 1
        elif first is not None:
            release = first
            TIERS["a property with none, taking its class's own annotation"] += 1
        else:
            TIERS["none: a property with none and a class with none"] += 1
        if declared and release and declared not in per_selector:
            per_selector[declared] = release
        if release and first is None:
            first = release
    return per_selector, first, header


def lines_of(path):
    with open(path) as handle:
        return handle.read().splitlines()


def rows_over_base(entries, base):
    """The entries in the order the base file already has them, and what that costs, said by name.

    A registry file is edited BY ROWS and never rewritten: a shared file an export reorders merges today
    only while nobody else has opened it, so the diff becomes hundreds of lines that differ only in
    position, and the real edit is lost in it. This file is written by walking the objects' filenames
    sorted, which is NOT the order the committed Matter file has - the 144 cluster rows were there first
    and the 924 plain data rows were appended under them - so writing the tool's own order over it
    replaced every row in the file and changed nothing but the order.

    So with `--base`, the order is the base's: every row it holds keeps its place, rows this run adds are
    appended in the order the run produced them, and rows the base holds that this run no longer produces
    are DROPPED - a row for an object that is no longer built must go, and the run says which by name
    rather than letting the diff say it. What the run prints is the whole of what a reviewer's `git diff`
    on the file would show, so the two can be compared.

    Every row that keeps its place is still compared, value for value, and a row whose value changed is
    printed by name with what it changed: a reordering that silently rewrote a release would be the same
    defect in a different shape.
    """
    held = json.load(open(base))
    order, kept = {}, []
    for index, entry in enumerate(held["entries"]):
        order.setdefault(entry["api"], index)
    fresh = {entry["api"]: entry for entry in entries}
    moved, renamed = [], []
    for api, index in sorted(order.items(), key=lambda pair: pair[1]):
        entry = fresh.pop(api, None)
        if entry is None:
            renamed.append(api)
            continue
        was = dict(held["entries"][index])
        if was != dict(entry):
            fields = sorted(set(was) | set(entry))
            moved.append((api, "; ".join("%s %r -> %r" % (field, was.get(field), entry.get(field))
                                        for field in fields if was.get(field) != entry.get(field))))
        kept.append(entry)
    appended = [entry for entry in entries if entry["api"] in fresh]
    print("rows over the base %s: %d kept in its order, %d appended, %d dropped" % (base, len(kept),
                                                                                   len(appended),
                                                                                   len(renamed)))
    if moved:
        print("  %d row(s) whose value changed:" % len(moved))
        for api, what in moved:
            print("    %s: %s" % (api, what))
    if renamed:
        print("  %d row(s) the base held that this run does not produce, dropped:" % len(renamed))
        for api in renamed[:20]:
            print("    %s" % api)
        if len(renamed) > 20:
            print("    ... and %d more" % (len(renamed) - 20))
    return kept + appended


def plain_data_classes(sdk):
    """(every payload class of the SDK, the plain data ones among them), read once.

    It is what tells a row apart from a cluster's: the prose beside a row is keyed on the class, and a row
    that calls a payload class a cluster names a cluster that does not exist. The second half is which of
    them has a -copyWithZone: to describe, which is what its own protocol list says.
    """
    families = GENERATE.payload_classes(
        [line for _, block in GENERATE.matter_headers(sdk) for line in block]) if sdk else {}
    return families, set(GENERATE.plain_data_classes(families))


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--objects", help="the directory holding the emitted objects")
    parser.add_argument("--sdk", help="the SDK the headers are read from, for the releases")
    parser.add_argument("--out", help="the registry file to write")
    parser.add_argument("--base", help="the committed registry file this run writes over, so the rows keep"
                                       " their places and the diff is the rows that changed and nothing"
                                       " else; without it the rows come out in the order the objects' file"
                                       " names sort in, which is not the committed order")
    arguments = parser.parse_args()

    # The classes are the objects, one class each: what the generator wrote, read back with the
    # generator's own reader. Four classes had no row because the class list was a list of CLUSTERS and
    # three of them were passed in with --skip on a claim - that they do not build - which stopped being
    # true when the params family was forward-declared, and the fourth is the shared base class, which is
    # not a cluster and so was never on the list at all.
    families, data = plain_data_classes(arguments.sdk)
    copying = {name for name in data if "NSCopying" in families[name]["protocols"]}
    # The classes the SDK declares as a deprecated SPELLING of another one, each read out of its own
    # MTR_DEPRECATED("Please use X") annotation against its own superclass - the same rule the generator
    # emits them under, read from the same place. It is a set of class names and not a shape test because
    # three of the 60 declare no member at all and a fourth writes its accessors out instead of @dynamic:
    # `dynamic_of()` sees nothing in any of the four, and the object alone cannot tell an alias with no
    # members from a plain data class with no members.
    aliases = {name for name in data
               if families[name].get("deprecated_for") == families[name]["super"]}
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
        dynamic = dynamic_of(path)
        alias = cluster in aliases
        if cluster in BASE_ROWS:
            reason, effect = BASE_ROWS[cluster]
        elif cluster in data:
            reason = REASON_DATA
            if alias:
                effect = EFFECT_ALIAS_CLASS
            else:
                effect = EFFECT_DATA if cluster in copying else EFFECT_DATA_EVENT
        else:
            reason, effect = REASON_CLASS, EFFECT_CLASS
        if introduced is None:
            undated.append(cluster)
        if introduced is None:
            fell_back.append(("class", cluster))
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
                    fell_back.append(("method", "%s[%s %s]" % (head, cluster, selector)))
            entries.append(collections.OrderedDict([
                ("api", "%s[%s %s]" % (head, cluster, selector)),
                ("kind", "method"),
                ("introduced", dated or introduced or FALLBACK), ("minimum", "6.0"),
                ("status", "implemented"), ("source", source), ("facts", FACTS),
                ("reason", "a member of a cluster class the release does not have, carried whole"),
                ("effect", "the member answers without reaching a fabric: the value the caller set, or no "
                           "value and the error the release documents for a cluster it cannot reach")]))
            counts["method"] += 1
        for declared in sorted(properties_of(path)):
            dated = releases.get(declared)
            if dated is None:
                undated.append("%s.%s" % (cluster, declared))
                if introduced is None:
                    fell_back.append(("property", "%s.%s" % (cluster, declared)))
            if declared in dynamic:
                what = EFFECT_ALIAS_PROPERTY
            elif alias:
                what = EFFECT_ALIAS_FORWARDED
            else:
                what = ("the property is a readwrite ivar of the object's own, and the header's own"
                        " attribute decides the setter: copy for a copy property, a plain store"
                        " otherwise. Nothing here reaches a fabric")
            entries.append(collections.OrderedDict([
                ("api", "%s.%s" % (cluster, declared)),
                ("kind", "property"),
                ("introduced", dated or introduced or FALLBACK), ("minimum", "6.0"),
                ("status", "implemented"), ("source", source), ("facts", FACTS),
                ("reason", "a property of a class the release does not have, carried whole"),
                ("effect", what)]))
            counts["property"] += 1
    entries = rows_over_base(entries, arguments.base) if arguments.base else entries
    document = collections.OrderedDict([("framework", "Matter"), ("entries", entries)])
    with open(arguments.out, "w") as out:
        out.write(json.dumps(document, indent=2) + "\n")
    print("wrote %s: %d entries (%d class, %d method, %d property) over %d objects, every object one class"
          % (arguments.out, len(entries), counts["class"], counts["method"], counts["property"],
             len(classes)))
    dynamic_total, forwarded_total, empty = 0, 0, 0
    for stem, cluster in classes:
        if cluster not in aliases:
            continue
        built = set(properties_of(os.path.join(arguments.objects, stem)))
        held = dynamic_of(os.path.join(arguments.objects, stem))
        dynamic_total += len(held)
        forwarded_total += len(built - held)
        empty += 1 if not built else 0
    print("  deprecated ALIAS classes the SDK declares - each carries MTR_DEPRECATED naming its own"
          " superclass: %d; %d member(s) their objects declare @dynamic, %d whose accessors they write"
          " out over the superclass's storage, and %d class(es) with no member at all"
          % (len(aliases), dynamic_total, forwarded_total, empty))
    for tier, count in sorted(CLASS_TIERS.items()):
        print("  class row from %s: %d" % (tier, count))
    # Said out loud rather than left as a silent fallback, and the two sets counted apart, because they are
    # two different things: only the rows in the first take a release the header states NOWHERE, while the
    # second inherit one the header does state.
    # Counted by KIND, not by the shape of the name: a property row is `Class.property` and a method row is
    # `+[Class selector]`, and sorting the two by whether the name holds a `[` counted every property row as
    # a class - 2,022 class rows over 1,067 classes in the first run.
    kinds = collections.Counter(kind for kind, _ in fell_back)
    methods_fell = set(name for kind, name in fell_back if kind == "method")
    inherited = [each for each in undated if "[" in each and each not in methods_fell]
    print("  %d row(s) take the %s fallback, which the header states nowhere: %d class, %d method,"
          " %d property"
          % (len(fell_back), FALLBACK, kinds["class"], kinds["method"], kinds["property"]))
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
