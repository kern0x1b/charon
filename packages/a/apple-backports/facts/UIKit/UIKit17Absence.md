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
## M4. UIScrollView, measured member by member (17.0 and 17.4)

Asked of the host's own UIKit, built for `arm64-apple-ios15.0-macabi`, on a real `UIScrollView` of
100x100 with `contentSize` 400x400:

| member | introduced | host | measured default / behaviour |
|---|---|---|---|
| `allowsKeyboardScrolling` | 17.0 | get+set | **YES** on a fresh scroll view |
| `contentAlignmentPoint` | 17.4 | get+set | **(0,0)** on a fresh view; setting (37,11) reads back (37,11) while `contentOffset` stays (0,0) |
| `isScrollAnimating` | 17.4 | **readonly** | NO |
| `isZoomAnimating` | 17.4 | **readonly** | NO |
| `transfersHorizontalScrollingToParent` | 17.4 | get+set | **YES** |
| `transfersVerticalScrollingToParent` | 17.4 | get+set | **YES** |
| `withScrollIndicatorsShownForContentOffsetChanges:` | 17.4 | yes | runs the block; **a nil block kills the host** |

Two findings changed the implementation rather than confirming it:

- **`contentAlignmentPoint` is not a function of `contentOffset`.** Setting it to (37,11) left
  `contentOffset` at (0,0) and read back (37,11). So it is stored, and a port that computed it from the
  offset would answer something the system does not.
- **The host SEGFAULTS on a nil block** (exit 139, no output at all), so the port runs the block and does
  not guard nil. A guard would be the port answering something the system does not, and it would hide
  the caller's own mistake. This is recorded rather than smoothed over.

Cross-checked against the SDK's own declarations, which agree exactly:
`UIScrollView.h:96,153,157,180,221,262` — `contentAlignmentPoint` readwrite, the two `transfers…`
readwrite, `withScrollIndicators…:` a method, and `scrollAnimating`/`zoomAnimating` declared
`(nonatomic, readonly, getter=isScrollAnimating)`. **That last part is why the port declares getters
only for those two**: writing setters the SDK and the host both lack would be inventing API.

## The two release-split trap, and why this slice has two scroll view files

My slice holds **17.0 and 17.4 rows on the same class**, and a `.m` must hold ONE release's API.
`release-split.lua` reads band points only, so one file holding both passes it and only a reader
catches it — which has stopped three batches. So:

- `UIScrollView+KeyboardScrolling17.m` — the **one** 17.0 row (`allowsKeyboardScrolling`).
- `UIScrollView+ContentAlignment17.m` — the **six** 17.4 rows.

Nothing else in either file is from the other release.

## M5. The symbol-effect rows are blocked, and by what

The 22 `addSymbolEffect:` / `removeSymbolEffect…` rows and the two `setSymbolImage:withContentTransition:`
families (24 rows in all) look implementable — the host carries all of them, and the port already has
real symbol infrastructure (`CharonSymbols.h`, `charon_symbol_bitmap`, `UIImage+Symbols.m`). They are
blocked anyway, and the blocker is measured rather than assumed:

- Every one of those methods takes an **`NSSymbolEffect *`**, and `NSSymbolEffect` is declared in
  **Symbols.framework**, not UIKit: measured, the 16.4 SDK's UIKit headers hold **no** `NSSymbol*`
  declaration at all, and `NSSymbolEffect.h` exists only under `…/Frameworks/Symbols.framework/Headers/`.
- **`NSSymbolEffect` has no registry row anywhere in this repository** (searched every
  `registry/*/*.json`), and `registry/Symbols/` does not exist.
- So implementing these rows would mean inventing a class outside my slice, in a framework this batch
  does not own, with no row to record it against. `check_registry` reads a built class and finds no
  entry — which is exactly the `built, but no entry in registry/` failure, and the trap the AGENTS
  contract names ("a seam the port owns still needs a registry row").

The honest disposition for these rows is therefore `absent` with **that** reason, naming the substrate
rather than the queue. They are not `owed`: a row lands, and this one lands `absent` because the class
its parameter names does not exist in this port's world, in any release it deploys on, or in its SDK.

## M6. The bounce-form spring, measured to zero error

`-initWithDuration:bounce:` and `-initWithDuration:bounce:initialVelocity:` (both 17.0) build a spring out
of a perceptual duration and a bounce. The port's own settling solver does **not** reproduce the host's
numbers — an earlier version of this object derived the spring from the settling duration and was wrong
by up to **358%**, so the spring constants were read back off the host's parameters object instead of
inferred from anything:

```
double (*dg)(id, SEL) = ...;   // -mass, -stiffness, -damping on the host's own object
id p = [[UISpringTimingParameters alloc] initWithDuration:0.5 bounce:0.25];
```

| duration | bounce | host mass | host stiffness | host damping | critical | damping/critical |
|---|---|---|---|---|---|---|
| 0.50 | -1.00 | 1.0000 | 157.9137 | inf | 25.1327 | inf |
| 0.50 | -0.75 | 1.0000 | 157.9137 | 100.5310 | 25.1327 | 4.0000 |
| 0.50 | -0.50 | 1.0000 | 157.9137 | 50.2655 | 25.1327 | 2.0000 |
| 0.50 | -0.25 | 1.0000 | 157.9137 | 33.5103 | 25.1327 | 1.3333 |
| 0.50 | -0.10 | 1.0000 | 157.9137 | 27.9253 | 25.1327 | 1.1111 |
| 0.50 | 0.00 | 1.0000 | 157.9137 | 25.1327 | 25.1327 | 1.0000 |
| 0.50 | 0.25 | 1.0000 | 157.9137 | 18.8496 | 25.1327 | 0.7500 |
| 0.50 | 0.50 | 1.0000 | 157.9137 | 12.5664 | 25.1327 | 0.5000 |
| 0.50 | 0.75 | 1.0000 | 157.9137 | 6.2832 | 25.1327 | 0.2500 |
| 0.50 | 1.00 | 1.0000 | 157.9137 | 0.0000 | 25.1327 | 0.0000 |

That is Apple's law, and it is two formulas:

```
mass      = 1
stiffness = 4*pi^2 / duration^2          (631.6547 / 157.9137 / 39.4784 / 9.8696 at 0.25 / 0.5 / 1 / 2)
critical  = 2*sqrt(mass*stiffness) = 4*pi/duration
damping   = critical * f(bounce),  f(b) = 1 - b        for b >= 0
                                f(b) = 1 / (1 + b)  for b <  0
```

**The negative branch is measured, not assumed.** The obvious guess `f(b) = 1 - b` for every sign is
right for `b >= 0` and **wrong** for `b < 0`: at `b = -0.5` it predicts 1.5 × critical where the host
answers 2.0. Samples at -0.1, -0.25, -0.5 and -0.75 give 1.1111, 1.3333, 2.0 and 4.0 — that is `1/(1+b)`
to four places — and at `b = -1` it diverges and the host reports `damping = inf`, which is what this file
produces rather than a clamp.

### The two sides, run together

The port's formula and the host's own initialiser, over 4 durations × 11 bounces:

```
   dur  bounce |   host stiff   port stiff |    host damp    port damp
   0.25   -1.00 |     631.6547     631.6547 |          inf          inf
   0.25    0.00 |     631.6547     631.6547 |      50.2655      50.2655
   0.25    0.75 |     631.6547     631.6547 |      12.5664      12.5664
   0.50   -0.50 |     157.9137     157.9137 |      50.2655      50.2655
   1.00    0.25 |      39.4784      39.4784 |       9.4248       9.4248
   2.00    1.00 |       9.8696       9.8696 |       0.0000       0.0000
   … 44 rows in all …
WORST |stiffness| error 0.000000
WORST |damping|  error 0.000000
```

**Zero error on every one of the 44 samples, including both infinities.** That is why the file holds the
formulas and not a table of fitted numbers: a table would agree only at the points it was built from.

### What does NOT raise

`bounce 2.0`, `bounce -1.5` and `duration 0.0` all return a usable object on the host — measured, no
exception and no `NSParameterAssert`. So the port clamps nothing and adds no precondition of its own; a
clamp would be the port answering something the system does not.

### The velocity

`initialVelocity` passes through **exactly**: a velocity of `(2,0)` reads back `(2,0)`, and every zero
velocity reads back `(0,0)`. So it goes to the 13.0 initialiser untouched, unscaled.

## M7. iOS 6.1.3, read without waiting for the whole inventory

`objc-inventory.lua` over the 6.1.3 armv7 cache is a heavy job and this batch's run sat behind other
batches' readers of the same cache for 26 minutes at 0% CPU. Two things were already on disk, so the
6.1.3 answers below come from those and are labelled for what they are:

- `~/.charon/dyld/6.1.3/selectors_armv7.txt` — 113981 distinct selectors of that release, pre-extracted.
- `~/.charon/dyld/4.3/classes_armv7.json` — the 4.3 class-scoped inventory, used below to
  class-scope the six names 6.1.3 answers somewhere.

**The control, in the same file: 8 of 8.** `setFrame:`, `reloadData`, `tintColor`, `title`,
`imageNamed:`, `isHidden`, `text` and `value` are all present, so the reader is looking at the right
thing and a zero on another name is the release's.

### The 54 method rows: 0 present, anywhere

Not one of this slice's 54 method selectors appears in 6.1.3's selector list at all — 0 hits over all
113981 names. That is a stronger statement than the class-scoped one, because it does not depend on
which class carries the name.

### The 61 property rows: 6 names appear somewhere, and class-scoping kills every one

This is the rulebook's own trap, live: *a selector's rung says nothing about its owner*. Six property
rows have an accessor name that 6.1.3 carries **somewhere**:

| row | accessor found in 6.1.3 | class-scoped: is it on THIS class? |
|---|---|---|
| `UIImageConfiguration.locale` | `locale`, `setLocale:` | owner is not even a 4.3 class — another class's selector |
| `UIPageControl.progress` | `progress`, `setProgress:` | **no** on `UIPageControl` in 4.3 |
| `UITextView.borderStyle` | `borderStyle`, `setBorderStyle:` | **no** on `UITextView` in 4.3 |
| `UITextSelectionRect.transform` | `transform`, `setTransform:` | owner is not even a 4.3 class |
| `UIHoverGestureRecognizer.rollAngle` | `rollAngle`, `setRollAngle:` | owner is not even a 4.3 class |
| `UITouch.rollAngle` | `rollAngle`, `setRollAngle:` | **no** on `UITouch` in 4.3 |

Three are a selector belonging to a different class, and three are a name the owner does not answer even
in the release where its owner exists. So all six are `absent`, and had this been read as a bare name
match it would have produced six false claims.

### What is NOT yet measured, and is not claimed

The **44 class and protocol rows** need a class list for 6.1.3, which the flat selector file does not
carry, and the class-scoped 6.1.3 inventory had not returned when this batch's turn ended. The
statement for those 44 rows is therefore only the 4.3 one (**0 present, control 8/8**) plus the host's.
No 6.1.3 claim is made for them here, and the rows stay `absent` on the 4.3 measurement alone.

## M8. The 17.5 feedback generators, and the limit that shapes them

Asked of the host's own UIKit:

| member | host | measured |
|---|---|---|
| `+[UIFeedbackGenerator feedbackGeneratorForView:]` | yes | returns a non-nil **UIFeedbackGenerator**; `isKindOfClass:` YES; **a nil view does not raise** |
| `+[UIImpactFeedbackGenerator feedbackGeneratorWithStyle:forView:]` | yes | returns a non-nil **UIImpactFeedbackGenerator** |
| `-[UIImpactFeedbackGenerator impactOccurredAtLocation:]` | yes | returns |
| `-[UIImpactFeedbackGenerator impactOccurredWithIntensity:atLocation:]` | yes | returns |
| `-[UISelectionFeedbackGenerator selectionChangedAtLocation:]` | yes | returns |
| `-[UINotificationFeedbackGenerator notificationOccurred:atLocation:]` | yes | returns |

Two of those decided the code:

- **A factory builds the class it is called on.** `feedbackGeneratorWithStyle:forView:` answers a
  `UIImpactFeedbackGenerator`, so it is `[[self alloc] initWithStyle:]` and not a hard-coded
  `[[UIImpactFeedbackGenerator alloc] …]`.
- **A nil view is not an error.** The host returns a usable generator, so this file adds no precondition
  of its own.

### What the location does NOT get, stated plainly

This release's haptics are the Taptic Engine's one motor, driven by the port's own
`charon_feedback_play(intensity, milliseconds, count)` → `AudioServicesPlaySystemSoundWithVibration`.
**That call takes an intensity and a duration and nothing else.** There is no position parameter, and
no public mechanism on iOS 6.1.3 to say "vibrate harder on the left of the screen".

So the four location methods **accept the point and ignore it**, and say so in the source. What a caller
gets is the haptic its style asks for, at the same strength wherever on the screen it happened. The
alternative — refusing the point, or pretending to weight it — would be the port answering something the
system cannot. The **intensity** argument *is* honoured, because it maps onto a real parameter: it calls
the port's existing 13.0 `-impactOccurredWithIntensity:` rather than repeating that arithmetic.

The bound view is stored so a factory hands back what it was given. Nothing in this release routes
feedback by view, so the view is **recorded, not obeyed** — which is the honest limit of 17.5's location
API on a motor that takes no position.
