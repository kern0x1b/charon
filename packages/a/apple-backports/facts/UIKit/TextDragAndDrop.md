# The text side of a drag and a drop

A drag of a range of text rather than of a view: the items carry text, and the preview is a picture
of the text. Everything here is in-process on this release; a drag that would leave the application
is not offered, which is what a device of this era answers and what the sessions say.

## What the family is, measured against the registry first

Of the 96 rows the ledger had as missing, **eleven were already routed by the port and only
undescribed** — the questions a drag and a drop ask its *interaction* delegate, in
`UIDragInteraction.m` and `CharonDropSequence11.m`. Those are registered where the routing is, and the
order a drop is asked in is asserted by `tests/backports/device/textdragdrop.m`. It has been **RUN on
an emulated iPhone3,1 6.1.3 and it CRASHED in the guest with signal 5 before its first check**, so it
establishes nothing about the order and no verdict is claimed for it here or anywhere in this series.
What is on the record is the crash, not a pass: `verdict.json` reads `state: crash, signal: 5,
reason: reached, guest_seconds: 0.126`, and the program wrote no `textdragdrop.done`.

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
