# The sixteen rows of iOS 8.0's corpus this group registers `absent`, and what each one is measured to be

Sixteen rows of `registry/HealthKit/ios8.json` sit at `absent`: the eight `-init` methods of the classes
whose header marks them unavailable, the four workout-session methods of `HKHealthStore`, and the four
states-of-mind predicates of `HKQuery`. This file is what each of the sixteen is, measured, with the
command behind every number — because a row that names a measurement without the command is an
assertion, and these rows' `source` named only the SDK's own header.

**No row changed status.** `absent` is the right verdict for all sixteen, and for eight of them it is
now the right verdict for a reason that was not known: `implemented` needs a definition the band
exports, the port declares no workout-session method and no states-of-mind predicate, and the eight
`-init` methods are refused by the release and **not** refused by this port, which is an open difference
and not a carried capability. What changed is that each row now says what it is — and eight of them
said something false, not merely something weaker.

**The reader, and its control, once.** Every path in the output quoted below is written `$HOME` where
the run prints this machine's own home; the run prints the absolute cache it read, and that is the one
thing in it a repository may not carry. Sections 1 to 3 are read by

```
CHARON_ROOT="$PWD" xmake l packages/a/apple-backports/facts/HealthKit/rows-code-map.lua 8.0 6.1.3 4.3 9.0 18.0
```

through `modules/apple/objc.lua`'s `code_map()`, which gives every method a rung declares as
`{owner, is_class_method, selector, imp, category}` — so an answer can say **which class** declares a
selector, whether it is a class method, and whether the class declares it of its own or a category adds
it. `objc.inventory()` cannot: its `method_list()` keys *both* of a class's method lists with a leading
`-` and nothing says whether an entry came from the class or from a category. That is not a
hypothetical: a first differential built on `inventory()` answered `no` for all sixteen owners **and
`no` for all sixteen controls**, and could not tell a real zero from a blind reader, so it reported
`CONTROL FAILED` and no row was written from it. The count beside every answer in the output is that
control, and the last line of each rung says what it was:

```
== 8.0  armv7  $HOME/.charon/dyld/8.0/dyld_shared_cache_armv7
   812 images, 380422 methods
   +HKQuery                predicateForStatesOfMindWithValence:operatorType:  own-methods-of-owner=54     NOT DECLARED BY THIS CLASS
   +HKQuery                predicateForStatesOfMindWithKind:               own-methods-of-owner=54     NOT DECLARED BY THIS CLASS
   +HKQuery                predicateForStatesOfMindWithLabel:              own-methods-of-owner=54     NOT DECLARED BY THIS CLASS
   +HKQuery                predicateForStatesOfMindWithAssociation:        own-methods-of-owner=54     NOT DECLARED BY THIS CLASS
   -HKHealthStore          startWorkoutSession:                            own-methods-of-owner=95     NOT DECLARED BY THIS CLASS
   -HKHealthStore          endWorkoutSession:                              own-methods-of-owner=95     NOT DECLARED BY THIS CLASS
   -HKHealthStore          pauseWorkoutSession:                            own-methods-of-owner=95     NOT DECLARED BY THIS CLASS
   -HKHealthStore          resumeWorkoutSession:                           own-methods-of-owner=95     NOT DECLARED BY THIS CLASS
   -HKObject               init                                            own-methods-of-owner=24     own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   -HKObjectType           init                                            own-methods-of-owner=28     own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   -HKQuantity             init                                            own-methods-of-owner=15     own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   -HKSource               init                                            own-methods-of-owner=28     own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   -HKStatistics           init                                            own-methods-of-owner=38     own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   -HKStatisticsCollection init                                            own-methods-of-owner=21     own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   -HKCategorySample       init                                            own-methods-of-owner=11     own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   -HKWorkoutEvent         init                                            own-methods-of-owner=15     own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   anywhere predicateForStatesOfMindWithValence:operatorType:  no class in this rung
   anywhere startWorkoutSession:                            no class in this rung
   anywhere endWorkoutSession:                              no class in this rung
   anywhere pauseWorkoutSession:                            no class in this rung
   anywhere resumeWorkoutSession:                           no class in this rung
   control: every owner class this rung holds declares methods of its own
```

`own-methods-of-owner=54` is the control reading out loud: HKQuery *does* declare 54 methods of its own
in that cache, so a `no` beside it is about the selector and not about the reader. The eight `-init` rows
are in the same table for completeness — they are the subject of §4.

## 1. Both band ends

`modules/apple/backports.lua`'s `band_ranges()` checks a band against the **first and last release of
its range**, so the 8.0 band is checked against the port's deployment release and against the last held
release before the next band point. Neither carries any of these sixteen names, and neither carries the
framework at all:

```
== 6.1.3  armv7  $HOME/.charon/dyld/6.1.3/dyld_shared_cache_armv7
   524 images, 206216 methods
   ... all sixteen: NOT DECLARED BY THIS CLASS, own-methods-of-owner=0
   anywhere <each of the eight selectors>  no class in this rung
   this rung holds none of: HKCategorySample, HKHealthStore, HKObject, HKObjectType, HKQuantity, HKQuery,
                            HKSource, HKStatistics, HKStatisticsCollection, HKWorkoutEvent
```

and the same for 4.3 (354 images, 123684 methods). That last line is the honest form of the zero on
those two rungs: **the ten owner classes are not there**, which is a different statement from "this
reader cannot see them", and the tool now says which of the two it is instead of printing a control that
is vacuously true when no class was found at all.

## 2. The four states-of-mind rows: iOS 18's, and 18.0 is the only rung that has them

`+[HKQuery predicateForStatesOfMindWithValence:operatorType:]`, `-predicateForStatesOfMindWithKind:`,
`-predicateForStatesOfMindWithLabel:` and `-predicateForStatesOfMindWithAssociation:`. The SDK header
leaves all four unannotated, inside `@interface HKQuery (HKStateOfMind)`, so the corpus dated them from
the class — its `via=class-floor` — and filed them under 8.0. They are not 8.0's, and the old reason
("no release from 8.0 to 10.0 carries it") named a range where a measurement names an owner.

```
$ python3 tools/cache-index/first-rung.py --rungs predicateForStatesOfMindWithKind:
predicateForStatesOfMindWithKind:	18.0

$ python3 tools/cache-index/first-rung.py --rungs HKStateOfMind
HKStateOfMind	18.0
```

18.0 is the **first and the only** held rung carrying any of the four, and `rows-code-map.lua` says who
declares them there:

```
== 18.0  arm64e  $HOME/.charon/dyld/18.0/dyld_shared_cache_arm64e
   3692 images, 2896455 methods
   +HKQuery                predicateForStatesOfMindWithValence:operatorType:  own-methods-of-owner=155    own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   +HKQuery                predicateForStatesOfMindWithKind:               own-methods-of-owner=155    own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   +HKQuery                predicateForStatesOfMindWithLabel:              own-methods-of-owner=155    own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   +HKQuery                predicateForStatesOfMindWithAssociation:        own-methods-of-owner=155    own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   anywhere predicateForStatesOfMindWithValence:operatorType:  +HKQuery predicateForStatesOfMindWithValence:operatorType: [own]
   control: every owner class this rung holds declares methods of its own
```

**`own`, not a category** — worth saying, because the release-split script's own blind-spot note is that
a category's methods compile to no nm-visible symbol and a category is the usual reason a method list
cannot be attributed. These four are HKQuery's own. And they are absent from 8.0, from 9.0 (HKQuery
declares 75 methods of its own there and not these), and from every rung in between: the reader above
reports `no class in this rung` for all four on 8.0 and 9.0.

## 3. The four workout-session rows: watchOS's surface, and the strings are in iOS caches anyway

`-[HKHealthStore startWorkoutSession:]`, `-endWorkoutSession:`, `-pauseWorkoutSession:`,
`-resumeWorkoutSession:`. The header settles what they are, one line each
(`System/Library/Frameworks/HealthKit.framework/Headers/HKHealthStore.h`, lines 305, 314, 323, 332):

```
- (void)startWorkoutSession:(HKWorkoutSession *)workoutSession API_DEPRECATED("Use HKWorkoutSession's start method", watchos(2.0, 5.0)) API_UNAVAILABLE(ios, macCatalyst, macos);
- (void)endWorkoutSession:(HKWorkoutSession *)workoutSession API_DEPRECATED("Use HKWorkoutSession's end method", watchos(2.0, 5.0)) API_UNAVAILABLE(ios, macCatalyst, macos);
- (void)pauseWorkoutSession:(HKWorkoutSession *)workoutSession API_DEPRECATED("Use HKWorkoutSession's pause method", watchos(3.0, 5.0)) API_UNAVAILABLE(ios);
- (void)resumeWorkoutSession:(HKWorkoutSession *)workoutSession API_DEPRECATED("Use HKWorkoutSession's resume method", watchos(3.0, 5.0)) API_UNAVAILABLE(ios);
```

Two are **of watchOS 2.0** and two of **watchOS 3.0**, all four **deprecated from watchOS 5.0**, all four
`API_UNAVAILABLE(ios)`. That is more than the rows said: the old reason was "the watch application and
app extensions both arrived after this release", which is true and says nothing about which release the
API belongs to.

**And the strings are in iOS caches, which is why the reason was rewritten instead of trusted.** A
selector's rung says nothing about its own owner, so both questions were asked:

```
$ python3 tools/cache-index/first-rung.py startWorkoutSession: endWorkoutSession: pauseWorkoutSession: resumeWorkoutSession: HKWorkoutSession
startWorkoutSession:	9.0
endWorkoutSession:	9.0
pauseWorkoutSession:	10.0.1
resumeWorkoutSession:	10.0.1
HKWorkoutSession	9.0

$ python3 tools/cache-index/first-rung.py --rungs startWorkoutSession:
startWorkoutSession:	9.0,9.0.2,9.1,9.2,9.2.1,9.3,9.3.5,9.3.6,10.0.1,10.1.1,10.2,10.2.1,10.3,10.3.1,10.3.2,10.3.3,10.3.4,11.0,12.0,16.0,18.0
```

**Control for this reader, in the same run**, because a `NONE` and a broken index look the same:

```
$ printf '%s\n' predicateForObjectsFromWorkout: predicateForSamplesWithStartDate:endDate:options: \
      zzNoSuchCharonSelectorControl: | python3 tools/cache-index/first-rung.py
predicateForObjectsFromWorkout:	8.0
predicateForSamplesWithStartDate:endDate:options:	8.0
zzNoSuchCharonSelectorControl:	NONE
```

Two HealthKit class methods of 8.0 read 8.0 and a nonsense name reads `NONE`, so the index sees
HealthKit's own selectors and the rungs above are the ladder's and not the reader's.

So the absence is **not** "the image has no such string". `rows-code-map.lua` says which class, on
which rung:

```
== 9.0  armv7  $HOME/.charon/dyld/9.0/dyld_shared_cache_armv7
   905 images, 515998 methods
   -HKHealthStore          startWorkoutSession:                            own-methods-of-owner=155    own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   -HKHealthStore          endWorkoutSession:                              own-methods-of-owner=155    own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   -HKHealthStore          pauseWorkoutSession:                            own-methods-of-owner=155    NOT DECLARED BY THIS CLASS
   -HKHealthStore          resumeWorkoutSession:                           own-methods-of-owner=155    NOT DECLARED BY THIS CLASS
   anywhere startWorkoutSession:                            -HKHealthStore startWorkoutSession: [own]
   anywhere pauseWorkoutSession:                            no class in this rung
   control: every owner class this rung holds declares methods of its own

== 18.0  arm64e  $HOME/.charon/dyld/18.0/dyld_shared_cache_arm64e
   -HKHealthStore          pauseWorkoutSession:                            own-methods-of-owner=283    own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   -HKHealthStore          resumeWorkoutSession:                           own-methods-of-owner=283    own in /System/Library/Frameworks/HealthKit.framework/HealthKit
   anywhere endWorkoutSession:                              -CMWorkoutManager endWorkoutSession: [own], -HKHealthStore endWorkoutSession: [own]
   control: every owner class this rung holds declares methods of its own
```

Three facts out of that, each of which the old reason did not have:

1. **8.0 has none of the four.** Its `HKHealthStore` declares 95 methods of its own and not one of
   these, and no class of the 8.0 cache declares them anywhere. So this file, the surface of 8.0, is
   right that they are not 8.0's — and it is now measured rather than asserted.
2. **`startWorkoutSession:` and `endWorkoutSession:` are 9.0's**, HKHealthStore's own from that rung.
   **`pauseWorkoutSession:` and `resumeWorkoutSession:` are 10.0.1's** — 9.0 does not have them at all,
   on any class. The four are therefore two releases apart and the rows now say which is which, where
   before all four shared one sentence.
3. **`-endWorkoutSession:` has a second owner.** In 18.0 `CMWorkoutManager` declares it too, which is
   the concrete case of the rulebook's warning that a selector's rung is not an owner: a first-rung
   answer of 9.0 for `endWorkoutSession:` says nothing about whether it is HealthKit's.

## 4. The eight `-init` rows: the effect was false, and the release refuses where this port does not

Eight rows — `-[HKCategorySample init]`, `-[HKObject init]`, `-[HKObjectType init]`,
`-[HKQuantity init]`, `-[HKSource init]`, `-[HKStatistics init]`, `-[HKStatisticsCollection init]`,
`-[HKWorkoutEvent init]` — carried this `effect`:

> the method is not there: respondsToSelector: answers NO.

**False, on both halves.** `NS_UNAVAILABLE` in the header of each class is a compile-time annotation: it
stops a caller writing the call and says nothing about what the class answers at run time. Measured, in
one process, with the port's classes compiled under names of their own so the system's own HealthKit and
this port's run side by side:

```
$ sh tests/backports/host/healthkit8/run.sh
ok   -[HKCategorySample init]                                   instancesRespondToSelector: host=YES port=YES; alloc-init gives host raised NSInvalidArgumentException: The -init method is not available on HKCategorySample port <CharonHostHKCategorySample:0x1058c1fa0>
ok   -[HKObject init]                                           instancesRespondToSelector: host=YES port=YES; alloc-init gives host raised NSInvalidArgumentException: The -init method is not available on HKObject port <CharonHostHKObject:0x1058c3700>
ok   -[HKObjectType init]                                       instancesRespondToSelector: host=YES port=YES; alloc-init gives host raised NSInvalidArgumentException: The -init method is not available on HKObjectType port <CharonHostHKObjectType:0x1058c3740>
ok   -[HKQuantity init]                                         instancesRespondToSelector: host=YES port=YES; alloc-init gives host raised NSInvalidArgumentException: The -init method is not available on HKQuantity port <CharonHostHKQuantity:0x1058c3d50>
ok   -[HKSource init]                                           instancesRespondToSelector: host=YES port=YES; alloc-init gives host raised NSInvalidArgumentException: The -init method is not available on HKSource port <CharonHostHKSource:0x1058c4260>
ok   -[HKStatistics init]                                       instancesRespondToSelector: host=YES port=YES; alloc-init gives host raised NSInvalidArgumentException: The -init method is not available on HKStatistics port <CharonHostHKStatistics:0x1058c4660>
ok   -[HKStatisticsCollection init]                             instancesRespondToSelector: host=YES port=YES; alloc-init gives host raised NSInvalidArgumentException: The -init method is not available on HKStatisticsCollection port <CharonHostHKStatisticsCollection:0x1058c4920>
ok   -[HKWorkoutEvent init]                                     instancesRespondToSelector: host=YES port=YES; alloc-init gives host raised NSInvalidArgumentException: The -init method is not available on HKWorkoutEvent port <CharonHostHKWorkoutEvent:0x1058c4ae0>
ok   -[HKHealthStore startWorkoutSession:]                      - respondsToSelector: host=YES port=no
ok   -[HKHealthStore endWorkoutSession:]                        - respondsToSelector: host=YES port=no
ok   -[HKHealthStore pauseWorkoutSession:]                      - respondsToSelector: host=YES port=no
ok   -[HKHealthStore resumeWorkoutSession:]                     - respondsToSelector: host=YES port=no
ok   +[HKQuery predicateForStatesOfMindWithAssociation:]        + respondsToSelector: host=YES port=no
ok   +[HKQuery predicateForStatesOfMindWithKind:]               + respondsToSelector: host=YES port=no
ok   +[HKQuery predicateForStatesOfMindWithLabel:]              + respondsToSelector: host=YES port=no
ok   +[HKQuery predicateForStatesOfMindWithValence:operatorType:] + respondsToSelector: host=YES port=no
checks=16 failures=0
rows asked about: 16, all absent in registry/HealthKit/ios8.json
```

`instancesRespondToSelector: host=YES port=YES`, eight times over. The rows' sentence was wrong about
the port and about Apple's own class.

Nothing in the tree could have caught that, which is why it stood. `NS_UNAVAILABLE` leaves no symbol, the
port exports no `-init` for these classes, and `modules/apple/backports.lua`'s `backports.surface()`
reads the built library's **own** method lists — an inherited method is another image's, so `nm -gU`
and the gate both correctly report the row as "not built" while the runtime answer is YES. A probe is
the only place the sentence can be checked, so it is in the tree.

### What the release itself does, read out of its own image

The eight rows also claimed "the release declares no `-init` of its own either". **That is false, and
the code map in §0 says so**: each of the eight classes declares an `-init` **of its own** in the 8.0
image — 11 of `HKCategorySample`'s 11, 24 of `HKObject`'s 24, 28, 15, 28, 38, 21, 15 — and the image
declares nothing else for that selector. The body was read, with the project's own reader and never
copied:

```
$ CHARON_ROOT="$PWD" xmake l <extract + address reader> ~/.charon/dyld/8.0/dyld_shared_cache_armv7
extracted .../HK-8.0-armv7 (41785240 bytes)
  -[HKQuantity init]  imp=0x2284e9d5
  -[HKObject   init]  imp=0x22850cd1
  ...

$ /Library/Developer/CommandLineTools/usr/bin/llvm-objdump --macho --arch=armv7 --disassemble HK-8.0-armv7
2284e9d4:  b0 b5        push  {r4, r5, r7, lr}
2284e9e0:  4c f2 d8 40  movw  r0, #0xc4d8
2284e9e4:  c0 f6 62 50  movt  r0, #0xd62
2284e9ec:  08 46        mov   r0, r1              ; r0 = _cmd
2284e9ee:  2a f0 12 e8  blx   0x22878a14 @ symbol stub for: _NSStringFromSelector
2284e9f8:  80 46        mov   r8, r0              ; r8 = "init"
2284ea06:  20 46        mov   r0, r4              ; r0 = self
2284ea08:  2a f0 5c e8  blx   0x22878ac4 @ symbol stub for: _objc_msgSend   ; r9 = [self class]
2284ea30:  cd e9 00 89  strd  r8, r9, [sp]        ; the two %@ arguments
2284ea38:  2a f0 44 e8  blx   0x22878ac4 @ symbol stub for: _objc_msgSend   ; raise(name, reason, ...)
2284ea48:  00 20        movs  r0, #0              ; ARC unwind epilogue; unreachable
2284ea50:  b0 bd        pop   {r4, r5, r7, pc}
```

The image's own `__cstring` holds exactly one string of that shape:

```
$ strings -a HK-8.0-armv7 | grep -E 'not available|-%@ method'
The -%@ method is not available on %@
```

Two `%@`, and the two arguments are `NSStringFromSelector(_cmd)` and the receiver's class — so 8.0
raises with the reason **`The -init method is not available on HKObject`**, formatted, and the exception
it raises is `NSInvalidArgumentException`, which that image imports:

```
$ nm -m HK-8.0-armv7 | grep -i exception
         (undefined) external _NSInvalidArgumentException (from CoreFoundation)
         (undefined) external _OBJC_CLASS_$_NSException (from CoreFoundation)
         (undefined) external _OBJC_EHTYPE_$_NSException (from CoreFoundation)
```

**That is byte-for-byte the message the host raises today.** I had written in an earlier draft of this
file that the host's refusal was a later behaviour, because the literal
`The -init method is not available on ` is not a string in the 8.0 cache — it is a *format*, and the
cache index holds strings, so the absence of the literal proves nothing. It is retracted: the format is
8.0's own and the message it produces is the host's.

So: the release refuses an uninitialized instance of these eight classes, and this port hands one over.

### Why this band does not carry the refusal yet, and what closing it needs

The refusal is four lines of armv7 and the port already has the shape for it — `HKQuery.m:58` and
`HKUnit.m:420` both define `- (instancetype)init` inside their own `@implementation`. It is **not**
written here, for a reason that is about scope and not about difficulty:

**The refusal does not stop at the eight.** `HKObjectType`'s subclasses are `HKSampleType` and, through
it, `HKQuantityType`, `HKCategoryType`, `HKCharacteristicType`, `HKCorrelationType` and
`HKWorkoutType`; `HKObject`'s subclass is `HKSample`. A `-init` that raises on `HKObjectType` is
inherited by all six, and a `-init` that raises on `HKObject` is inherited by `HKSample`. **None of
those six is in this slice and none of their own `-init` was measured here.** Writing the refusal for
the eight alone would silently change the behaviour of seven classes this band does not own, on the
assumption that they refuse too — which is an assumption, and a test that guesses is what §9 of the
workspace contract forbids.

Closing it needs one more measurement, over the seven subclasses: does the 8.0 image declare an `-init`
of its own on each, and does its body refuse? The reader already answers the first half —
`rows-code-map.lua` with those seven names added — and the disassembly answers the second. With that,
one object carrying the refusal for every class of the 8.0 image that refuses turns these eight rows
`implemented` with a measured effect, and this section becomes a record of a closed difference rather
than an open one.

## What a caller gets, all sixteen together

Twelve of the sixteen are methods no iOS release may call, or only from 9.0 and 10.0.1 onwards: the port
declines them and `respondsToSelector:` answers NO, which is what their `effect` says. The other eight
are `-init` methods a caller cannot write, and where a caller reaches an instance anyway, this port hands
over an object of the right class with nothing set — where iOS 8.0 raises `NSInvalidArgumentException`
with `The -init method is not available on <class>`, and where a current host raises exactly the same.
That difference is the one thing in this file still open, and §4 says what it needs.

## The check to run before each delivery

```
sh tests/backports/host/healthkit8/run.sh
```

Sixteen checks, one per row. It fails when the port and the system's own class disagree about one of the
eight `-init` names, and when the port answers one of the eight it must not. It also reads the sixteen
names back out of `registry/HealthKit/ios8.json` and fails if any is gone or is no longer `absent`, so a
row added to this set is a check someone has to add rather than a silent gap. When the refusal is
written, the eight `-init` checks become a comparison of the message the two raise, and the row goes
from "the two agree on respondsToSelector:" to "the two refuse identically".
