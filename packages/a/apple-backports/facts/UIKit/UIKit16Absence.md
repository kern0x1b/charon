# The 16.0 rows of `registry/UIKit/ios15-16.json`: what each band end carries

115 rows of release **16.0** sat at `absent` with the SDK's own declaration as their only `source`,
which is an assertion and not a measurement. This page holds the measurement, the commands that
reproduce it, and their output, so a reviewer can settle any row here without a second tool.

**The claim, in one line:** no held release the 16.0 band builds carries any of the 115 names, so
`absent` is the correct verdict for all 115 and the gate's `held` check cannot fire on this file.

## Which releases are the band's ends, and why these two

`modules/apple/backports.lua:2578` — "every band checks its imports against the caches of its first
and last release". The held ladder (`dyld.held_ladder`) jumps **12.0 -> 16.0**: no 13.0, 14.0 or 15.0
is held. So for a band whose points end at 16.0 the first release is the oldest the port deploys on,
**6.1.3**, and the last is the newest held release below 16.0, **12.0**. Those two are this file's
band ends, and a row that survives both cannot fire `held`.

## The measurement: class-scoped, both ends, with the control in the same run

The rule that makes a selector's rung useless here: **a selector's rung says nothing about its owner**
(`fileSystemRepresentation` reads 3.0 — another class's — while `-[NSURL fileSystemRepresentation]`
is 7.0). So the question is never "does this name exist", it is "does *this class* carry *this
selector*", and that is `carried_by_release()` at `backports.lua:1612-1631` reading the release's own
`apple.objc` inventory.

```
CHARON_ROOT=$PWD xmake l tools/corpus/cache-census.lua UI 6.1.3 12.0
```

Output, abridged to its control line and the two headers (the full run is 2926 names):

```
6.1.3     ~/.charon/dyld/6.1.3/dyld_shared_cache_armv7
         images 524, of which naming UI 25
         classes 11378, of which UI* 705 (UIActionSheet UIAlertView ... UIBarButtonItem UIButton UICollectionViewCell ...)
         protocols 1171, of which UI* 91 (UIAccessibilityElement UIActionSheetDelegate ... UITableViewDelegate UITextViewDelegate ...)
12.0      ~/.charon/dyld/12.0/dyld_shared_cache_arm64
         images 1368, of which naming UI 138
         classes 63192, of which UI* 1741 (...)
         protocols 11426, of which UI* 389 (...)
control: 2926 name(s) beginning UI found in this run, so a zero on another rung is the release's and not the reader's
```

**The control is the point of that run.** A census printing 0 is ambiguous — the name may be absent,
or the reader may be looking at the wrong thing — so each release prints its image, class and
protocol counts, and a run finding nothing anywhere is reported `CONTROL FAILED`. 2926 names found
means the reader was looking at the right thing.

**Result: 0 of the 115 names appear in either band end.**

The census answers the 29 class and protocol rows, because a class name belongs to exactly one class
and first-rung is therefore a *class-scoped* answer for them — which is the one case where the
selector trap does not apply. The 86 method and property rows need the class's own selector list, so
they were read from the two full inventories:

```
CHARON_ROOT=$PWD xmake l tools/corpus/objc-inventory.lua ~/.charon/dyld/6.1.3/dyld_shared_cache_armv7 > inv-6.1.3.tsv
CHARON_ROOT=$PWD xmake l tools/corpus/objc-inventory.lua ~/.charon/dyld/12.0/dyld_shared_cache_arm64 > inv-12.0.tsv
```

One TSV line per class: `class <name> <superclass> <image> <instance selectors> <class selectors>
<protocols>`. Selector keys carry a `-` prefix in **both** columns, which is what
`carried_by_release` expects (`carried[sign == "-" and "instance" or "class"]["-" .. selector]`), so
the dump is directly comparable to the check.

**Result: 0 of the 86 are carried by 6.1.3, and 0 by 12.0.** 27 of them have an owner class a band
end *does* carry, so for those the selector check was a real question, not a formality.

### Controls, and two traps the controls caught

The reader is only worth a zero if it can find what is there. Eight controls, 8/8 present on each
release: `UIView -setFrame:`, `UITableView -reloadData`, `UIBarButtonItem -tintColor`,
`UINavigationItem -title`, `UIImage -imageNamed:` (class column), `UIView -isHidden`,
`UICollectionView -dequeueReusableCellWithReuseIdentifier:forIndexPath:`, `UISearchBar -text`.

- **The `is`-form.** The 6.1.3 era spells the `hidden` property's getter `-isHidden`, not `-hidden`.
  A property check that looked only for `-<name>` would have reported a false clean. All 41 property
  rows were re-run against the getter, the `is`-getter and the setter; still 0 carried. This matters
  for `UIBarButtonItem.hidden`, whose owner 6.1.3 does carry.
- **Categories are merged.** `UIImage`'s class column holds `-mapkit_imageNamed:` — a MapKit category
  on a UIKit class — so the dump already counts what categories add, which is what the registry check
  counts.

### The early rungs are other classes', measured

`first-rung.py` over the 107 distinct names: 94 read 16.0, and 13 read earlier. All 13 are
explained, and none of them touches its row:

| name | rung | what 6.1.3 actually says |
|---|---|---|
| `style` | 3.0 | 90 classes carry it, `UINavigationItem` among the 6 that do not |
| `hidden` | 3.0 | 14 classes carry it (`CALayer`, `DOMHTMLElement`, ...); `UIBarButtonItem` is not a view and is not among them |
| `direction` | 3.0 | 25 classes carry it (`CALight`, the DOM HTML classes, `UISwipeGestureRecognizer`); not `UIPageControl` |
| `ordered`, `documentProperties`, `badgeCount`, `export:`, `backAction`, `duplicate:`, `find:`, `alwaysAvailable` | 3.2 – 11.0 | the name is in the index, but **no 6.1.3 class implements it** — the inverse of the documented trap |

### Two rows the SDK's own annotation is wrong about

`UICalendarViewDelegate` and `UISceneWindowingBehaviors` read **18.0**, not 16.0: the 16.0 cache
carries no such name, so the SDK's `introduced` is not corroborated by the cache of the release that
introduced it. Both are recorded in their rows rather than smoothed over. Both are still absent from
every release the band builds, which is the claim the row makes.

## The one row with real demand, and why it is still `absent`

`-[UISearchResultsUpdating updateSearchResultsForSearchController:selectingSearchSuggestion:]` is the
only row of the 115 with demand behind it (2 apps, `CRASH-ON-USE`; rank 68). It was measured rather
than assumed, and the measurement says the port cannot carry it:

- **Both apps DEFINE the selector.** `corpus/defcache/session.json` and `defcache/delta.json` list
  `updateSearchResultsForSearchController:selectingSearchSuggestion:` among the methods the binaries
  define. So the method is the *application's*; any definition the band exported would shadow it.
- **The band cannot export a definition anyway.** A `.m` redeclaring the protocol compiles with
  `warning: duplicate protocol definition of 'UISearchResultsUpdating' is ignored` and the object
  exports **no symbol at all** — the SDK the package compiles against already declares the member, so
  the redeclaration is discarded. `implemented` needs "a definition the band exports"
  (`backports.lua:1932`, `unbuilt`), and this exports nothing: it would fail the gate.
- **A conformer already compiles and dispatches.** Built for `arm64-apple-ios15.0-macabi`, a conformer
  implementing both members compiles (one `-Wunguarded-availability-new` note about the
  `UISearchSuggestion` parameter type), and `respondsToSelector:` answers **YES**, because the
  application's own method answers it.
- **Nothing in the port applies it, and the header says why.** `UISearchController.h:54` scopes the
  trigger to "one of the search suggestion buttons displayed under the keyboard on **tvOS**". This
  port lists no suggestions — `UISearchSuggestion` is a protocol no held release declares (its own row
  is `absent`) — so there is no call site to add without building a suggestion list, which is a
  feature, not a backport.

`inert` was considered and rejected on the same measurement: `inert` means "the symbol loads and
nothing applies it", but the symbol here is the application's, and the band exports none. `absent`
means "nothing the release has answers the name" — measured, 0 at both ends. The `CRASH-ON-USE` label
describes two applications *defining* a selector for a framework release the port is not; it is not
a missing port capability, and no registry row or object changes it.

## What a reader should take from this

Every row of the file says `absent`, and that is now a measurement rather than a queue entry: **0
carried at 6.1.3, 0 carried at 12.0, control passed in the same run, 8/8 selector controls on each
release, and the `is`-getter form checked on all 41 properties.** No status in this file is wrong.
The rows that could be implemented are the ones whose owner class a band end carries, and each of
those is feature work with its own differential — not something a registry row can settle.
