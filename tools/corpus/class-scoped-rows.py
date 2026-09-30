#!/usr/bin/env python3
"""class-scoped-rows.py - does the OWNER CLASS of each registry row answer that member on a release?

    python3 tools/corpus/class-scoped-rows.py <queue-or-rows.tsv> <label=inventory.tsv> [...]
    python3 tools/corpus/class-scoped-rows.py --inventory <release> [<release> ...] -- <queue.tsv>

The inventory is one `objc-inventory.lua` run per release:

    CHARON_ROOT=<worktree> xmake l tools/corpus/objc-inventory.lua ~/.charon/dyld/<r>/dyld_shared_cache_<arch> \
        > <label>.tsv

Its lines are `class<TAB>name<TAB>super<TAB>image<TAB>instance<TAB>class<TAB>protocols` and
`protocol<TAB>name<TAB><TAB><TAB>instance<TAB>class`. `modules/apple/objc.lua`'s `method_list` prefixes
EVERY selector it reads with `-`, in both tables, so which table a row needs is chosen by the row's own
sign and the prefix is this script's to strip — which is what `backports.lua`'s `carried_by_release` does
too, and which is why both agree.

## Why a first rung cannot answer this, twice measured on 2026-09-30

`fileSystemRepresentation` reads first-rung 3.0, because some OTHER class has a selector of that name,
while `-[NSURL fileSystemRepresentation]` is `API_AVAILABLE(ios(7.0))` at NSURL.h:118. `init` reads 3.0,
which is NSObject's. A name's first rung answers PRESENCE OF A NAME. A member row asks whether one class
has one selector, so this looks the member up in the OWNER's line and nowhere else, and a class it cannot
find is reported as `NO CLASS` rather than as an absence.

## And why the own table is not the class

The inventory holds one class's own methods and its categories, not the superclass chain, so an own-table
read calls `-[AVCompositionTrack associatedTracksOfType:]` absent on a release that answers it from
AVAssetTrack — measured here: ABSENT on 6.1.3, INHERITED on 7.0 and 7.1. "The class answers it" and "the
class declares it" are different claims and the second one is not the question, so the chain is walked and
the two verdicts are told apart.

## Verdicts

| verdict | meaning |
| --- | --- |
| `CARRIED` | the owner class answers it from its own table |
| `INHERITED` | the owner class answers it only through a superclass |
| `ABSENT` | the owner class and its whole chain are there and none answers it |
| `NO CLASS` | the owner class itself is not in this release, so the member cannot be asked |
| `NO PROTOCOL` | a protocol row whose protocol this release does not have |
| `NO PROTOCOL MEMBER` | the protocol is there and does not declare it; an `@protocol A <B>` chain is not walked, so this is a refusal, not an absence |

## The controls, and why they are in the run

A run that read nothing answers `ABSENT` for every row, and `ABSENT` is a verdict a wrong reader produces
happily. So every release is asked three things it must answer, and a run where any of them is wrong
prints `CONTROL FAILED` and writes no row:

| control | wanted | what a wrong reader would say |
| --- | --- | --- |
| `-[AVPlayerItem duration]` | `CARRIED` | `ABSENT` — the class tables were read from the wrong place |
| `-[AVPlayerItem aSelectorNoFrameworkHas]` | `ABSENT` | `CARRIED` — the table was read as one bag of names |
| `-[AVCompositionTrack mediaType]` | `INHERITED` | `ABSENT` — the own table was taken for the class |
"""
import collections
import os
import sys

CARRIED, INHERITED = "CARRIED", "INHERITED"
ABSENT, NO_CLASS, NO_PROTOCOL, NO_PROTOCOL_MEMBER = "ABSENT", "NO CLASS", "NO PROTOCOL", "NO PROTOCOL MEMBER"

CONTROLS = (("-[AVPlayerItem duration]", "method", CARRIED),
            ("-[AVPlayerItem aSelectorNoFrameworkHas]", "method", ABSENT),
            ("-[AVCompositionTrack mediaType]", "method", INHERITED))


def load(path):
    """One objc-inventory.lua dump: the classes, the protocols, and each class's own two selector tables."""
    classes, protocols = {}, {}
    for line in open(path):
        line = line.rstrip("\n")
        if not line:
            continue
        f = line.split("\t")
        if f[0] == "class":
            classes[f[1]] = {"super": f[2], "image": f[3], "instance": set(f[4].split(",")),
                             "class": set(f[5].split(",")), "protocols": set(f[6].split(","))}
        elif f[0] == "protocol":
            protocols[f[1]] = {"instance": set(f[4].split(",")), "class": set(f[5].split(","))}
    if not classes:
        raise SystemExit("FAIL %s holds no class line: the reader read nothing, so no row below is evidence" % path)
    return classes, protocols


def owner_and_member(api, kind):
    """The owner class and what the row asks of it, or (None, None) when the spelling names no owner."""
    if kind in ("class", "protocol"):
        return api, None
    if kind == "method":
        sign, rest = api[0], api[2:]
        if not rest.endswith("]"):
            return None, None
        owner, _, selector = rest[:-1].partition(" ")
        if not owner or not selector:
            return None, None
        return owner, ("class" if sign == "+" else "instance", selector)
    if kind == "property":
        if "." not in api:
            return None, None
        owner, _, name = api.partition(".")
        return owner, ("property", name)
    return None, None


def spellings(member):
    """The selectors a member may be spelled as: its own name, and for a property its accessor pair.

    The `is` form is an answer on purpose and not a guess: the SDK decides it with the `getter=`
    attribute, and `AVCaptureDeviceFormat.videoBinned` is one - 7.0 answers it as `-isVideoBinned`, which
    is measured, not assumed.
    """
    if member[0] == "property":
        name = member[1]
        upper = name[0].upper() + name[1:]
        return {"-" + name, "-set" + upper + ":", "-is" + upper}
    return {"-" + member[1]}


def chain(classes, owner):
    """The owner and its superclasses to the root, with a guard against a cycle in a malformed dump."""
    seen, out = set(), []
    while owner and owner in classes and owner not in seen:
        seen.add(owner)
        out.append(owner)
        owner = classes[owner]["super"]
    return out


def ask(classes, protocols, api, kind):
    owner, member = owner_and_member(api, kind)
    if owner is None:
        return "NO OWNER", ""
    if owner in protocols and owner not in classes:
        # A row naming a delegate protocol is a member of the protocol, and a class table cannot answer
        # it. Its own selector table can; its @protocol chain is not walked, so a member it does not
        # declare is a refusal rather than an absence.
        proto = protocols[owner]
        if member is None:
            return CARRIED, "protocol with %d own instance selectors" % len(proto["instance"])
        table = proto["class"] if member[0] == "class" else proto["instance"]
        got = sorted(table & spellings(("property", member[1])) if member[0] == "property" else table & spellings(member))
        return (CARRIED if got else NO_PROTOCOL_MEMBER), ",".join(x.lstrip("-") for x in got)
    if kind == "protocol":
        proto = protocols.get(owner)
        if proto is None:
            return NO_PROTOCOL, ""
        return CARRIED, "protocol with %d own instance, %d own class selectors" % (len(proto["instance"]),
                                                                                  len(proto["class"]))
    if owner not in classes:
        return NO_CLASS, ""
    if member is None:
        klass = classes[owner]
        return CARRIED, "super %s, %d own instance, %d own class selectors" % (klass["super"],
                                                                               len(klass["instance"]),
                                                                               len(klass["class"]))
    wanted = spellings(member)
    table = "instance" if member[0] == "property" else member[0]
    for depth, name in enumerate(chain(classes, owner)):
        got = sorted(classes[name][table] & wanted)
        if got:
            where = "own" if depth == 0 else "from %s" % name
            return (CARRIED if depth == 0 else INHERITED), "%s %s" % (where, ",".join(x.lstrip("-") for x in got))
    return ABSENT, ""


def rows(path):
    """A queue file's rows: `api<TAB>kind<TAB>introduced<TAB>minimum`, `#` comments and blanks skipped."""
    for line in open(path):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        api, kind, introduced, minimum = line.split("\t")
        yield api, kind, introduced, minimum


def main(argv):
    argv = list(argv[1:])
    if argv and argv[0] == "--inventory":
        # The dump is the expensive half and it is keyed by nothing, so build it once and name it after
        # the release the ladder holds for it - `dyld.held_ladder`'s own choice of architecture.
        argv = argv[1:]
        if "--" not in argv:
            raise SystemExit(__doc__)
        cut = argv.index("--")
        releases, queue = argv[:cut], argv[cut + 1:]
        ladder = []
        for release in releases:
            for arch in ("armv7", "armv7s", "arm64", "arm64e"):
                source = os.path.expanduser("~/.charon/dyld/%s/dyld_shared_cache_%s" % (release, arch))
                if os.path.exists(source):
                    ladder.append((release, arch, source))
                    break
            else:
                raise SystemExit("no held cache for %s under ~/.charon/dyld" % release)
        specs = []
        for release, arch, source in ladder:
            dump = "%s.%s.inventory.tsv" % (release, arch)
            if not os.path.exists(dump):
                raise SystemExit("FAIL %s does not exist: run objc-inventory.lua over %s into it first"
                                 % (dump, source))
            specs.append(("%s-%s" % (release, arch), dump))
        argv = [queue[0]] + ["%s=%s" % (label, path) for label, path in specs]

    if len(argv) < 2:
        raise SystemExit(__doc__)
    queue_rows = list(rows(argv[0]))
    inventories = []
    for spec in argv[1:]:
        label, _, path = spec.partition("=")
        inventories.append((label, load(path)))
    print("# %d rows x %d releases: %s" % (len(queue_rows), len(inventories),
                                           ", ".join(label for label, _ in inventories)))
    wrong = []
    for label, (classes, protocols) in inventories:
        for api, kind, want in CONTROLS:
            got = ask(classes, protocols, api, kind)[0]
            print("# control %-12s %-50s %-7s want %-9s got %s" % (label, api, kind, want, got))
            if got != want:
                wrong.append((label, api, want, got))
    if wrong:
        print("# CONTROL FAILED: the reader does not answer its own controls, so no row below is evidence")
        return 1
    tally = {label: collections.Counter() for label, _ in inventories}
    for api, kind, introduced, minimum in queue_rows:
        cells = []
        for label, (classes, protocols) in inventories:
            verdict, where = ask(classes, protocols, api, kind)
            tally[label][verdict] += 1
            cells.append("%s=%s%s" % (label, verdict, " (%s)" % where if where else ""))
        print("%s\t%s\t%s" % (api, kind, "\t".join(cells)))
    print("# --- per release ---")
    for label, _ in inventories:
        print("# %-12s %s" % (label, dict(sorted(tally[label].items()))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))