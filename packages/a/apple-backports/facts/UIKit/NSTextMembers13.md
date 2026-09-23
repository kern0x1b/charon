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
alias (`charon_alias.h`, as `UIKit/NSTextTab.m` does for `NSTextTab`, carried and not exported before 7.0).

## The aliases, `NSTextList` and `NSTextTab`

`CHARON_ALIAS(Name)` defines `CharonName` and exports `_OBJC_CLASS_$_Name` and its metaclass as aliases of it, so what an
application links is `CharonName`. What the port does with it:

- The library's loader (`attach.c`, `charon_reparent`) makes `CharonName` a subclass of the release's class before the runtime
  first uses it: it writes the release's class into the second word of `CharonName`'s class and of its metaclass - `superclass`,
  after `isa`, in the class structure the compiler emits for every class, in the library's own data - and then has the runtime
  lay it out, which lays it out after the release's instance variables. The loader then checks it through the public
  functions: `class_getSuperclass` is the release's class and `class_getInstanceSize` is the release's. What else was weighed:
  - a superclass given at compile time, `@interface CharonName : Name`: the alias itself defines `_OBJC_CLASS_$_Name`, so the
    superclass would be the class itself; and without the alias the reference is a weak import, NULL on a release that does
    not export the class, and the runtime drops a class whose weak superclass is missing;
  - `objc_allocateClassPair(release, ...)`: it makes a class at run time, and no symbol can name it, while an application's
    subclass has its superclass bound at load to `_OBJC_CLASS_$_Name`, the alias; it would still inherit from the alias;
  - `class_setSuperclass`, the one public function that changes a superclass (deprecated from iOS 2.0 in the header): it
    works on a class the runtime has laid out already, and does not lay it out again. Measured by `textalias.m` on the test's
    own `NSTextTable` alias, which the runtime laid out before the loader: after `class_setSuperclass(CharonNSTextTable,
    NSTextTable)` its superclass is the release's class and its size stays NSObject's, 4 bytes, where the release's `NSTextTable`
    is 52, and the test's subclass has its first instance variable at offset 4, inside the release's (the same on iPhone4,1
    6.1.3 and iPhone2,1 6.0 in the emulator). So a subclass written of it has its instance variables where the release's
    are, and making one would write over them.
- So a subclass an application writes of the name inherits the release's class and has its instance variables after the
  release's; `+alloc` of the subclass makes the subclass.
- Sent to the name itself, the class methods of NSObject answer as the release's class does: `+class`, `+alloc`,
  `+allocWithZone:`, `+superclass`, `+isSubclassOfClass:`, `+instancesRespondToSelector:`, `+instanceMethodForSelector:`,
  `+instanceMethodSignatureForSelector:`, `+conformsToProtocol:`, `+respondsToSelector:`, `+methodForSelector:`, `+description`,
  `+hash` and `+isEqual:`; what the release's class answers beyond them is forwarded to it. Sent to a subclass, they answer as
  NSObject's do, and `+superclass` of a direct subclass is the release's class.
- What differs: the name's own object is not the release's class. `[Name isEqual:release]` is YES, `[release isEqual:Name]`
  is NO (NSObject compares the objects, and the release's class is not ours to change); `class_getName`, `object_getClass`
  and the other C functions of the runtime, given the linked name rather than `[Name class]`, answer `CharonName`; and
  `class_getSuperclass` of a direct subclass is `CharonName`, whose superclass is the release's class.
- ld64 merges a category written on the name in the library into `CharonName`. The loader gives the release's class each method
  of it the release's class lacks, and gives `CharonName`'s copy of each method the release's class has the release's
  implementation, so that a subclass reaches the same method a plain instance does.
- A class of an image loaded with the library that has a `+load` of its own and subclasses the name makes the runtime lay
  `CharonName` out on NSObject before the loader runs. The loader's check fails, it takes its write back, and the log says
  `apple-backports: CharonName was laid out before the library's loader ran`; the name still answers as the release's class,
  and that subclass does not inherit it.
- A category on a class the release carries without exporting, written without an alias, has a NULL class reference, and the
  loader has nothing to attach it to: the gate refuses it and names `charon_alias.h` (`unattached_categories` in
  `modules/apple/backports.lua`).

## Measured

`tests/backports/device/textalias.m`, 61 checks, built by `@addon/charon/daemon` (addon `v0.8.10`) against the package of commit
`dacc7278`, whose library code is the branch's last, and run by `xmake emulate`: 61 of 61 on an emulated iPhone4,1 of iOS 6.1.3
(10B329) and 61 of 61 on an emulated iPhone2,1 of iOS 6.0 (10A403) (`.agent-work/plan-and-analysis/b1314-catcheck/`
`textalias-emulate613.txt`, `textalias-emulate60.txt`). The emulator runs the release's own dyld, runtime and UIFoundation,
which is what the aliases and the loader depend on. The same subclass check answers YES for `NSTextList`, which the loader
put under the release's class, and NO for the test's own `NSTextTable`, laid out before the loader ran, so the check tells the
two apart. Device-unverified: not yet run on a device for this code; an earlier run on an iPad 2 (15 of 15,
`textalias-ipad2-gate5.txt`) was of the alias before it was a subclass.
