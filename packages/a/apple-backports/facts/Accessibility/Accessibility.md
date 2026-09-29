# Accessibility on a release that has the C library and not the classes

`libAccessibilityBackports.dylib` carries the first two groups of the Accessibility framework of SDK
26.2: the request and the feature-override session, the braille tables, and now the chart and data
classes of 15.0. Every registry entry of this framework points here.

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
thirteen.

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

**The band a chart object lands in is measured, not read from the header.**
`tools/release-split.lua` over the built objects answers 16.0 for all fourteen class symbols of
`CharonChartDescriptors.o`, while Apple's header and the corpus both say 15.0:

```
release-split: clean, every object file's symbols first-appear in one release (5 files, 26 symbols, 50 releases checked)
CharonChartDescriptors.o	_OBJC_CLASS_$_AXChartDescriptor	16.0
CharonChartDescriptors.o	_OBJC_METACLASS_$_AXChartDescriptor	16.0
```

The 16.0 is what the SDK the objects were compiled against can prove: its own interface file for the
16.0 Accessibility framework exports these names, and no earlier release on the held ladder is held with
a cache that does. That is the same rule the tool's own header describes - a header can name a later
release than the one that already exports the symbol - read the other way round. The consequence is the
one that matters and it is not a gap: `band()` keeps an object in every band whose release is older than
the object's own, so an object placed at 16.0 is carried on 6.1.3, 4.3 and 12.0 and is left out from
16.0 up, where the system has the class itself. The classes of 18.0 and 26.0 in the same library have
no export in that interface file at all and come out `none`, and are placed by the registry and the
header instead - which is why the two are named here and the 15.0 classes are not.

**Not transcribed yet, and the next groups of this framework are them**: `AXMathExpression.h` (fifteen
classes, 39 rows) and `AXSettings.h` (five functions and five notification constants, 7 rows).

`AXAudiograph.h` and `AXBrailleMap.h` are in 16.4 already and are byte-identical to 26.2's copies
(`shasum -a 256` of each pair agrees), so the chart group needs no Charon header at all.
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

## The chart and data classes of 15.0

The group is seven classes and the two protocols that declare an axis, of which the class
`AXLiveAudioGraph` is the one that asks for something; the other six are containers. An application
fills a container in and an assistive technology reads it back, and neither half has to reach anything
on this release, so the value each one keeps is the value it was given. Every rule below was measured against the host's own `Accessibility.framework` by
`tests/backports/host/accessibilitychart/run.sh`, which builds the same 206 questions against the
system's classes and against the port's - compiled under names the system does not use, so neither can
answer for the other - and compares the two outputs line by line. **193 of them are behaviour cases and
all 193 answer the same; 13 check a declaration** (the two protocols and their members, which come from
whichever header each side compiled against and are counted apart for that reason) **and there is no
declared difference left.** The case's own `expected-differences.tsv` is empty and says why, and the
summary line `run.sh` prints says which of the two kinds each case is:

```
=== the two answers: 206 cases a side (193 behaviour, 13 declaration), 0 declared to differ
cases read: 206 a side; declared differences: 0; undeclared or moved: 0
identical on all 193 behaviour cases: the system and the port answer the same
declaration cases: 13, which check a header and not the port's code
```

**A name and an attributed name are one value.** The header declares `title` and `attributedTitle` (and
`label`/`attributedLabel`, and `name`/`attributedName`) as two readwrite properties each. On the host,
setting either face leaves the other holding the same characters, and setting one to nil leaves the
other nil - measured on a chart, a data point, a series and both axis classes. The port keeps two
storage slots and its two setters write both, which is the smallest thing that keeps them in step.

**A data point value's two faces are independent, and are not the same rule.** The factory for a number
leaves the category **nil**; the factory for a category leaves the number **0**, not NaN and not a
raise. A write to one afterwards does not move the other: a number value given a category keeps 1.5, a
category value given a number keeps "cat".

**A nullable argument stays what it was given.** A data point built with the two-argument initialiser
answers nil for its y value, its additional values, its label and its attributed label. A chart given
an empty series answers an empty array, and the same chart given nil answers nil. A numeric axis given
nil gridline positions answers nil, and answers nil again after a set to nil.

**The two values no initialiser takes start where the host's start.** A chart's `contentFrame` is a zero
rectangle and its `contentDirection` is the zero case of its own enumeration, and both are set and read
back when a caller sets them.

**`-copy` is shallow, and which objects it shares was measured one field at a time.** The case asks
every copy whether it answers the very object its original does, and prints shared-or-copied for each -
the addresses stay out of the output and the question is the same on both sides. Measured on the host:
a copy of a chart, a series, a categorical axis, a numeric axis and a value shares its arrays, its axes,
its block and both faces of its name pair, and a copy of a data point shares the plain label and answers
a **new** attributed string. So four of the five copies hand their storage over, and the point's copy is
built through its own pair's setter, which is what makes the attributed string a new one.

That last rule was found by the identity probe and not by reading: the first version of this file said
the copies share, the case could not see whether they did, and when the probe went in it turned up four
copies in this port that rebuilt the attributed face through an initialiser where the system shares it.
All four are fixed, and a mutant per class now holds each of them.

### The two protocols, and how a caller gets their metadata

`AXChart` and `AXDataAxisDescriptor` are rows of their own in the registry, and what the port carries for
them is the declaration and the metadata: `modules/apple/backports.lua`'s `protocol_sources()` reads the
two `implemented` protocol rows and writes `AccessibilityBackportsProtocols15.0.m`, which names each one
so clang emits its metadata into that object. `Accessibility/CharonAccessibilityProtocols.h` is the
header that generated source imports, and it exists because without it the build stops on "file not
found" - the light guard says so by name.

The port implements **no member** of either protocol: they are declarations an adopter answers, and the
port has no class of its own that adopts them. What the case checks is that a caller can: it declares a
class that adopts both, gives it values, and asks it - `conformsToProtocol:` for each, its title, its
attributed title, the series count of the chart descriptor it was handed, and its own description. On the
port those answers come from the port's own protocol metadata, and on the host from the framework's.

The adopter is in **both** halves of the case, and that is the whole fix for a hole the first version of
this case had: the system's Accessibility image does not list `AXChart` in its protocol list, so with no
adopting class the name resolved on one side and not the other and four of the cases were comparing the
case's own file with itself. `AXDataAxisDescriptor` never had the problem - the system's own image names
it - and the case now has the adopter for both so the two halves are asked the same question. The port
half is also given the generated protocols object, because that object is part of what the port ships and
its absence would be a real defect; the host half is not, because the host's equivalent is the framework
it links.

The thirteen cases labelled `declaration.` are the ones that do not test the port's code: their members
come from whichever header each side compiled against, so a change to Apple's header moves them and
nothing under `packages/` can. They are counted apart from the behaviour cases in the summary line above,
so "193 answer the same" is a claim about the port and not about a header.

### The three fields the port's copies drop, because the system's do

The host's own `-copyWithZone:` drops three fields, and the port drops the same three. Measured twice on
the host: a chart set to direction 5 and frame (1, 2, 3, 4) and a numeric axis set to scale case 2, and
of the copies of those objects the host answers the zero case, the zero rectangle and the zero case
again, while every object-typed field of the same copies is carried - the title, the summary, the shared
series array, both axes, the additional axes, the gridline positions, the caller's own description
block. The three fields it loses are the three value-typed ones, and it loses the same three in both
runs.

**The policy of this framework is the system's behaviour, so a copy here answers the same.** A copy that
kept them would be a port that is better than the system, and that is a thing to decide on purpose and
record, not to arrive at by writing a careful copyWithZone:. What a copy that kept them would be good
for is written down in the ledger the coordinator keeps
(`.agent-work/handoffs/better-than-system-accessibility.md`): a port application that sets a chart's
content frame, copies the descriptor and reads the copy's frame would get the frame back here and a
zero rectangle on the device, which is a difference a port should not have introduced quietly.

What pins the parity is three mutants, one per field, each of which puts the field back into the copy
and has to turn that one case red. The three rows of `expected-differences.tsv` that used to declare
these differences are gone and the file says in its own lines why it is empty: a declaration could not
have held this, because a port that quietly started *agreeing* with the host would have passed a
"the two must not agree" check and told nobody anything about the parity the policy asks for.

### AXLiveAudioGraph, the one member of the group that asks for something

A live audio graph is drawn by an assistive technology, and this release runs none: the whole
Accessibility surface it holds is the preferences library above, and no publisher of a graph is in it.
The class is carried and `inert`, and so are its three class methods, each of which writes one line to
the log the first time it is used - the package's own say-once, so a second call is silent.

The class holds **no state**, and that is measured rather than assumed: the host's instance has no ivar
at all (`class_copyIvarList` over `AXLiveAudioGraph` returns none, and its instance size is 8, which is
the isa pointer and nothing else), and all three of its methods are class methods
(`class_getClassMethod` for each). No value is refused and no call raises, because the host does not:
it takes a value below the unit range, a value above it and a call after `+stop`, without complaint.
What the case compares for this class is the shape both sides can answer - the three class methods, the
instance size, the ivar count, that the calls survive - and the sound itself, which a program cannot
read, is not compared and is not claimed.

**The once-only part of the `inert` contract is held by a count, not by a comparison.** "Declared, does
nothing, and says so once in the log the first time it is used" is most of what the four `inert` rows
here claim, and a log line is not a value: the host writes none, because the system's three methods
publish sound. So the case calls each of the three members several times and prints how many times, and
`run.sh` counts the port's own log lines against exactly those numbers and fails if any member wrote
more than one:

```
say-once: +[AXLiveAudioGraph start] called 3 times, 1 line in the port's log
say-once: +[AXLiveAudioGraph updateValue] called 5 times, 1 line in the port's log
say-once: +[AXLiveAudioGraph stop] called 2 times, 1 line in the port's log
```

A mutant that takes the guard out of `CharonSayOnce.h` writes a line per call, and the run fails with
"the port wrote 3 lines for +[AXLiveAudioGraph start], and the case called it 3 times". That is what the
`inert` status now rests on rather than on a sentence.

## What the registry holds, and the rows it does not

**117 entries** are written. Of the 114 the Accessibility framework started with, 35 rows became
`implemented` with the chart group and one became `inert` (`AXLiveAudioGraph` and its three class
methods, which the registry now names one by one), two rows were **removed** rather than left `absent`,
and five rows were added that the registry had no answer for at all: the two protocols of 15.0 and the
three class methods of the graph. Fifty-five entries are `implemented`, four `inert` and 58 `absent`.

The two rows that were removed, and the one rule that took them out:

* **`AXNumericDataAxisDescriptor.range`** and **`AttributeScopes.accessibility`** are both Swift-only
  spellings. Neither exports a symbol, so neither can be an `implemented` row, and an `absent` row
  would be the registry claiming an answer it has not got. `range` is the Swift face of the
  `lowerBound`/`upperBound` pair - the Swift initialiser takes a `range` and the Objective-C one takes
  the two bounds, and no header of either the port's SDK or 26.2's declares a `-range` selector: the
  host answers `respondsToSelector:range` = 0, and the only "range" in either header is inside a
  comment. `AttributeScopes.accessibility` is a nested member of a Foundation Swift type that no header
  in the port's SDK tree declares; its seven members are the `UIAccessibilitySpeech*Attribute` constants
  of the **UIKit** family, so the scope's content is already another family's answer. Both are owed to
  the Swift module build, which is where a Swift-only surface belongs, and until then they are owed
  work rather than a registry row of any status.
* The same rule takes **36 other Swift-only spellings** out of this framework's rows: the Swift face of
  an Objective-C initialiser (`AXDataPoint.init(x:y:additionalValues:label:)`), a Swift getter label
  (`AXBrailleTranslationResult.inputIndex(forResultIndex:)`), and the whole `AttributeScopes` and
  `AttributeDynamicLookup` surface. A property row is named by one spelling in this registry, and these
  are not it; the accessibility of an attribute is reached through the Objective-C half.
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

Not run for the chart group: not on the device, not in the emulator, not through the generated call test.
The host differential and its eight mutants are what the group is held to here - each mutant changes one
line of the port's own source and has to be caught by the comparison, and each was shown to be caught,
with the line that caught it. The braille table group is at the same state: device-unverified, and the
package build that checks every band is what the delivery report quotes.
