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
The release carries the class without exporting it (the gate's import check names `_OBJC_CLASS_$_NSTextList` as a weak import NULL on
6.1.3), and the library's loader (`attach.c`) skips a category whose class reference is NULL, so the category alone would never reach
the class on iOS 6. `CharonTextListInit16` in the same file adds the method to `objc_getClass("NSTextList")` in its `+load`, which runs
before the loader, when the class lacks it; the category stays for the registry and for a release that exports the class.
`objc.inventory` (`.agent-work/plan-and-analysis/b1314-flips/ladder-rest.log`): the three-argument initializer is not in 6.1.3 or 12.0 and
is in 16.0 and 18.0, the two-argument one is in all four. No 13-15 cache, so `introduced` stays the header's 16.0. Run on a device: the last section.

## On a device, iOS 6.1.3

On an iPad 2 of iOS 6.1.3 (2026-09-23), a process of the band's own (`.agent-work/runs/b1314-live/main.m`, output `run4-all.txt` beside it) loaded the gate's `libUIKitBackports.dylib` and checked the three-argument `NSTextList` initializer: the class answers it - added by name, since 6.1.3 does not export the class - and the list has the starting number, while the two-argument initializer is still UIFoundation's own.
