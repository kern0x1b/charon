# The text side of a drag and a drop

A drag of a range of text rather than of a view: the items carry text, and the preview is a picture
of the text. Everything here is in-process on this release; a drag that would leave the application
is not offered, which is what a device of this era answers and what the sessions say.

## What the family is, measured against the registry first

Of the 96 rows the ledger had as missing, **eleven were already routed by the port and only
undescribed** — the questions a drag and a drop ask its *interaction* delegate, in
`UIDragInteraction.m` and `CharonDropSequence11.m`. Those are registered where the routing is, and the
order a drop is asked in is asserted by `tests/backports/device/textdragdrop.m`. It has been **RUN on
an emulated iPhone3,1 6.1.3, both halves, and both CRASHED in the guest with signal 5 before the
first check** -- `verdict.json` reads `state: crash, signal: 5, reason: reached, guest_seconds: 0.366`
-- and the program wrote no `textdragdrop.done`, so the device half asserts nothing about the order
and no verdict is claimed for it here or anywhere in this series.

**What did run is the host-side half**, and it is the half that matters for what the mutant is: the
run generates the mutant from the live source, stops with a non-zero exit if `cmp` says the result is
identical, and prints the diff when it is not:

    cmp: the mutant differs from the source, as it must
    -    if ([delegate respondsToSelector:perform])     # the drop first, as the header has it
    +    if ([delegate respondsToSelector:preview])     # the preview first, the mutant

That is what found the defect: the live source had the preview before the drop, which is the order
`UITextDropping.h` puts the other way round, so the fixture and the source were the same wrong thing
and the mutated half was installing the unmutated source. The source is now the header's order, and
the fix is argued from the header and not from a gate that cannot run.

The rest are the text family proper: the two request types, the text delegates, the droppable and
draggable protocols' properties, the paste configuration, and the spring-loaded interaction. **Most
of those are protocols, not classes**: `UITextDragRequest`, `UITextDropRequest`, `UITextPasteItem`,
`UITextPasteConfigurationSupporting` and the three spring-loaded protocols are all `@protocol` in the
SDK. Only `UITextDragPreviewRenderer` is a class in the family, and it is built.

## What the renderer differential does and does not show

The differential in `tests/backports/host/renderer-differential/` compares the port's renderer with the
system's own in one process, and it is a gate: the clean pair must agree and the no-condition mutant
must not, and the script exits non-zero on either.

**Its oracle is degenerate, and that limits what it proves.** In a headless Catalyst process the
system's renderer produces no geometry at all: every rect it reports is empty (`null=0 empty=1`), every
shape record is the same, and no picture is drawn. So the comparison establishes that the port agrees
with the system on empty rects, and nothing about rects with extent. One case now puts a null rectangle
on the record so that all three shapes are named in the logs. What is **reasoned and not measured** is
that the guard is right for a null rectangle, because it tests `CGRectIsEmpty` and a null rectangle is
empty by definition. A case where the host produces geometry needs a laid-out text view in a window,
which is the emulator's job and not this harness's.

## The renderer measures with the release, not with itself

`UITextDragPreviewRenderer` is given a layout manager and a range, and the three rectangles it
reports are the ones TextKit already holds for those glyphs: the bounding rectangle of the range and
the used rectangle of the line fragments at each end, from
`-lineFragmentRectForGlyphAtIndex:effectiveRange:`. The picture is drawn by asking that same layout
manager to draw its glyphs, each line fragment in its own place, so the text in the image is where
the text is in the view. `adjustFirstLineRect:bodyRect:lastLineRect:textOrigin:` moves the three by
the text's origin for a preview drawn where the text is not already.

A range of no glyphs, or a renderer with no layout manager, has no picture: the answer is `nil`, not
a blank image, because a blank picture is a picture and would be drawn.

## The seams, stated

- **`UITextDropPosition` is not a type in the SDK.** The header's `dropPosition` is a
  `UITextPosition *`, the caret or a range in the text. An earlier draft of this family wrote a
  `UITextDropPosition` of its own, which no header declares; it is gone rather than shipped.
- **The text delegates' questions are carried by the protocols, and nothing calls them yet.** A
  `UITextDraggable` is told which items a drag carries, and a `UITextDroppable` is asked what a drop
  would do, by a text view that implements the protocol. A release with no text drag and drop has no
  such caller, so these are carried surface rather than routing; what routes today is the interaction
  delegate sequence above, and that is the part with an emulator test.
- **The paste configuration is the same shape**: `UITextPasteConfigurationSupporting` and
  `UITextPasteItem` are protocols an application adopts to say how a paste behaves, and the port's
  pasteboard is the transport. Nothing in this file changes that, and the rows are described as the
  surface rather than as a mechanism that runs without a caller.

## Header reachability, which cost an hour

Every header of this family is behind the SDK's own guard

    #if (defined(USE_UIKIT_PUBLIC_HEADERS) && USE_UIKIT_PUBLIC_HEADERS) || !__has_include(<UIKitCore/…>)

so a translation unit that includes only the umbrella header sees none of it, and a class written
against a name the header does not declare compiles as a root class and the gate says so later. The
check that matches the build passes `-DUSE_UIKIT_PUBLIC_HEADERS=1` and the lift's vfs overlay; that
is what `/tmp/checkbuild.sh` now does for this family.


## What this series adds, counted

The count is 19 registry rows, all in `registry/UIKit/dragdrop.json`, which goes from 81 entries to
100. It is measured with

    git diff 1924aeaa2..HEAD | grep -c '^+.*"api"'

and it is 19, not the 45 an earlier report of this series claimed. The 45 was a sum of three
different things across three different deliveries — the eleven interaction delegate rows, the eight
renderer rows, and rows from a neighbouring family that this series never touched — added together as
though they were one. They were not. The eleven and the eight are inside the 19; the rest were never
part of this series, and saying so is the correction.

What the 19 are, by file and kind:

- 11 `UIDragInteractionDelegate` and `UIDropInteractionDelegate` questions the port already routed
  and this series registers;
- 8 `UITextDragPreviewRenderer` members: three methods and the five properties.


## Who owns these members, and who owned them wrongly

The 26.2 SDK declares `textDragDelegate`, `textDragInteraction`, `textDragActive`,
`textDragOptions`, `textDropDelegate`, `textDropInteraction` and `textDropActive` on the
**`UITextDraggable` and `UITextDroppable` protocols**, and `UITextField` and `UITextView` adopt those
two protocols in their class extensions (`UITextField.h:116`, `UITextView.h:329`). **No class declares
them, and `UIView` has neither protocol.**

The first version of this put a category on `UIView`, so thirteen members were built on a class that
has no claim to any of them, seven registry rows on `UIView.*` were the only rows that existed, and
the stack's 6.1.3 registry check named the built-but-unregistered members. The file's own name —
`UITextView+TextDragDrop11.m` — had been saying which class they belonged to all along.

They are on **`UITextView` and `UITextField`**, one row per class per member: fourteen rows, with the
two custom getters spelled as the header spells them, `isTextDragActive` and `isTextDropActive`, after
the `UIImage.isHighDynamicRange` convention, and the setters follow from the property row rather than
being rows of their own. The adaptor's control is typed `UIView<UITextDraggable, UITextDroppable> *`,
so the members are reached through the protocol the SDK declares them on.

**The seven interim `UIView.*` rows are removed**, and their removal is intended: they described
members on a class that has neither protocol, and the same check is what named them. Where a control
has no interaction the answer is nil, which is what the header's nullable properties allow and what
`isTextDragActive` and `isTextDropActive` then report as no.
