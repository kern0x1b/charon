# The adapters of the text system, iOS 7 to 12

Up to iOS 6 the text system of UIKit is the Mac one in UIFoundation - `NSTextContainer`, `NSLayoutManager`, `NSTextAttachment` and
`NSParagraphStyle` are there and lay out and measure text; iOS 7 renamed some of what they answer and added some. This batch names
the iOS 7 to 12 spellings over what the release has.

Source: the host's own UIKit for the defaults and the answers, recorded by `host/textsystem7` and read back on the iPad 2 by
`device/textsystem7.m`; the shared cache of iOS 6.1.3 for the selectors the release has (a walk of its classes: 255 selectors on
`NSLayoutManager` alone).

## What the port does as the system does

`NSTextContainer` takes `-initWithSize:`, `-size` and `-setSize:` for the release's container size, and answers
`-lineFragmentRectForProposedRect:atIndex:writingDirection:remainingRect:` with the release's line fragment for that sweep. The
attachment's `contents` and `fileType` are the data and the type it was made with, and `setFileWrapper:` takes the wrapper's contents.
`NSLayoutManager` takes `-CGGlyphAtIndex:`, `-enumerateLineFragmentsForGlyphRange:usingBlock:`, the enclosing rects of a glyph range,
`-propertyForGlyphAtIndex:` (null, control character and non-base character, worked out from the character, since the release keeps
only a not-shown flag) and `-getGlyphsInRange:glyphs:properties:characterIndexes:bidiLevels:`. The release measured a container's used
rectangle only once something had asked for its layout, and answered an empty one before; `-usedRectForTextContainer:` now lays the
container out first, as iOS 7's does. A container with exclusion paths or a line limit is no longer simple, as on the system, and lays its lines round the paths (`NSTextContainerExclusionPaths.md`). The paragraph style's `allowsDefaultTighteningForTruncation` (on, as the host has it) and
`lineBreakStrategy` are kept by the style, copied with it, held in its equality and read back.

## What it cannot do

The release's layout knows no line break mode of a container, no tracking of a text view, no tightening and no line
break strategy: those are kept and read back and the text is laid out without them (`inert`). The attachment's `bounds` is kept and the
release lays an attachment out at the size of its image. `-truncatedGlyphRangeInLineFragmentForGlyphAtIndex:` answers no range, since the
release does not say what it truncated. A paragraph style's two properties are not in its archive, and a style that the release copies
inside itself, out of its own code, loses them.

The library changes the release's own methods only where the release lacks the iOS 7 spelling of the same class, told when it loads and before
its own categories are attached: the release's `-usedRectForTextContainer:` and `-isSimpleRectangularTextContainer`, the copy and equality
of a paragraph style, and `-[NSString drawInRect:withAttributes:]`.
