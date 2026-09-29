#!/usr/bin/env python3
# registry-content15.py — the registry entries for the model of TextKit 2: the content manager, the content
# storage, the list element, the four protocols between them, and the port's own NSTextLocation. Generated from
# the corpus rows so that no row of the group is missed and none is spelled by hand twice, with the effect of
# each row written here rather than in the JSON, and a row of the group this script has no effect for is a hard
# error rather than a generic line.
#
#   python3 tools/corpus/registry-content15.py
#
# The effects are the rules facts/UIKit/NSTextContent15.md records, and they are the only thing in this file
# that is not mechanical: a reader who wants to know why an entry says what it says is sent there. The rows,
# their kinds, their releases and the shape of an entry all come from the corpus and the registry's own README.
#
# M-numbers in an effect are the measurements in that facts file: M1 the host's content storage cannot be made,
# M2 a bare manager's defaults, M3 a synchronization inside a transaction, M4 the list element's two factories,
# M5 -initWithAttributedString: on a list element, M6 the item marker.
import csv
import json
import os
import re
import sys

CORPUS = os.path.expanduser("~/Git/projects/ios/coordination/corpus/sdk-26.2-surface.tsv")
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "packages", "a", "apple-backports", "registry", "UIKit", "ios15content.json")
FACTS = "facts/UIKit/NSTextContent15.md"
SOURCE = ("UIKitCore 26.2 arm64e under Mac Catalyst, the host's own UIKit, measured by "
          ".agent-work/runs/textkit2/probe-content.m and held by tests/backports/host/uikit2/content15_test.m")

OWNED_CLASSES = ("NSTextContentManager", "NSTextContentStorage", "NSTextListElement")
OWNED_PROTOCOLS = ("NSTextElementProvider", "NSTextStorageObserving", "NSTextContentManagerDelegate",
                   "NSTextContentStorageDelegate")
# The port's own NSTextLocation: a name no SDK header declares, so it is a private entry point and takes the
# release of the API that needed it, which is the range layer of 15.0.
PRIVATE = {"CharonTextLocation": "15.0"}
VALUES = re.compile(r"NSText(ContentManager|ContentStorage)\w*$")
# A notification name is a symbol, not a case of an enumeration, so it is not one of the header-only values.
NOT_A_VALUE = re.compile(r"Notification$")

EFFECTS = {
    "CharonTextLocation": ("a position in a document: an offset and the document it is in, which is all "
                           "NSTextLocation's one method - a comparison - needs, and which is what a range is made "
                           "of; a name no SDK header declares, so the lift's sets are re-measured for it in this "
                           "push (rule R4)"),
    # classes
    "NSTextContentManager": "the root of TextKit 2's object network: the layout managers, the primary one, the editing transaction and the record of what each edit did, with the document itself left to a concrete subclass, and its own defaults are the host's - no layout manager, not in a transaction, layout managers synchronized when the outermost transaction ends and the backing store not",
    "NSTextContentStorage": "a document over an NSTextStorage, and the factory for the locations a range is made of: its document range, the offset arithmetic over its own locations, one NSTextParagraph per paragraph cut at the paragraph endings, the two conversions between an element and a string, and the observation of the storage that keeps a range true while the text under it is edited",
    "NSTextListElement": "an element whose contents are a list item: the item's own text, the marker's formatting, the items nested inside it, and the string the document holds for it, which is the marker and the text together",
    "NSTextElementProvider.documentRange": "the document's range in the document's own locations, from offset zero to the string's length, and nil for the abstract manager, which has no document",
    "NSTextStorageObserving.textStorage": "the storage the document is held in, held strongly by the content storage because the storage's own reference to its observer is weak",
    "NSTextContentStorage.includesTextListMarkers":
        "a 26.0 member the build SDK does not declare, so no property carries it below 26.0: the port's storage carries the document's own text and the caller adds the markers, which is what the 16.0 element's own marker rule already describes",
    # protocols
    "NSTextElementProvider": "the content storage is the port's implementation of it: the document range, the element enumeration in both directions, the replacement, the synchronisation and the two location conversions, each sent by the object that holds the document",
    "NSTextStorageObserving": "the content storage is the port's observer of the text storage it is made over: the two messages the storage sends an observer are the port's way of learning that an edit has finished, which is what keeps every range in the document true",
    "NSTextContentManagerDelegate": "the manager asks its delegate for the element at a location and whether an element takes part in an enumeration, and a delegate that implements neither leaves the manager's own mapping and its own enumeration as they are",
    "NSTextContentStorageDelegate": "the content storage asks its delegate for the paragraph of a range, which is how a document type of an application's own supplies elements instead of the port's paragraph mapping",
    # properties
    "NSTextContentManager.delegate": "the delegate the manager asks for an element at a location and for whether an element is enumerated, and nil for a manager with none",
    "NSTextContentManager.textLayoutManagers": "the layout managers the manager holds, in the order they were added, and empty for a bare one",
    "NSTextContentManager.primaryTextLayoutManager": "the one the user is interacting with, which is the one that may edit; the first added is the primary unless something else is set, setting a manager that is not in the list resets it to nil, and removing the primary resets it too",
    "NSTextContentManager.hasEditingTransaction": "YES between the outermost -performEditingTransactionUsingBlock: and its return, and NO outside one, whatever a nested transaction does",
    "NSTextContentManager.automaticallySynchronizesTextLayoutManagers": "YES unless it is set to NO, which is the host's own default: the layout managers are synchronized when the outermost transaction ends",
    "NSTextContentManager.automaticallySynchronizesToBackingStore": "NO unless it is set to YES, which is the host's own default: the backing store is not synchronized on its own",
    "NSTextContentStorage.delegate": "the delegate asked for the paragraph of a range, and nil for a storage with none, which is the standard paragraph mapping",
    "NSTextContentStorage.attributedString": "the document's string, as a copy; a storage of its own wins over it, so setting the string while there is one leaves the document where it is",
    "NSTextContentStorage.textStorage": "the storage the document is held in, which the port holds strongly and which observes it back, so that an edit is learned the moment it finishes",
    # methods
    "-[NSTextContentManager init]": "a manager with no layout managers, in no transaction, with the host's own two flag defaults, and no document - a document belongs to a concrete subclass",
    "-[NSTextContentManager initWithCoder:]": "a manager read back from an archive, with the two synchronisation flags it recorded and the host's defaults for either the archive does not hold",
    "-[NSTextContentManager addTextLayoutManager:]": "the manager holds it, and it becomes the primary if there is none, which is the header's reading of a manager with a user interacting through it",
    "-[NSTextContentManager removeTextLayoutManager:]": "the manager lets it go, and a primary that is gone becomes nil rather than the next one",
    "-[NSTextContentManager synchronizeTextLayoutManagers:]": "the layout managers are synchronized, and a handler is called with no error; a synchronization asked for inside an editing transaction raises nothing, which is what the host does where the header says it should block (M3)",
    "-[NSTextContentManager performEditingTransactionUsingBlock:]": "the block runs with -hasEditingTransaction YES, nests, and the outermost frame sends the two synchronisations the flags ask for; a block that raises still leaves the transaction, so a raise cannot leave the manager permanently in one",
    "-[NSTextContentManager recordEditActionInRange:newTextRange:]": "the pair of ranges is recorded for the layout managers to read when they synchronize, and a pair with a missing range is refused with NSInvalidArgumentException as the host refuses it",
    "-[NSTextContentManager textElementsForRange:]": "the elements meeting the range, in sequence, and none for a manager with no document",
    "-[NSTextElementProvider documentRange]": "the document's range in the document's own locations, from offset zero to the string's length, and nil for the abstract manager, which has no document",
    "-[NSTextElementProvider enumerateTextElementsFromLocation:options:usingBlock:]": "the elements from a location - the document's start going forward and the element before the one containing it going back, and the end of the document going back from nil - each asked of the delegate first, and the edge the enumeration reached",
    "-[NSTextElementProvider replaceContentsInRange:withTextElements:]": "the characters of the range are replaced by the elements' own contents, and the document range is rebuilt; an element whose contents are not a string contributes nothing, which is what the header calls adjusting the replacement range",
    "-[NSTextElementProvider synchronizeToBackingStore:]": "the document is written out and a handler called with no error, and a synchronisation asked for inside an editing transaction raises nothing, as on the host (M3)",
    "-[NSTextElementProvider locationFromLocation:withOffset:]": "a location that many characters on, and nil for a location of another document or one that would fall outside it, which is what the header says a nil here is",
    "-[NSTextElementProvider offsetFromLocation:toLocation:]": "the number of characters between two locations, and NSNotFound for a pair that is not one document's, which is the header's own case",
    "-[NSTextElementProvider adjustedRangeFromRange:forEditingTextSelection:]": "nil until something has been edited, and afterwards the range the header describes: one that ends before the edit began is unchanged, one that begins after it moves by what the edit did, and one that meets it is cut at the edit's end",
    "-[NSTextContentStorage attributedStringForTextElement:]": "the element's own string, and nil for an element whose contents are not a string, which is the header's own case",
    "-[NSTextContentStorage textElementForAttributedString:]": "the element for a string, which is the paragraph of that string, and nil for none",
    "-[NSTextContentStorage locationFromLocation:withOffset:]": "a location of this document that many characters on, and nil outside the document or for a location of another",
    "-[NSTextContentStorage offsetFromLocation:toLocation:]": "the number of characters between two locations of this document, and NSNotFound for a pair that is not one document's",
    "-[NSTextContentStorage adjustedRangeFromRange:forEditingTextSelection:]": "the range as it reads after the last edit, and nil when nothing has been edited or the pair is not one document's",
    "-[NSTextStorageObserving processEditingForTextStorage:edited:range:changeInLength:invalidatedRange:]": "the document learns an edit has finished: its range is rebuilt from the storage's new length and the edit is recorded, which is what keeps every range in the document true",
    "-[NSTextStorageObserving performEditingTransactionForTextStorage:usingBlock:]": "the block runs inside the manager's own transaction, so nesting and the outermost synchronisation are the manager's",
    "-[NSTextStorageObserving textStorage]": "the storage the document is held in, held strongly by the content storage because the storage's own reference to its observer is weak",
    # the delegate methods
    "-[NSTextContentManagerDelegate textContentManager:textElementAtLocation:]": "the element the manager uses at a location, so a document type of an application's own supplies it instead of the port's mapping; a manager with no delegate uses its own",
    "-[NSTextContentManagerDelegate textContentManager:shouldEnumerateTextElement:options:]": "NO skips the element from the enumeration, which is how a provider hides an element from the layout; a manager with no delegate enumerates all of them",
    "-[NSTextContentStorageDelegate textContentStorage:textParagraphWithRange:]": "the paragraph of a range, used in place of the port's own paragraph for that range, which is how a document type of an application's own supplies its elements",
}

METHODS_EXTERNAL = {
    # the list element's two factories and its unavailable initializer
    "+[NSTextListElement textListElementWithContents:markerAttributes:textList:childElements:]":
        "a standard list item: the contents, the marker's formatting, the list it is in and the items nested inside it, whose displayed string is the marker and the contents together",
    "+[NSTextListElement textListElementWithChildElements:textList:nestingLevel:]":
        "a nesting parent over the children, nil when there are none, and NSInvalidArgumentException for a negative nesting level, which is the host's own answer as well as the header's (M4)",
    "-[NSTextListElement initWithAttributedString:]":
        "an element with the string as what it displays and no list, no contents and no marker of its own, which is what the host answers although the header marks the initializer unavailable (M5)",
    "-[NSTextListElement initWithParentElement:textList:contents:markerAttributes:childElements:]":
        "either a standard item or a nesting parent, and an item with none of the three of contents, marker attributes and children is refused with NSInvalidArgumentException, since there is nothing to display and nothing to mark",
}
EFFECTS.update(METHODS_EXTERNAL)

PROPERTIES_EXTERNAL = {
    "NSTextListElement.contents": "the item's own text, without its marker and without the formatting the marker carries, and nil for an element made with -initWithAttributedString:",
    "NSTextListElement.markerAttributes": "what the marker is drawn with, and nil when it is derived from the contents instead",
    "NSTextListElement.attributedString": "what the document holds for the element: the marker and the contents together, which is the only part of a list element that has characters in the document",
    "NSTextListElement.childElements": "the items nested inside this one, and none for a standard item",
    "NSTextListElement.parentElement": "the item this one is nested inside, and nil for one that is at the top",
    "NSTextListElement.textList": "the list the marker and the numbering come from, and nil for an element made with -initWithAttributedString:",
}
EFFECTS.update(PROPERTIES_EXTERNAL)


def load_rows():
    """The corpus rows this group owns: one of the three classes, one of the four protocols, or a member of
    one of them. NSTextListElement is here because a list element is a document's element; the layout half's
    own classes are not in this group."""
    with open(CORPUS, newline="") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    keep, values, unmatched = [], [], []
    for row in rows:
        if row["framework"] != "UIKit" or row["lang"] != "objc":
            continue
        api = row["api"]
        if api in OWNED_CLASSES or api in OWNED_PROTOCOLS or api in PRIVATE:
            keep.append(row)
            continue
        if VALUES.match(api) and not NOT_A_VALUE.search(api):
            # A case of an enumeration or a macro is written into the application by the compiler and neither
            # side of the check can see it, so it gets no entry: registry/README.md. It is counted and named
            # here, not dropped, so that a row of this group the script did not account for cannot pass by
            # being skipped.
            values.append(row)
            continue
        method = re.match(r"[-+]\[([A-Za-z_]+) ", api)
        name = method.group(1) if method else api.split(".")[0]
        if name in OWNED_CLASSES or name in OWNED_PROTOCOLS or name in PRIVATE:
            keep.append(row)
        elif (VALUES.match(name) or VALUES.match(api)) and not NOT_A_VALUE.search(api):
            values.append(row)
        # Anything else is another group's row and is not this script's business.
    return keep, values


def entry_for(row):
    api = row["api"]
    kind = row["kind"]
    introduced = PRIVATE.get(api, row["introduced"])
    minimum = "6.0"
    effect = EFFECTS.get(api)
    if effect is None:
        return None
    return dict(api=api, kind=kind, introduced=introduced, minimum=minimum, status="implemented",
                facts=FACTS, effect=effect, source=SOURCE)


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
    # The port's own location type, which no SDK header declares, so no corpus row names it: it is carried from
    # the release of the API that needed it, and rule R4 asks a delivery with such a name to say so.
    entries.append(dict(api="CharonTextLocation", kind="class", introduced=PRIVATE["CharonTextLocation"],
                         minimum="6.0", status="implemented", facts=FACTS, effect=EFFECTS["CharonTextLocation"],
                         source=SOURCE))
    # A notification name is a symbol and not a case of an enumeration, so it takes an entry, and this one is
    # absent because the condition that posts it cannot arise in the port's document: it is posted when a text
    # attribute the storage cannot map to an element is added, and the port's elements carry the whole
    # attributed string, so there is no attribute it cannot map. The effect says the condition, so a reader can
    # see what would have to change for the name to be there.
    entries.append(dict(
        api="NSTextContentStorageUnsupportedAttributeAddedNotification", kind="constant", introduced="15.0",
        minimum="6.0", status="absent",
        reason=("the notification is posted when an attribute the storage cannot map to an element is added, and "
                "the port's elements carry the whole attributed string: a paragraph is a range of the string and a "
                "list element is its marker and its contents, so there is no attribute the port cannot map and the "
                "condition cannot arise"),
        effect=("the name is not there: a lookup of it answers nil, and no notification of it is ever posted. What "
                "would have to change is the element model - an element that could not represent some attribute a "
                "caller put in the backing store - and the port has none"),
        source=SOURCE))
    entries.sort(key=lambda e: (e["kind"], e["api"]))
    with open(OUT, "w") as handle:
        json.dump({"framework": "UIKit", "entries": entries}, handle, indent=2)
        handle.write("\n")
    kinds = {}
    for entry in entries:
        kinds[entry["kind"]] = kinds.get(entry["kind"], 0) + 1
    print("  " + " ".join(f"{k}={v}" for k, v in sorted(kinds.items())))
    print(f"{len(rows)} rows of the group plus the port's own location type and one notification: "
          f"{len(entries)} entries")
    print(f"plus {len(values)} header-only values, which get no entry by registry/README.md:")
    for name in sorted({v["api"] for v in values}):
        print("  " + name)


main()
