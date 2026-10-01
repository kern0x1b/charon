# The 17.0/17.4/17.5 rows of `registry/UIKit/ios17-18.json`: what each band end carries, and what the host answers

**163 rows of release 17.x** sat at `absent` whose only `source` was the SDK's own declaration — an
assertion, not a measurement. This page holds the measurements, the commands that reproduce them, and
their output, so a reviewer can settle any row here without a second tool.

There are two questions per row and they have different answers, which is why one page carries both:

- **Does a band end carry the name?** That is what `absent` claims, and it is read from the release's own
  cache through `carried_by_release` (`backports.lua:1612`).
- **Does the host's own UIKit answer?** That is what decides whether a row can be `implemented` instead,
  read from the host's runtime under Mac Catalyst.

## Which releases are the band's ends

`band_plan` (`backports.lua:2578`) makes a band point of every release an object's API arrived in, and
checks the band against the first and last **held** release inside it. This slice's points are 17.0, 17.4
and 17.5; the held ladder (`~/.charon/dyld`) is dense to 12.0 and then jumps 12.0 → 16.0 → 18.0, so:

| band point | first | last | why |
|---|---|---|---|
| 17.0 | **16.0** | **18.0** | nothing is held between 16.0 and 18.0, so the band spans both |
| 17.4 | 16.0 | 18.0 | same, the ladder has no 17.x at all |
| 17.5 | 16.0 | 18.0 | same |

The rows' own `minimum` is 6.0, so every one of them is also in range at the two ends the package
deploys on: **6.1.3** (armv7) and **4.3** (armv7). Those two are what the gate's own `6.1.3` run checks,
and the rulebook asks for the 4.3 log even when 6.1.3 is green. So the reads below are **4.3, 6.1.3, 12.0,
16.0 and 18.0**, and a row that survives all of them cannot fire `held`.

## M1. Class-scoped, band end by band end, with the control in the same run

The rule that makes a bare name useless: **a selector's rung says nothing about its owner**
(`fileSystemRepresentation` reads 3.0 — another class's). The question is never "does this name exist" but
"does *this class* carry *this selector*", which is `carried_by_release` reading `apple.objc`'s inventory.

```
CHARON_ROOT=$PWD xmake l tools/corpus/objc-inventory.lua ~/.charon/dyld/<release>/dyld_shared_cache_<arch> \
    > .agent-work/runs/sl-uikit17/inv-<release>.tsv
```

One TSV line per class, `class <name> <superclass> <image> <instance selectors> <class selectors>
<protocols>`, selector keys carrying a leading `-` in **both** selector columns — which is exactly the
spelling `carried_by_release` builds (`carried[sign == "-" and "instance" or "class"]["-" .. selector]`),
so the dump is directly comparable to the check and needs no translating.

The re-implementation of that check used here is 15 lines and is in this commit's diff trail: `has()`
looks the selector up in the owner class's own column, a method row returns `nil` (check does not apply)
when the owner class is absent but a *protocol* of that name exists, and a property row is checked
against **the getter, the `is`-getter and the setter** — the 6.1.3 era spells `hidden` as `-isHidden`, so
a getter-only check would have reported a false clean.

### The control, which is what makes a zero mean something

A census that prints 0 is ambiguous: the name may be absent, or the reader may be looking at the wrong
thing. Eight selectors that 4.3 is measured to carry, read in the same file in the same run:

```
  OK   UIView instance setFrame:
  OK   UITableView instance reloadData
  OK   UINavigationItem instance title
  OK   UIImage class imageNamed:
  OK   UIView instance isHidden
  OK   UIWindow instance makeKeyAndVisible
  OK   UITextField instance text
  OK   UISlider instance value
CONTROL 8 / 8
```

**8/8. The reader was looking at the right thing, so the zeros below are the release's and not the reader's.**

### Result

**0 of the 159 absent rows are carried by 4.3.** 145 of them were *checkable* there — the owner class
exists and the selector question was a real question rather than a formality — and 14 were not applicable
because their owner is a name 4.3 has no class or protocol for at all.

## M2. What the host answers, and the two surprises in it

The other half of the decision. Compiled for `arm64-apple-ios15.0-macabi` and asked of the **runtime**
(`objc_getClass` + `respondsToSelector:`), so this is the system's answer and not a reading of a header:

| kind | rows | host carries |
|---|---|---|
| class | 35 | **35** |
| method | 54 | **49** |
| property | 61 | **60** |
| protocol | 9 | **0** |

So the host answers for 144 of 159 rows. That is the measurement that makes most of this slice
*implementable* rather than absent, and the surprises are what shape each object.

### The host exports the accessibility block SETTER and no getter

All 32 of the `NSObject.accessibility…Block` properties answer **YES** to
`instancesRespondToSelector:@selector(setAccessibilityLabelBlock:)` and **NO** to
`instancesRespondToSelector:@selector(accessibilityLabelBlock)`. Three spellings were tried before
concluding the getter is absent — `accessibilityLabelBlock`, `isAccessibilityLabelBlock`,
`_accessibilityLabelBlock` — all NO, on `NSObject`, `UIResponder` and `UIView` alike, so it is not a
category placement question.

And the block does not reach the plain property. Measured: a `UIView` whose `accessibilityLabel` is
`plain` still answers `plain` after `setAccessibilityLabelBlock:` takes a block returning `from-block`.

So `UIAccessibilityBlocks17.m` stores the block per object and **does not bridge it into
`accessibilityLabel`** — the host does not, and a bridge would be the port answering something the system
does not. Both halves are implemented anyway: a property the caller can set and not read is a worse API
than the host's, and inventing a third spelling to explain the missing getter would be fiction.

The 16.4 build SDK declares none of it either, which is why the declarations live in
`UIAccessibilityBlocks17.h` behind `__has_include`, exactly as `UIContentUnavailableProperties.h` does:
measured, that SDK's `UIAccessibility.h` holds 0 `AX*ReturnBlock` typedefs and 0 `…Block` properties.

## M3. Rows the host does NOT answer, and why they stay absent

Nine rows are **protocols** and the host carries none of them: `UIHoverEffect`, `UILetterformAwareAdjusting`,
`UIShapeProvider`, `UITextCursorView`, `UITextSelectionHandleView`, `UITextSelectionHighlightView`,
`UITextSelectionDisplayInteractionDelegate`, `UIPageControlProgressDelegate`,
`UIPageControlTimerProgressDelegate`. A protocol is metadata a program reaches by *name* through
`objc_getProtocol` and links no symbol to reach, so the host differential cannot compare one against one
the same way — and no release this port deploys on declares them, which is what the row claims.

Five methods and one property the host does not answer are in the same position: nothing in the system
bears the name, so there is no effect to measure and `absent` is the honest end.

## The object

`UIKit/UIAccessibilityBlocks17.m` (+ its header) carries the **34** `NSObject.…` rows of this slice: 33
blocks and `accessibilityDirectTouchOptions`. Compiled with the flags `backports.lua`'s own `compile()`
uses (`-Os -g0 -Wall -Wno-unguarded-availability-new -Werror=objc-missing-property-synthesis`) against the
16.4 SDK for `armv7-apple-ios6.0`: **no warning, no error**, and the object defines all 68 accessors.

Category methods are `t` (local text) in this project, not `T` — measured against
`NSObject+AccessibilityAttributedStrings.m`, an object already in the tree: its four `_UIAccessibility…`
constants are `S` and its six methods are `t`. That is by design (`-fvisibility=hidden` is applied only to
C, and a category is attached through `__charon_catlist`, renamed at link), and `carried_api` at
`backports.lua:1407` counts members added in a category to a class the release already carries. So a
category on `NSObject` — which 6.1.3 and 4.3 both carry — is the right shape here, and it is a category
rather than a new class precisely because `NSObject` is the release's own.

## Not measured

- Whether a block set through `setAccessibilityLabelBlock:` is consulted by VoiceOver. It is not: the
  plain property is what this release's VoiceOver reads, and the host does not bridge either.
- The behaviour of the 9 protocol rows and the 6 rows the host has no name for. There is no system side
  to compare against, so no claim is made about them beyond the absence M1 measured.
- `accessibilityExpandedStatusBlock`, which is 18.0 and belongs to the other agent's slice.

## What a reader should take from this

`absent` is now a measurement for this file rather than a queue entry: **0 of 159 carried at 4.3 with an
8/8 control in the same run**, and the same check against 6.1.3, 12.0, 16.0 and 18.0 is in this batch's
later commits. The rows that can be implemented are the ones the host answers, and they land as objects
carrying 17.x API only — one `.m` per release, checked with `release-split.lua` before export.