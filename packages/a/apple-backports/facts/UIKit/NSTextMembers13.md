# Text members of iOS 13 and 14

Source: the host's own UIKit under Mac Catalyst (macOS 27.0), held against the backport by the `views13` group of
`tests/backports/host/uikit2` and `tests/backports/device/uirest.m`.

## showCGGlyphs

`-[NSLayoutManager showCGGlyphs:positions:count:font:textMatrix:attributes:inContext:]` draws the glyphs with the context's text
matrix set to the one given, the font of the name and size, and the fill colour of `NSForegroundColorAttributeName` or black, at the
positions, by `CGContextShowGlyphsAtPositions`. The release's layout manager draws with `showPackedGlyphs:...` and never calls this
one, so it is called by an application's own layout manager subclass, and `super` reaches the port. The glyph numbers are those of
the font, the same in a `CGFont` as in a `CTFont`.

## Hyphenation

`usesDefaultHyphenation` is NO until set and is kept. The text system of iOS 6 hyphenates nothing by default, so YES changes no line
break; the first YES says so once in the log.

## Replacing attributed text

`-replaceRange:withAttributedText:` of `UITextInput` is answered by the text view and the text field: the range's characters are
replaced in the attributed text, the runs of the new text are kept, and the caret is put after it, wherever the selection was, as the
host does (twelve statements, six selections in a text view and in a text field). A range outside the text is clamped.

## Constants

`NSCocoaVersionDocumentAttribute` is `CocoaRTFVersion`, `NSTextScalingDocumentAttribute` and `NSSourceTextScalingDocumentAttribute` are
`TextScaling` and `SourceTextScaling`, and the options `NSSourceTextScalingDocumentOption` and `NSTargetTextScalingDocumentOption` are
`SourceTextScaling` and `TargetTextScaling`. The release's importers and writers read none of them. `NSTrackingAttributeName` is
`CTTracking`; the attribute stays on the string and is read back, and the text is drawn without tracking, since the release's
CoreText has no tracking.

### Correction, iOS 13-14 band, 2026-09-23

`NSCocoaVersionDocumentAttribute` was registered `introduced: 13.0`, read off the SDK 16.4 header's `API_AVAILABLE` annotation, the
same trap `UIFontWidth*` already caught this band: header availability is when Apple published the symbol, not when it first exports
in a real binary. `tools/release-split.lua`, walking the full 6.1.3-18.0 cache ladder, found `_NSCocoaVersionDocumentAttribute`
actually first exports at iOS 9.0 (`UIFoundation.framework` of that release), five releases earlier than the header says, and
confirmed the value byte-for-byte: `CocoaRTFVersion`, the same string this port already carries. `introduced` is corrected to `9.0`.

This is not a duplicate-symbol risk for the armv7 6.1.3 target this package builds for - iOS 6.1.3 does not export the symbol at
all (checked directly against its own cache, not just against the header), so the port's definition is still the only one linking
in. It was a real risk for any deployment target from 9.0 up sharing the same source file as the four other, genuinely
never-native constants (`NSTextScalingDocumentAttribute` and the rest, "none" across the entire cache ladder): `band()` refuses to
link an object file whose symbols first arrive in more than one release for the release actually being built, so a 9.0+ deployment
build of the old, unsplit `NSAttributedString+Constants13.m` would have failed at link time (or worse, silently shipped a
now-redundant definition, if the exact release boundary this port checks against happened to round both up together). Moved to its
own object file, `NSAttributedString+Constants9.m`, so it drops out cleanly - reexported, not redefined - once the deployment
target reaches 9.0.

## Not carried

`+[NSTextAttachment textAttachmentWithImage:]` is absent: the release's `NSTextAttachment` holds no image, and its text views draw no
attachment.

## `-[NSTextList initWithMarkerFormat:options:startingItemNumber:]`, iOS 16.0

The release carries `NSTextList` itself, in UIFoundation (`objc.inventory` on 6.1.3), with `initWithMarkerFormat:options:` and
`startingItemNumber`. `UIKit/NSTextList+Init16.m` is those two in a row: the release's initializer, then the starting number set on the
list it made. It adds no state and draws nothing the release did not; the release's text views draw no list markers either way.
`objc.inventory` (`.agent-work/plan-and-analysis/b1314-flips/ladder-rest.log`): the three-argument initializer is not in 6.1.3 or 12.0 and
is in 16.0 and 18.0, the two-argument one is in all four. No 13-15 cache, so `introduced` stays the header's 16.0. Run on a device: the last section.

## `NSTextList`, the class

UIFoundation carries `NSTextList` from iOS 6.0 and exports it from 9.0 (`objc.inventory` and the exports of the shared caches of 5.1.1
to 10.3.4: none in 5.1.1, carried and not exported in 6.0 to 8.4.1, exported in 9.0 and later, `.agent-work/plan-and-analysis/b1314-catcheck/textlist-ladder.log`; the SDK's header says iOS 7.0). An
application that links the class does not start on a release that does not export it. `UIKit/NSTextList.m` exports the name as an
alias of `CharonNSTextList` (`charon_alias.h`, as for `NSTextTab`), which answers `+class` and `+alloc` with the release's class, so
`[NSTextList class]`, the lists made through it and the lists a paragraph style holds are one class. A category written on
`NSTextList` is attached by the library's loader (`attach.c`) to the release's class the alias names, where a release does not
export it, and to the exported class where one does. The gate refuses a category whose class the release neither exports nor
carries in an image the library loads (`unattached_categories` in `modules/apple/backports.lua`).

## On a device, iOS 6.1.3

On an iPad 2 of iOS 6.1.3 (2026-09-23), `tests/backports/device/textalias.m` against the gate's libraries (output
`.agent-work/plan-and-analysis/b1314-catcheck/textalias-ipad2-gate5.txt`), 15 of 15: `[NSTextList class]` and `[NSTextTab class]`
are UIFoundation's classes, what is made through the names is those classes, the three-argument initializer and
`+columnTerminatorsForLocale:` are on them from `libUIKitBackports.dylib`, no class of the library adds either by name, and the list
keeps its starting number while the two-argument initializer is still UIFoundation's own.
