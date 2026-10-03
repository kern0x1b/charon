# UIKit's 18.0 band in this port: the ladder, the one member, and the question this page does not answer

Every row of `registry/UIKit/ios17-18.json` whose `introduced` is 18.0 is one of 103: 28 classes,
4 protocols, 37 methods and 34 properties. This page holds the measurement all of them rest on, the
one member the port carries, and - stated plainly, because a reader of the registry will want to
know - the one question about the band that is not settled here.

## M1. Both band ends, class-scoped, with the controls in the same run

```
$ CHARON_ROOT=$PWD xmake l ./tools/corpus/objc-inventory.lua ~/.charon/dyld/6.1.3/dyld_shared_cache_armv7
$ CHARON_ROOT=$PWD xmake l ./tools/corpus/objc-inventory.lua ~/.charon/dyld/4.3/dyld_shared_cache_armv7
```

6.1.3: 12549 lines, 11378 classes, 1171 protocols, 705 of the classes named `UI*`.
4.3: 7751 lines, 7187 classes, 564 protocols, 597 named `UI*`.

Seven selector controls, each read class-scoped - the class that must own it does:

| selector | 6.1.3 | 4.3 |
| --- | --- | --- |
| `-[UITabBarController selectedViewController]` | on UITabBarController | on UITabBarController |
| `-[UITabBarController setViewControllers:animated:]` | on UITabBarController | on UITabBarController |
| `-[UITextView text]` | on UITextView | on UITextView |
| `-[UIColor blackColor]` | on UIColor | on UIColor |
| `-[UIColor clearColor]` | on UIColor | on UIColor |
| `-[UITableView reloadData]` | on UITableView | on UITableView |
| `-[UIViewController viewDidLoad]` | on UIViewController | on UIViewController |

The two `UIColor` entries are class methods and the dump writes every selector in a class's column
with a `-`, so they read `-blackColor` and `-clearColor` there; the class that owns them is the one
named above, which is the part that makes them controls.

**Checked row by row, all 71 absent member rows of the band.** For each one, either the row's own
class is in neither dump, or the class's own selector list in both dumps holds neither the name, nor
its `is`-getter form, nor its `set-` form. **Zero rows where the claim fails.** 36 of the 71 name a
class that is itself of 18.0 and is in neither dump - `UIBackgroundConfiguration`,
`UIListContentConfiguration`, `UIListContentImageProperties`,
`UICollectionLayoutListConfiguration`, `UITabBarControllerDelegate`, `UITextInput`,
`UITextViewDelegate` - and for those the claim is the class's own absence, not a selector's.

**`UITraitCollection` is in neither dump**, which is why a member of it is a member of a class the
port owns rather than one the release carries (see M2).

### A selector index that cannot be used for this, so nobody uses it again

The cheap reading looks like the right one and is not:
`grep -cxF separatorInsetReference ~/.charon/dyld/6.1.3/selectors_armv7.txt` answers 0, and so does
the same file for plain `separatorInset`, which `first-rung.py` places at **7.0**, while the same
file answers 1 for `reloadData`. `selectors_armv7.txt` is a partial index: a zero in it says nothing
about the release. `first-rung.py` is the reader with a self-test, and the class-scoped dump above
is the reader that answers the question these rows ask. Measured 2026-10-03.

## M2. The one member the port carries: `+[UITraitCollection traitCollectionWithListEnvironment:]`

The band has exactly one member with substrate, and it is this one, because the port owns
`UITraitCollection` itself (M1) and already keeps the list-environment trait on both sides of the
store:

- `UITraitListEnvironment` is `implemented`, minimum 6.0 (`registry/UIKit/ios17traits.json`,
  defined in `UITraitList18.m`), so the class is exported in every band the constructor's object is
  in - the one link-time dependency this object has, and it is a dependency the band keeps;
- `-[UITraitCollection listEnvironment]` is `implemented` and reads through the store's own reader,
  `CHARON_TRAIT_PROPERTY([UITraitListEnvironment class], UIListEnvironment, listEnvironment,
  setListEnvironment)` at `UITraitCollection+Traits17.m:239`;
- `+[UITraitCollection traitCollectionWithNSIntegerValue:forTrait:]` at
  `UITraitCollection+Traits17.m:321` is the store's own writer, and `UITraitList18.m`'s
  `CHARON_TRAIT(17, UITraitListEnvironment, @"ListEnvironment", CharonTraitValueNSInteger,
  CharonTraitHomeExtras, @(0), YES)` declares this trait's kind to be the writer's kind.

So the constructor is one call to the writer, and what it writes is what `-listEnvironment` reads.
`packages/a/apple-backports/UIKit/UITraitCollection+TraitConstructors18.m` is that call.

### What the system's own UIKit answers, measured

`.agent-work/runs/w-uikit-18/probe-listenv.m` in the worktree this landed from, compiled for
`arm64-apple-ios18.0-macabi` against the host's own UIKit, one collection per line:

```
enum controls: Unspecified=0 None=1 Plain=2 Grouped=3
Unspecified                                          -> listEnvironment=0  description=<UITraitCollection; >            (no ListEnvironment at all)
None                                                 -> listEnvironment=1  description=<UITraitCollection; ListEnvironment = 1>
Plain                                                -> listEnvironment=2  description=<UITraitCollection; ListEnvironment = 2>
Grouped                                              -> listEnvironment=3  description=<UITraitCollection; ListEnvironment = 3>
out of range 99                                      -> listEnvironment=99 description=<UITraitCollection; ListEnvironment = 99>
negative -1                                          -> listEnvironment=-1 description=<UITraitCollection; ListEnvironment = -1>
a collection with no list environment set            -> listEnvironment=0
same collection's other traits are untouched         -> userInterfaceStyle=0
```

Three things the port's answer therefore has to agree with, and does:

1. **the value goes under the trait's own name**, `ListEnvironment`, and nothing else - the last line
   is the control that it is a trait and not a field the constructor kept;
2. **no argument is validated** - 99 and -1 are stored and read back unchanged, exactly as
   `UITraitCollection+TraitConstructors17.m`'s three constructors do, measured the same way for 17.0
   in `facts/UIKit/UIKit17Absence.md` M15 (`imageDynamicRange 99 -> ImageDynamicRange = 99`);
3. **`Unspecified` is the absence of the trait**, not a stored zero: its description carries no
   `ListEnvironment` at all while every other case does. The port's own answer for an unset
   collection is the trait class's default, which `UITraitList18.m` declares as `@(0)` - the same
   value, reached the way the store reaches it, and for the same reason: `Unspecified` is 0.

The 16.4 SDK the package compiles against has no `UITrait.h` (the trait classes reached UIKit in
17.0), so `UIListEnvironment` and `UITraitListEnvironment` come from `CharonTraits17.h` behind the
`__has_include` the rest of the tree uses, and the object's own declaration sits behind the same
guard - the same reason, and the same shape, as `UITraitCollection+TraitConstructors17.m`.

**Compiled as the build compiles it**, with the flags `modules/apple/backports.lua` assembles
(`-Os -g0 -Wall -Wno-unguarded-availability-new -Wno-unguarded-availability
-Werror=objc-missing-property-synthesis`, ARC, the package on the include path):
`clang -fsyntax-only -target armv7-apple-ios6.1.3` and `armv7-apple-ios4.3` each print **0 lines
matching ` error: `**, and the two warnings each prints are the nullability notes from
`CharonTraits17.h` that the 17.0 constructors file beside it prints in the same run.

## M3. What this page does not settle: the 28 class rows and the 4 protocol rows

The band also carries 28 classes and 4 protocols as names only. main's registry has all 32 at
`absent`, with the reason "the class arrived in iOS 18, and nothing in iOS 6 does its work or stands
in for it". Two other bands on this tree have taken the opposite position for the same shape of
name - `CharonUIKit26.h`'s twenty-one 26.0 classes and `CharonUIKit18.h`'s 18.2 and 18.4 classes are
declared, given empty implementations and marked `implemented`, on the argument that an application
linking strongly against the name needs dyld to resolve it.

**This page does not claim those 32 rows either way**, and nothing here changes them. They are one
question - whether a name-only class with no measurement of the release behind it is `implemented`
or `absent` - and the two answers are both on this tree today, the `absent` one being the newer.
Whoever settles it settles all three bands at once, and the decision belongs to the owner.

What *is* settled here, and is not in question: the 71 absent member rows of the band are measured
(M1) and say what the release does not have; the one member with substrate is carried (M2); and the
other 32 member rows are the list-configuration and delegate rows whose reasons name the port's own
classes and styles - main's, kept as they are.

**Not claimed:** that a 6.1.3 or 4.3 release could have displayed a list environment had it carried
the constructor. Neither does: M1 measured the class out of both band ends. What M2 measures is what
the constructor has to agree with where one exists, which is the host's own UIKit.