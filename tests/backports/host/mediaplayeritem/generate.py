#!/usr/bin/env python3
"""Emits one release group of MPMediaItem's properties, and the check's table, from ONE list.

The getters a group carries, the facts rows that cite them, and the table the host contract check
asserts are three places that would drift if they were written separately, so all three come from the
list below: this script writes the library file, appends the facts rows, and writes the check's table.

    python3 tests/backports/host/mediaplayeritem/generate.py 80

`key` is the property's own name, and `getter` is the header's `getter=` name when it has one. That the
dictionary key is the property name is the documented convention for MPMediaItem's property constants -
they are spelled as the property - and it is **not** verified against a populated item, because neither
this Mac nor 6.1.3 has one without a media library. What *is* measured is that the release has none of
these members at all, so a port-created item is the only thing that can answer them here.
"""
import os
import pathlib
import sys

# (property, type, getter, key) - the single list for this group. 7.0 was hand-written before the
# generator existed and is here now, so one writer emits every group and none is typed twice.
GROUP_70 = [("albumTrackNumber", "NSUInteger", "albumTrackNumber", "albumTrackNumber"),
            ("discNumber", "NSUInteger", "discNumber", "discNumber")]
GROUP_80 = [
    ("albumPersistentID", "MPMediaEntityPersistentID", "albumPersistentID", "albumPersistentID"),
    ("artistPersistentID", "MPMediaEntityPersistentID", "artistPersistentID", "artistPersistentID"),
    ("albumArtistPersistentID", "MPMediaEntityPersistentID", "albumArtistPersistentID", "albumArtistPersistentID"),
    ("genrePersistentID", "MPMediaEntityPersistentID", "genrePersistentID", "genrePersistentID"),
    ("composerPersistentID", "MPMediaEntityPersistentID", "composerPersistentID", "composerPersistentID"),
    ("podcastPersistentID", "MPMediaEntityPersistentID", "podcastPersistentID", "podcastPersistentID"),
    ("albumTrackCount", "NSUInteger", "albumTrackCount", "albumTrackCount"),
    ("discCount", "NSUInteger", "discCount", "discCount"),
    ("beatsPerMinute", "NSUInteger", "beatsPerMinute", "beatsPerMinute"),
    ("compilation", "BOOL", "isCompilation", "isCompilation"),
    ("cloudItem", "BOOL", "isCloudItem", "isCloudItem"),
    ("lyrics", "NSString *", "lyrics", "lyrics"),
    ("comments", "NSString *", "comments", "comments"),
    ("userGrouping", "NSString *", "userGrouping", "userGrouping"),
    ("assetURL", "NSURL *", "assetURL", "assetURL"),
]

# The three groups after 8.0, with the release as the header writes it and as the file names it. Two of
# the four are declared with a getter=, so the property name is the first field and the selector the third.
GROUP_92 = [("protectedAsset", "BOOL", "hasProtectedAsset", "hasProtectedAsset")]
GROUP_100 = [("dateAdded", "NSDate *", "dateAdded", "dateAdded"),
              ("explicitItem", "BOOL", "isExplicitItem", "isExplicit")]
GROUP_103 = [("playbackStoreID", "NSString *", "playbackStoreID", "playbackStoreID"),
             ("preorder", "BOOL", "isPreorder", "isPreorder")]

# The property-key constants, each the same-named string: the header declares them NSString * const and
# the dictionary is keyed by the property's name, so a constant that named anything else would name a key
# nothing reads. The release each arrived in is its own group's, per the header's MP_API.
# A member's dictionary key is what the constant of that name holds, and this Mac's own MediaPlayer says
# what that is: the property's own name, except where the 26.2 header declares a getter=, where the value
# is the getter's name. Measured, not assumed - see constant-values.m, and the five keys it moved are the
# ones with a getter= (isCompilation, isCloudItem, hasProtectedAsset, isExplicit, isPreorder).
#
# The property-key constants, one per release, emitted as the globals the header declares: a
# `NSString * const` at file scope, outside the @implementation, so a caller that spells the constant the
# way Apple spells it links against a data symbol. A class property would be a method and would not.
CONSTANTS = {
    70: [("MPMediaItemPropertyIsExplicit", "isExplicit")],
    80: [],
    92: [("MPMediaItemPropertyHasProtectedAsset", "hasProtectedAsset")],
    100: [("MPMediaItemPropertyDateAdded", "dateAdded")],
    103: [("MPMediaItemPropertyPlaybackStoreID", "playbackStoreID")],
    145: [("MPMediaItemPropertyIsPreorder", "isPreorder")],
}
# MPMediaItemPropertyIsExplicit is 7.0 and MPMediaItemPropertyIsPreorder is 14.5, so each needs a group
# of its own rather than a neighbour's file: one object, one release, per band()'s own rule.
GROUP_145 = []
CONSTANTS[145] = [("MPMediaItemPropertyIsPreorder", "isPreorder")]

GROUPS = {70: GROUP_70, 80: GROUP_80, 92: GROUP_92, 100: GROUP_100, 103: GROUP_103, 145: GROUP_145}
# The file and the table are named for the release without its dot; the header line quotes it with.
LABEL = {70: "7.0", 80: "8.0", 92: "9.2", 100: "10.0", 103: "10.3", 145: "14.5"}


# How each type is read out of the property dictionary. A type with no entry is not carried.
CONVERSION = {
    "NSUInteger": "[[self valueForProperty:@\"%s\"] unsignedIntegerValue]",
    "BOOL": "[[self valueForProperty:@\"%s\"] boolValue]",
    "MPMediaEntityPersistentID": "(MPMediaEntityPersistentID)[self valueForProperty:@\"%s\"]",
    "NSString *": "(NSString *)[self valueForProperty:@\"%s\"]",
    "NSURL *": "(NSURL *)[self valueForProperty:@\"%s\"]",
    "NSDate *": "(NSDate *)[self valueForProperty:@\"%s\"]",
}

HEADER = """// MPMediaItem's %(count)d %(release)s members, the ones this release does not have at all.
//
// Generated from the one list in tests/backports/host/mediaplayeritem/generate.py, with the facts rows
// and the host check's table, so the three cannot drift. Do not edit by hand: change the list and run the
// generator.
//
// What 6.1.3 has, measured with tools/mach32_methods.py against the 6.1.3 cache: none of these is in any
// of the image's 236 classes' own instance lists nor in any of its 41 categories - not on MPMediaItem
// (75 own methods), not on MPMediaEntity (18), not on MPConcreteMediaItem (29), the private class a real
// item's receiver is. What the release does have is the accessor they are conveniences over:
// valueForProperty: is an own method of MPMediaEntity. So a port-created item answers from its own
// dictionary, a real item is answered by the release, and a category on the public class clobbers nothing
// because a subclass's own method wins over a category on its public ancestor.
//
// Split by introduced release, per band()'s own rule: this file holds the %(count)d the 26.2 header
// declares MP_API(ios(%(release)s)).

#import <Foundation/Foundation.h>
#if defined(CHARON_MEDIAPLAYER_STANDIN)
// The host contract check compiles this file with the stand-in in place of the framework, so it measures
// this code and not the Mac's own MediaPlayer.
#import "MPMediaItemStandin.h"
#else
#import <MediaPlayer/MediaPlayer.h>
#endif

@interface MPMediaItem (Charon%(name)s)
%(declarations)s@end

%(constants_decl)s
@implementation MPMediaItem (Charon%(name)s)

%(bodies)s@end

%(constants_def)s"""


def emit(release, members, root):
    label = LABEL[release]
    library = os.path.join(root, "packages", "a", "apple-backports", "MediaPlayer", "MPMediaItem%s.m" % release)
    declarations, bodies = [], []
    constants = CONSTANTS.get(release, [])
    # The value is the property's own name, which is the dictionary key - the same convention the
    # getters use and the same one coordination/crutches.md records as unverified.
    constants_decl = "".join('extern NSString * const %s;\n' % c for c, _k in constants)
    constants_def = "".join('NSString * const %s = @"%s";\n' % (c, k) for c, k in constants)
    for name, kind, getter, key in members:
        if kind not in CONVERSION:
            raise SystemExit("%s has type %s, which this generator cannot read" % (name, kind))
        declarations.append("@property (nonatomic, readonly) %s %s;\n" % (kind, name))
        bodies.append("- (%s)%s {\n    return %s;\n}\n\n"
                      % (kind, getter, CONVERSION[kind] % key))
    with open(library, "w") as out:
        out.write(HEADER % {"count": len(members), "release": label, "name": release,
                            "declarations": "".join(declarations), "bodies": "".join(bodies),
                            "constants_decl": constants_decl, "constants_def": constants_def})

    table = os.path.join(root, "tests", "backports", "host", "mediaplayeritem", "members%s.h" % release)
    with open(table, "w") as out:
        out.write("// Generated by tests/backports/host/mediaplayeritem/generate.py from its one list.\n"
                  "// (getter, type, key)\n")
        for name, kind, getter, key in members:
            out.write('    {"%s", "%s", "%s"},\n' % (getter, kind, key))
    facts = os.path.join(root, "packages", "a", "apple-backports", "facts", "MediaPlayer", "MPMediaItem.md")
    write_facts(facts, release, members, label)
    print("wrote %s, %s and the facts rows from %d members" % (library, table, len(members)))


BEGIN = "<!-- generated: %s -->"
END = "<!-- /generated: %s -->"


def write_facts(facts, release, members, label):
    """The facts rows for a release, written by this script and only by it.

    They live between markers so a re-run replaces them rather than appending a second copy: two writers
    of the same rows is the drift this generator exists to remove.
    """
    header = "\n".join(
        "    @property (nonatomic, readonly%s) %s %s MP_API(ios(%s));"
        % (", getter = %s" % getter if getter != name else "", kind, name, LABEL[release])
        for name, kind, getter, _key in members)
    renamed = [(name, getter) for name, _kind, getter, _key in members if getter != name]
    body = [
        BEGIN % release,
        "",
        "## %s - `MPMediaItem%s.m`" % (LABEL[release], release),
        "",
        "The %d members the 26.2 header declares `MP_API(ios(%s))`, generated from the one list in"
        % (len(members), LABEL[release]),
        "`tests/backports/host/mediaplayeritem/generate.py` together with the getters and the check's table:",
        "",
        header,
        "",
        "Each member's dictionary key is the property's own name, which is the documented convention for",
        "MPMediaItem's property constants and the only reading the header's spelling supports. It is **not**",
        "verified against a populated item, because neither this Mac nor 6.1.3 can be given one without a",
        "media library; what *is* measured is that the release carries none of these members, so a",
        "port-created item - one built from a dictionary, which is exactly what the stand-in in the contract",
        "check is - is the only thing that can answer them here.",
    ]
    if renamed:
        body += ["",
                 "Declared with a `getter=` attribute, so the property name is not the selector: "
                 + ", ".join("`%s` is implemented as `%s`" % (n, g) for n, g in renamed) + "."]
    body += [END % release, ""]
    text = pathlib.Path(facts).read_text() if os.path.exists(facts) else "# MPMediaItem\n"
    begin, end = BEGIN % label, END % label
    if begin in text:
        head = text[:text.index(begin)]
        tail = text[text.index(end) + len(end):]
    else:
        head, tail = text.rstrip("\n") + "\n", ""
    pathlib.Path(facts).write_text(head + "\n".join(body) + tail)


def main(argv):
    if len(argv) != 2:
        sys.stderr.write(__doc__)
        return 2
    release = int(argv[1])
    if release not in GROUPS:
        sys.stderr.write("no list for release %s; add one to GROUPS\n" % release)
        return 2
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
    emit(release, GROUPS[release], root)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
