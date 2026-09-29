# Accessibility on a release that has the C library and not the classes

`libAccessibilityBackports.dylib` carries the first group of the Accessibility framework of SDK 26.2:
the request and the feature-override session, and the braille tables. Every registry entry of this
framework points here.

## What the release has, measured

`tools/intents/measure-release-carries.lua` walks **every** library in a release's cache and prints a
control symbol, so "carries none" is a measurement and not a probe that could not look. Against the
**6.1.3 armv7** cache: 580 libraries, control symbol found.

```
the release carries 0 of 30, and does not carry 30
```

The same walk against 4.3 armv7 (398 libraries) and 3.0 armv6 (152 libraries) answers 0 of 30 on
both, with the control symbol found on both.

Zero, and yet the release has had Accessibility since iOS 3. What it has is the **C** library. Every
AX-prefixed export of every Accessibility library in the 6.1.3 cache, walked out of the cache's own
library list:

```
/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/AccessibilityUtilities  (190 AX symbols)
/System/Library/PrivateFrameworks/UIAccessibility.framework/UIAccessibility  (43 AX symbols)
/usr/lib/libAccessibility.dylib  (310 AX symbols)
total AX-prefixed exports across Accessibility libraries: 543
```

All 310 exports of `libAccessibility.dylib` are its `AXS*`/`kAXS*` preference surface - 310 of 310
match that prefix, and none does not - and **no** export is named as the public C API: zero of the 543
match `_AXUIElement`, `_AXIsProcessTrusted`, `_AXValue`, `_AXError`, `_AXObserver`, `_AXMessaging`,
`_AXNotification`, `_AXRuntime` or `_AXMakeProcessTrusted` at the start of a name. Two exports contain
the string `AXUIElement` inside a longer private name in `UIAccessibility`, and neither is that API.
The braille names that are there are VoiceOver's braille *display settings* - a table identifier
preference and its siblings - not the braille table API of 26.0.

So this framework is two things stacked: a preferences library the release already answers for, and
thirty Objective-C classes the SDK of 26.2 declares on top of it, of which this delivery carries
six.

That is why no band needs a straggler here: nothing in either group is a class the release exports,
so every band builds the library whole and `tools/intents/measure-group.lua` - the check that found
the `INPaymentMethodResolutionResult` red - has nothing to name for Accessibility.

## The six headers 16.4 does not have, and what this tree declares

26.2 ships **thirteen** Accessibility headers and iPhoneOS 16.4 ships **seven**. The six that are new
to 16.4 are `AXRequest.h`, `AXMathExpression.h`, `AXBrailleTranslator.h`, `AXFeatureOverrideSessionManager.h`,
`AXSettings.h` and `AXTechnology.h`. Three of them are already transcribed in
`Accessibility/CharonAccessibility.h`: the request, the feature-override session and the braille
classes, and with them `AXTechnology` - Apple's own `NSString *const` typedef, whose nine constants are
externs, spelled out because a backport writes the declaration itself. One spelling is worth recording
because it cost a compile and would cost the next person the same: an ivar of `AXTechnology` is a
*const pointer* and can never be assigned, so the class's storage is an `NSString *` and the property's
accessor answers it unchanged.

**Not transcribed yet, and the next groups of this framework are them**: `AXMathExpression.h` (fifteen
classes, 39 rows) and `AXSettings.h` (five functions and five notification constants, 7 rows).

`AXAudiograph.h` and `AXBrailleMap.h` are in 16.4 already and are byte-identical to 26.2's copies
(`shasum -a 256` of each pair agrees), so the chart and braille-map groups need no Charon header at all.
`AXCustomContent.h` is in 16.4 too but is not the same file: 26.2's copy adds six lines inside
`AXCustomContentProvider` - a block-returning typedef, an `@optional` marker and the block property -
so that one member needs a Charon header of its own, as a protocol **category** and not as a second
declaration of the protocol.

This matters mechanically and not only for the compiler. A name no release exports and no implemented
registry row places is *unplaced*, and `modules/apple/backports.lua`'s `misplaced()` then refuses the
object that defines it with "no band can hold it". A class the SDK's own header declares is placed by
that header's availability annotation, read out of a clang AST dump of the source being compiled by
`introduced_version()`. Measured for the three headers above, compiling one file per name against the
16.4 SDK with `-Xclang -ast-dump -Xclang -ast-dump-filter`:

```
AXLiveAudioGraph   |-AvailabilityAttr <col:43, col:84> ios 15.0 0 0 "" "" 0
AXChartDescriptor  |-AvailabilityAttr <col:43, col:84> ios 15.0 0 0 "" "" 0
AXCustomContent    |-AvailabilityAttr <col:43, col:84> ios 14.0 0 0 "" "" 0
AXBrailleMap       |-AvailabilityAttr <col:43, col:84> ios 15.2 0 0 "" "" 0
```

The annotation has to be on the `@interface`, not on the `@implementation`: the same annotation above an
`@implementation` produces no `AvailabilityAttr` on the implementation node, which was measured with
the same dump. This is also how the 27 `inert` class rows elsewhere in this registry are placed, so an
`inert` class the release lacks is not a special case.

## The three walls, and what each answers

**A request is the system's.** `+[AXRequest currentRequest]` is the request the system's assistive
technology is serving, and `technology` is the one serving it. No assistive-technology service holds a
request on this release, so `+currentRequest` is **nil** and the class is the container an application
keeps its own request in: `-charon_withTechnology:` builds one, the coding and the copy carry it, and
`+currentRequest` says there is none.

**A feature override is a service.** `beginOverrideSessionEnablingOptions:disablingOptions:error:` is
how an application asks the system to turn grayscale on, or Voice Control on, for a while. The system
that does it is not on this release, so the manager answers **nil with
`AXFeatureOverrideSessionErrorUndefined`** - the header's own name for a session that could not be
begun for no more specific reason, and there is no more specific one: there is no service, so there is
nothing to be entitled to, nothing already active and nothing registered under a UUID.
`endOverrideSession:` answers NO for the same reason, and a session that cannot exist is not invented so
that the call has something to end.

**A braille table is Apple's data.** `AXBrailleTable` is a provider's dot patterns, and
`AXBrailleTranslator` maps print text onto the table it is given. The table the system installs is not
on this release, so `+supportedLocales` is an **empty set**, the two other sets are empty, and
`+defaultTableForLocale:` is nil - which is what makes the translator's answer honest rather than
invented: a translation of nothing is the input with **no cells**, and the location map is empty
because no cell was produced. Both directions answer that way, the second without guessing print text
out of dot patterns. A table an *application* builds is real and is kept, coded and copied.

## What the registry holds, and the rows it does not

**114 entries** are written, of the 361 rows the corpus names. The rest are three kinds of row, and
all three are counted here rather than written as claims nothing checks.

* **A Swift-only spelling** is not a row this registry can answer. There are 38 of them in this
  framework: the Swift face of
  an Objective-C initialiser (`AXDataPoint.init(x:y:additionalValues:label:)`), a Swift getter label
  (`AXBrailleTranslationResult.inputIndex(forResultIndex:)`), and the whole `AttributeScopes` and
  `AttributeDynamicLookup` surface. A property row is named by one spelling in this registry, and these
  are not it; the accessibility of an attribute is reached through the Objective-C half.
  Two of the 38 are named here because they are the ones a reader is most likely to look for:
  `AXNumericDataAxisDescriptor.range` is the Swift face of the `lowerBound`/`upperBound` pair - the Swift
  initialiser takes a `range`, the Objective-C one takes the two bounds, and no header of either the
  port's SDK or 26.2's declares a `-range` selector (the host answers `respondsToSelector:range` = 0, and
  the only "range" in either header is inside a comment) - and `AttributeScopes.accessibility` is a
  nested member of a Foundation Swift type that no header in the port's SDK tree declares, whose seven
  members are the `UIAccessibilitySpeech*Attribute` constants of the **UIKit** family. Both are owed to
  the Swift module build, which is where a Swift-only surface belongs. Neither is left as an `absent`
  row: that status would be the registry claiming an answer it has not got.
* **Four names the corpus gives twice** - a generic class's property once per instantiation
  (`AXChartDescriptor.additionalAxes`, `AXChartDescriptor.xAxis`, `AXNumericDataAxisDescriptor.gridlinePositions`,
  `AXBrailleTable.language`) - and two entries may not share a name, so one spelling is the row.

The **eleven Objective-C C functions** the corpus lists under this framework are not dismissed with a
sentence, because the rule that covers them is not the same rule twice. Eight of them are the framework's
own C surface that a backport has no reason to supply, and `registry/README.md` is right that a header's
own function is the header's own call. Three are the subject of the next groups and are named in the
plan for them: the two pairs of settings and the two constants, where the port **does** have to supply
the symbol, because a port application cannot call a function the release has no export of. The five
already answered are the two settings pairs of 17.0, the non-blinking pair of 18.0 and the two pairs of
26.1; the six still unanswered are `AXAssistiveAccessEnabled()`, `AXOpenSettingsFeature()`,
`AXNameFromColor()` and the three hearing-device functions, and each of them has a call written down for
it (D for the five that read a device or a service the release lacks, P for the one that is a pure
function of a colour).

## What the braille comparison measured, and the defect it found

`tests/backports/accessibility/braille-differential.sh` builds **two programs and diffs them**, because
one binary cannot hold both implementations: the system's three braille classes and the port's have the
same names, and renaming either renames the system's declaration. Two runs, the forward and the back,
per case.

The port's forward translation is the standard's, measured:

```
abcxyz        ⠁⠃⠉⠭⠽⠵
ABC           ⡀⠁⡀⡀⠃⠉
123           ⠼⠃⠉⠙
0123456789    ⠼⠁⠃⠉⠙⠑⠋⠛⠓⠊⠚
,;:.-!?       ⠂⠆⠒⠲⠤⠖⠦
Hello, World! 42.  ⡀⠓⠑⠇⠇⠕⠂⠀⡀⠺⠕⠗⠇⠙⠖⠀⠼⠑⠉⠲
```

The capital sign is doubled for the run after the first capital, and the number sign is written once
for a run of digits, which is the standard's own rule for both.

**The host answers nil for every case.** Its `AXBrailleTranslator` returns nil when it is given a table
built through `-[AXBrailleTable initWithIdentifier:]`, because a table's dot patterns are a provider's
data and this host has none installed for one. So on this host **the system is not an oracle for a
hand-built table**: the comparison's finding is that the oracle is unavailable here, not that the two
implementations agree. A host with an installed braille provider is where that finishes.

**One defect the comparison found, and this delivery does not fix:** the back-translation's number sign
does not keep its scope across a run of digits, so `123` comes back `2cd` where the standard says `123`.
The forward translation of the same input is right.

## What is not measured here

Not run: not on the device, not in the emulator, not through the generated call test. Every entry here is
**device-unverified**, and the package build that checks every band is what the delivery report quotes.
