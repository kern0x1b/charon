# registry-textrange15.py — the registry entries for the range layer of TextKit 2, generated from the corpus
# rows so that no row is missed and none is spelled by hand twice, with the effect of each row written here
# rather than in the JSON, and a row this script has no effect for is a hard error rather than a generic line.
#
#   python3 tools/corpus/registry-textrange.py
#
# The effects are the rules facts/UIKit/NSTextRange15.md records, and they are the only thing in this file that
# is not mechanical: a reader who wants to know why an entry says what it says is sent there. The rows, their
# kinds, their releases and the shape of an entry all come from the corpus and from the registry's own README.
import csv, json, os, re, sys

CORPUS = os.path.expanduser("~/Git/projects/ios/coordination/corpus/sdk-26.2-surface.tsv")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "packages", "a",
                   "apple-backports", "registry", "UIKit", "ios15textrange.json")
FACTS = "facts/UIKit/NSTextRange15.md"
SOURCE = ("UIKitCore 26.2 arm64e under Mac Catalyst, the host's own UIKit, measured by the probes under "
          ".agent-work/runs/textkit2 and held by tests/backports/host/uikit2/textkit2_test.m")

OWNED_CLASSES = ("NSTextRange", "NSTextSelection", "NSTextElement", "NSTextParagraph", "NSTextSelectionNavigation")
OWNED_PROTOCOLS = ("NSTextLocation", "NSTextSelectionDataSource")
# The constants of this group: the cases of the seven enumerations the headers declare.
VALUES = re.compile(r"NSTextSelection(Affinity|Granularity|Navigation\w+)\w*$")
# NSTextElementProvider is NSTextContentManager's protocol, and its seven members with it: nothing in this
# group sends them, and the content manager is the next group's work.
SKIP = re.compile(r"NSTextElementProvider")

# The effect each row answers with, keyed by the corpus spelling. A row with no entry here is a mistake and
# the script says so rather than writing something generic.
EFFECTS = {
    # classes
    "NSTextRange": "a range between two locations, and every question about one is a comparison of the two: it holds a location or a range, says whether two share contents, and gives the overlap, the intersection and the envelope",
    "NSTextSelection": "one selection over a set of ranges, with the affinity, the granularity, the anchor offset, the logical flag and the typing attributes that say how it behaves, and it is a value: two selections over the same state are -isEqual:",
    "NSTextElement": "the smallest unit of a document's contents: a range in a document, the content manager that owns it, and the three answers that describe the tree it sits in",
    "NSTextParagraph": "a text element whose contents are an attributed string, with the content and separator ranges that string places in the document",
    "NSTextSelectionNavigation": "what a selection moved does: every answer is a question for the data source the object was made with, and with no data source there is no document and the answer is the header's own",
    # protocols
    "NSTextLocation": "a location is anything that answers -compare:, and a range is two of them, so an object that adopts this is a location a range can be made of",
    "NSTextSelectionDataSource": "the navigation object sends each of these to the data source it was made with, and an application that adopts the protocol compiles against the SDK's own declaration of it",
    # properties
    "NSTextRange.empty": "YES when the range's two locations are the same place, which two equal location objects are",
    "NSTextRange.location": "the inclusive location the range starts at, which is the start of a union and the later of two starts for an intersection",
    "NSTextRange.endLocation": "the location directly after the last one in the range, and the start of a range with no end, so a range's end is exclusive for a location and closed for a range",
    "NSTextSelection.textRanges": "the ranges as they were given, in the order they were given, overlapping and out of order included - the header says they are reordered and merged and the system does neither",
    "NSTextSelection.affinity": "upstream or downstream, kept from the initialiser and by a copy",
    "NSTextSelection.granularity": "what an extending operation moves by, kept from the initialiser and by a copy",
    "NSTextSelection.transient": "whether a drag is making this selection; readonly in the header, so it is the value the selection was made with and a copy carries it",
    "NSTextSelection.anchorPositionOffset": "the offset of the non-anchored edge from its position, kept and copied, and one of the keys that make two selections equal",
    "NSTextSelection.logical": "NO once a secondary location is set, as the header says, and a copy keeps the flag it was made with rather than the one the setter would give it",
    "NSTextSelection.secondarySelectionLocation": "the location typing goes at when the selection is not logical, and nil for a logical one; a copy carries it",
    "NSTextSelection.typingAttributes": "the attributes new text is typed with: nil for a selection that was never given any, an empty dictionary once the setter has been called at all, the caller's dictionary copied, and an empty dictionary in a copy",
    "NSTextElement.textContentManager": "the manager that owns the element, and the document its ranges are positions in; weak, and nil for an element made on its own",
    "NSTextElement.elementRange": "the range of the element inside the document, and what the two derived ranges of a paragraph are placed from",
    "NSTextElement.childElements": "the elements inside this one, and an empty array for an element that is not inside another - the tree the content manager builds out of the elements it is given",
    "NSTextElement.parentElement": "the element this one is inside, and nil for one that is not inside another",
    "NSTextElement.isRepresentedElement": "YES: every element is one the content manager enumerates, the base class and a paragraph included",
    "NSTextParagraph.attributedString": "the string the paragraph holds, which is its contents, and nil for a paragraph made with none",
    "NSTextParagraph.paragraphContentRange": "the string without the trailing newline that ends the paragraph, placed in the document; nil while there is no content manager, which is the host's own answer in that state",
    "NSTextParagraph.paragraphSeparatorRange": "the trailing newline that ends the paragraph, placed in the document; nil when the contents do not end in one and while there is no content manager",
    "NSTextSelectionNavigation.textSelectionDataSource": "the data source every answer of this object is a question for, and nil for one made with none",
    "NSTextSelectionNavigation.allowsNonContiguousRanges": "YES unless it is set to NO, which is the host's own default",
    "NSTextSelectionNavigation.rotatesCoordinateSystemForLayoutOrientation": "NO unless it is set to YES, which is the host's own default",
    "NSTextSelectionDataSource.documentRange": "the navigation object reads it to move a selection to the start or the end of the document, and a nil or empty one means there is nowhere to move to",
}

# Methods, by selector. Each effect is what the method answers.
METHODS = {
    "-[NSTextRange initWithLocation:endLocation:]": "a range between the two, and an empty range at the location when the end is nil, which is what the header says",
    "-[NSTextRange initWithLocation:]": "an empty range at the location, whose end is the location itself",
    "-[NSTextRange init]": "raises NSInternalInconsistencyException naming the initialiser to use: a range is two locations, and the host faults on this one",
    "+[NSTextRange new]": "raises, through -init: the host faults on it and a range with no locations in it would be a silent nothing",
    "-[NSTextRange isEqualToTextRange:]": "YES when both pairs of locations are the same places, and NO for nil",
    "-[NSTextRange containsLocation:]": "the header's rule, (location <= l) && (l < endLocation), so the end is exclusive and an empty range holds nothing",
    "-[NSTextRange containsRange:]": "a range with contents is held whole with the end closed, and an empty range is held exactly when its one location is, so 0...10 holds 3...3 and does not hold 10...10; an empty range holds nothing at all",
    "-[NSTextRange intersectsWithTextRange:]": "YES when two non-empty ranges share contents, each starting before the other ends; ranges that touch share nothing, and an empty range shares nothing",
    "-[NSTextRange textRangeByIntersectingWithTextRange:]": "the later of the two starts and the earlier of the two ends when the ranges overlap or one is inside the other, and nil when they only touch or do not meet",
    "-[NSTextRange textRangeByFormingUnionWithTextRange:]": "the envelope of two ranges with contents, and the range that has contents when one of them is empty - or the one handed in when both are",
    "-[NSTextSelection initWithRanges:affinity:granularity:]": "a selection over the ranges as they are given, in the order they are given, and a copy of the array",
    "-[NSTextSelection initWithRange:affinity:granularity:]": "a selection of the one range, and of no ranges at all for nil",
    "-[NSTextSelection initWithLocation:affinity:]": "a cursor: a selection of one 0-length range at the location, with a character granularity",
    "-[NSTextSelection initWithCoder:]": "a selection read back from an archive, with an empty dictionary for typing attributes the archive did not hold",
    "-[NSTextSelection init]": "raises NSInternalInconsistencyException naming the initialiser to use: a selection is ranges, an affinity and a granularity, and the host faults on this one",
    "-[NSTextSelection textSelectionWithTextRanges:]": "a copy over the new ranges, keeping the affinity, the granularity, the transient flag, the anchor offset, the logical flag, the secondary location and the typing attributes, and with an empty dictionary where the selection it was made from had nil",
    "+[NSTextSelection supportsSecureCoding]": "YES on both sides; a range is not secure-coding, so a selection that holds ranges cannot actually be archived and the archiver raises",
    "+[NSTextSelectionNavigation new]": "raises, through -init: every answer of this object is a question for a data source, and the host faults on this one",
    "-[NSTextSelectionNavigation init]": "raises NSInternalInconsistencyException naming the initialiser to use: a navigation object with no data source has nothing to ask",
    "-[NSTextSelectionNavigation initWithDataSource:]": "a navigation object over that data source, allowed to make disjoint ranges and not rotating the coordinate system",
    "-[NSTextSelectionNavigation flushLayoutCache]": "nothing to do: the port asks its data source for everything each time and caches nothing, and an application calls this after changing the document",
    "-[NSTextSelectionNavigation destinationSelectionForTextSelection:direction:destination:extending:confined:]": "nil while there is no data source, because every answer of this method is a place in a document and the header says a movement with no valid result answers nil; with one, the range between where the selection was and where the movement reaches, and extending keeps the first location and moves only the end",
    "-[NSTextSelectionNavigation textSelectionsInteractingAtPoint:inContainerAtLocation:anchors:modifiers:selecting:bounds:]": "an empty array while there is no data source, since there is no line under a point; with one, the line's selection, or the anchor's when a drag extends from it",
    "-[NSTextSelectionNavigation textSelectionForSelectionGranularity:enclosingTextSelection:]": "nil while there is no data source, since there are no boundaries to expand to and an unexpanded range would claim an expansion that did not happen",
    "-[NSTextSelectionNavigation textSelectionForSelectionGranularity:enclosingPoint:inContainerAtLocation:]": "nil while there is no data source, since there is no line under a point to enclose a word in",
    "-[NSTextSelectionNavigation resolvedInsertionLocationForTextSelection:writingDirection:]": "the secondary location of a selection that is not logical and has one, and nil otherwise, which is the header's own rule; the writing direction does not enter into it, because a secondary location is one location and not a range with two ends",
    "-[NSTextSelectionNavigation deletionRangesForTextSelection:direction:destination:allowsDecomposition:]": "the selection's own ranges when it has contents, whatever the destination; for a cursor, what a move over the same destination would have selected, which with no data source is the cursor's own 0-length range",
    "-[NSTextElement initWithTextContentManager:]": "an element owned by that manager, or by none; -init is the same thing and the host faults on it",
    "-[NSTextParagraph initWithAttributedString:]": "a paragraph whose contents are that string, and nil for a paragraph made with none",
    "-[NSTextLocation compare:]": "the ordering of two locations, which is the whole of what a location has to answer and all a range ever asks of one",
    # the data source's own members: the navigation object sends each of these
    "-[NSTextSelectionDataSource documentRange]": "the navigation object moves a selection to the start or the end of this, and a nil or empty one means there is nowhere to move to",
    "-[NSTextSelectionDataSource enumerateSubstringsFromLocation:options:usingBlock:]": "the navigation object's own segmentation: it is what knows where the next word, line, sentence or paragraph is, and the port asks it rather than guessing",
    "-[NSTextSelectionDataSource textRangeForSelectionGranularity:enclosingLocation:]": "the range a granularity encloses at a location, which is where a move over a word, a line, a sentence or a paragraph lands",
    "-[NSTextSelectionDataSource locationFromLocation:withOffset:]": "a location that many characters on, which is how a move over one character or paragraph separator is placed",
    "-[NSTextSelectionDataSource offsetFromLocation:toLocation:]": "the offset between two locations, which is what a paragraph asks to place its two derived ranges in the document",
    "-[NSTextSelectionDataSource baseWritingDirectionAtLocation:]": "the base direction at a location, which is what an insertion location is resolved against",
    "-[NSTextSelectionDataSource enumerateCaretOffsetsInLineFragmentAtLocation:usingBlock:]": "the caret offsets of a line, in visual order, which is what a selection's affinity describes",
    "-[NSTextSelectionDataSource lineFragmentRangeForPoint:inContainerAtLocation:]": "the line under a point, which is what a tap and a mouse-down select, and what a word at a point is enclosed from",
    "-[NSTextSelectionDataSource enumerateContainerBoundariesFromLocation:reverse:usingBlock:]": "the container and page boundaries a move to a container destination lands on; a data source that does not enumerate them has none, and the navigation object answers nil for such a move, which is what the header says a movement with no valid result answers",
    "-[NSTextSelectionDataSource textLayoutOrientationAtLocation:]": "the orientation of the layout at a location; the navigation object assumes horizontal when a data source does not implement it, which is what the header says",
}

def load_rows():
    """The corpus rows this group owns: a row of one of the five classes, or of one of the two protocols the
    range layer is written against. NSTextElementProvider is NSTextContentManager's protocol and is left to
    the group that carries that class."""
    with open(CORPUS, newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    keep, values = [], []
    for row in rows:
        if row["framework"] != "UIKit" or row["lang"] != "objc":
            continue
        api = row["api"]
        if SKIP.search(api):
            continue
        if api in OWNED_CLASSES or api in OWNED_PROTOCOLS:
            keep.append(row)
            continue
        method = re.match(r"[-+]\[([A-Za-z_]+) ", api)
        name = method.group(1) if method else api.split(".")[0]
        if name in OWNED_CLASSES or name in OWNED_PROTOCOLS:
            keep.append(row)
        elif VALUES.match(api):
            # A case of an enumeration or a macro is written into the application by the compiler and neither
            # side of the check can see it, so it gets no entry: registry/README.md. It is counted and named
            # here, not dropped, so that a row of this group the script did not account for cannot pass by
            # being skipped.
            values.append(row)
        # Anything else is another group's row and is not this script's business.
    return keep, values

def entry_for(row):
    api = row["api"]
    kind = row["kind"]
    if kind == "class":
        effect = EFFECTS.get(api)
        return dict(api=api, kind=kind, introduced=row["introduced"], minimum="6.0", status="implemented",
                    facts=FACTS, effect=effect, source=SOURCE) if effect else None
    if kind == "protocol":
        effect = EFFECTS.get(api)
        return dict(api=api, kind=kind, introduced=row["introduced"], minimum="6.0", status="implemented",
                    facts=FACTS, effect=effect, source=SOURCE) if effect else None
    if kind == "property":
        effect = EFFECTS.get(api)
        return dict(api=api, kind=kind, introduced=row["introduced"], minimum="6.0", status="implemented",
                    facts=FACTS, effect=effect, source=SOURCE) if effect else None
    if kind == "method":
        effect = METHODS.get(api)
        return dict(api=api, kind=kind, introduced=row["introduced"], minimum="6.0", status="implemented",
                    facts=FACTS, effect=effect, source=SOURCE) if effect else None
    raise SystemExit("unhandled kind " + kind + " for " + api + " - give it the effect it answers, above")

def main():
    rows, values = load_rows()
    entries, missing = [], []
    for row in rows:
        entry = entry_for(row)
        if entry is None:
            missing.append(row["kind"] + " " + row["api"])
            continue
        entries.append(entry)
    if missing:
        raise SystemExit("no effect written for:\n  " + "\n  ".join(missing))
    entries.sort(key=lambda e: (e["kind"], e["api"]))
    with open(OUT, "w") as handle:
        json.dump({"framework": "UIKit", "entries": entries}, handle, indent=2)
        handle.write("\n")
    kinds = {}
    for entry in entries:
        kinds[entry["kind"]] = kinds.get(entry["kind"], 0) + 1
    print(f"{len(rows)} rows of the group: {len(entries)} entries {kinds}")
    print(f"plus {len(values)} header-only values, which get no entry by registry/README.md:")
    for name in sorted({v['api'] for v in values}):
        print("  " + name)

main()
