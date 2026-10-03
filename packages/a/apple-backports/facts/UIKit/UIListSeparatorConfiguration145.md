# UIListSeparatorConfiguration, iOS 14.5

A configuration for the separators of a `UICollectionView` list: two visibilities, two sets of insets, a colour
and a colour for while several rows are selected. The 14.5 header declares ten names and states no default for
any of them, so every number below is measured.

Source: the host's own UIKit under Mac Catalyst (macOS 27.0, build 26A428), asked for every default, every
write read back, the copy, the archive round trip and the two `NS_UNAVAILABLE` constructors, by the case in
`tests/backports/host/uikit2/listseparator_test.m` - the port's object built beside the system's in one
process, under the name `CharonHostUIListSeparatorConfiguration`, and every value printed by the case for both
sides. That case is the oracle: its expectations are what the host answers, not what the port returns.

## M1. The defaults, as the host answers them

One reading per appearance; the case asks all five and the host gives the same six values for every one of
them, so a port that switched on the appearance would be red.

| read | the host's answer |
| --- | --- |
| `topSeparatorVisibility` | `0` - `UIListSeparatorVisibilityAutomatic` |
| `bottomSeparatorVisibility` | `0` - `UIListSeparatorVisibilityAutomatic` |
| `topSeparatorInsets` | `0 1.79769e+308 0 1.79769e+308`, and it **is** `UIListSeparatorAutomaticInsets` by value (`1`) |
| `bottomSeparatorInsets` | the same automatic constant |
| `color` | a colour - the separator colour, 0 0 0 0.098 resolved |
| `multipleSelectionColor` | a colour - a DYNAMIC one on the host, over the same role |

`UIListSeparatorAutomaticInsets` is not a made-up constant here: the header declares it, and the case asks
whether the value the configuration answers **is** that constant, by comparison, and the host says yes.

The multiple-selection colour being dynamic is the one that shows on the host: it resolves to the same 0 0 0
0.098 on a light interface, and it is a provider over the trait collection rather than a frozen colour, so the
port makes it a dynamic colour over the same role instead of freezing a value that would be wrong on the other
interface.

## M2. Writes, the copy and the archive

Every property is written and read back on both sides, and the answers agree: visibility `2` and `1`, insets
`1 2 3 4` and `5 6 7 8`, and each colour **by identity** - the getter hands back the very object the setter was
given, which is what `copy` on the property means for an object.

`-copy` is another object, never its receiver, and it keeps the top visibility, the bottom insets and **the
colour instance** - the same colour object, not an equal one.

The archive round trip goes through `NSKeyedArchiver` with `requiringSecureCoding:YES` and back through
`NSKeyedUnarchiver`, on both sides, and the keys are the host's own - read out of the host's archive plist by
the band that measured them. A configuration written with visibility `2`/`1` and insets `1 2 3 4` / `5 6 7 8`
reads back with all four, and with a colour present.

## M3. `+new` and `-init` are `NS_UNAVAILABLE`, the port defines neither, and what a call reaches is `NSObject`'s

The 14.5 header marks both unavailable, and Apple's own class defines neither. Measured on the class's own
method lists, the way item 1's eight rows are decided and not by the header:

| read | source | result |
| --- | --- | --- |
| `-init` in `UIListSeparatorConfiguration`'s own instance list | arm64e cache of iOS 16.0, `modules/apple/objc.lua`'s `inventory` | **no** (`no-own-init`) |
| a method named `new` in its own metaclass list | the same read | **no** (`no-own-new`) |
| control: `-init` in a class's own instance list | the same read | yes, **28851** of that cache's classes, `ARConfiguration` and `NSObject` among them |
| control: a method named `new` in a class's own metaclass list | the same read | yes, **523** of them, `NSObject` itself among those |
| `UIListSeparatorConfiguration`'s own lists, on the host | `class_copyMethodList` | 37 instance methods, no `init`; 6 metaclass methods, no `new` |

The class arrived in 14.5 and no 14.x cache is held on this machine, so **16.0 is the oldest release here
that carries it** and 18.0 the newest read for this ruling; both agree, and both agree with the host. The two
rows are therefore `absent`, and the object carries `-initWithListAppearance:`, `-initWithCoder:` and the
header's ten members and nothing else.

What a call reaches is `NSObject`'s, on this release and on Apple's alike, and what that answers is every
field at the zero of its type - measured on the host, and the port's own case asks both constructors on both
sides with `objc_msgSend` and reads every field back:

| read | `+[UIListSeparatorConfiguration new]` | `-[UIListSeparatorConfiguration init]` |
| --- | --- | --- |
| `topSeparatorVisibility` | `0` | `0` |
| `bottomSeparatorVisibility` | `0` | `0` |
| `topSeparatorInsets` | `0 0 0 0` | `0 0 0 0` |
| `bottomSeparatorInsets` | `0 0 0 0` | `0 0 0 0` |
| `color` | nil | nil |
| `multipleSelectionColor` | nil | nil |

The insets are **zero** where `-initWithListAppearance:` - the header's `NS_DESIGNATED_INITIALIZER` - gives
the automatic ones, and both colours are nil where it gives the separator colour. Those numbers need no code
here: they are what an object that wrote nothing reads back as.

**The port defined both for a while, and the header was not the reason to take them out.** It defined
`-init` as `[super init]` and `+new` as `[[self alloc] init]`, and the `-init` was also the only warning the
package's own compile line printed on the file:

    UIListSeparatorConfiguration145.m:115:19: warning: convenience initializer should not invoke an
    initializer on 'super' [-Wobjc-designated-initializers]

Both are gone and the warning with them: the header already marks `-initWithListAppearance:`
`NS_DESIGNATED_INITIALIZER`, so the class's one initializer is a designated one and there is no secondary
initializer left to warn about. The two definitions were answering what `NSObject`'s already answers, on a
class Apple's own metadata does not give them to.

A first version of this file, and of the row beside it, said the port had a `-initCharonWithDefaults:` method
"stated as a separate method so the difference between the two paths is in the code rather than in a comment".
**There is no such method** and there never was. The registry check's coherence pass is what found it - it
named the selector as one the row cites and the file the row names does not define. A comment that describes a
method which is not there is the same defect as a row that describes one, so both were corrected forward.

## What this port does not do

The appearance model. `-initWithListAppearance:` stores the appearance and applies the defaults above; it does
not switch a separator's colour on the interface style, on a selection, or on a list's own background, because
this release has no `UICollectionView` list for a separator to be drawn in. The rows say what the object stores
and answers back and do not claim the drawing.

## The crash that was in this case, and where it was

The group's run died with `exit=139` - SIGSEGV - and the band that wrote the case could not root it in the time
it had, and recorded that the port's archive round trip passed in isolation and so did the system's.

**It was the case's own diagnostic string, not the archive.** Under AddressSanitizer the stack is

    #0 objc_opt_respondsToSelector+0xc (libobjc.A.dylib)
    #1 __CFSTRING_IS_CALLING_OUT_TO_AN_OBJECT_FORMAT_ARGUMENT_WITH_CONTEXT__ (CoreFoundation)
    #5 +[NSString stringWithFormat:]
    #6 check_one_appearance listseparator_test.m:117

and line 117 was `[NSString stringWithFormat:@"port %@ system %@", error, ourArchive.length]` - a `%@` given
`ourArchive.length`, an `NSUInteger`. CFString sent `-respondsToSelector:` to a number near the zero page and
the process died. The string is built **eagerly**, as the detail argument of the check, so it killed the run
whether or not the check it was reporting had failed: the archive round trip was never reached, and M2 above is
what it answers once the string is right.

Three errors, one per call, and the lengths as integers: `NSKeyedArchiver archivedDataWithRootObject:` was given
the same `NSError *` twice and so were the two unarchive calls, so a failure on the port's side could not be
told from one on the system's.

## The red control

The comparison responds to a wrong answer on the keys M1 states. One plant in a scratch copy of the port's
source - `_topInsets = NSDirectionalEdgeInsetsMake(3, 3, 3, 3)` where the measured value is
`UIListSeparatorAutomaticInsets` - and the run goes red and names the keys:

    FAIL the plain top insets are the automatic ones: port 3 3 3 3 != system 0 1.79769e+308 0 1.79769e+308
    FAIL the plain insets are the shared constant: port 0 != system 1
    FAIL the grouped top insets are the automatic ones: port 3 3 3 3 != system 0 1.79769e+308 0 1.79769e+308
    FAIL the grouped insets are the shared constant: port 0 != system 1

It is a value and not a call, so the group still builds and still links: a plant that broke the build would
prove the compiler works and not that the comparison works.