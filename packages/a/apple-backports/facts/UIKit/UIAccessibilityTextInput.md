# `NSObject.accessibilityTextInputResponder` and `NSObject.accessibilityTextInputResponderBlock`, iOS 18.1

Two accessibility properties that arrived in iOS 18.1: the text-input responder an accessibility object
presents, and the block that hands it out. Both rows in `registry/UIKit/ios17-18.json` are `absent`, and
`absent` is a positive claim: the caller cannot get the behaviour on this release. So the claim needs the
fact that makes it true, and that fact is measurable here without a device and without an argument about
hardware: UIKit is a framework this release HAS, so the question is whether the release's own UIKit
declares the member at all.

## The measurement

The library compiles against the iPhoneOS 16.4 SDK, so a member those headers do not declare has no
implementation to be written against on this release. One probe over the 16.4 UIKit headers, run over the
same tree as the rows:

| member | files of the 16.4 UIKit headers that declare it |
| --- | ---: |
| `accessibilityTextInputResponder` | 0 |
| `accessibilityTextInputResponderBlock` | 0 |
| `accessibilityLabel` (control) | 4 |
| `accessibilityTraits` (control) | 3 |

**The control is what makes the two zeroes evidence.** The same probe, the same tree, the same command:
it finds `accessibilityLabel` in four headers and `accessibilityTraits` in three. A probe that answered
zero for everything would say nothing about these two members, so the controls are in the table rather than
in a comment above it.

A second fact, and the one that closes the other way round: no backport supplies the member either. Over
`packages/a/apple-backports/` the two names appear in exactly one file, `registry/UIKit/ios26.json`, which
records what the 26.2 SDK declares and implements nothing. So "neither iOS 6 nor the backports give NSObject
a property like it" is a measurement here, not a reading of a header.

## What the caller gets

The accessors are not declared, so `respondsToSelector:` answers honestly and an unchecked call raises
instead of returning a plausible zero. That is the whole effect, and it is the same effect the neighbouring
17.0 and 18.0 rows carry.

## Hardware

None is named here, because none is what is missing. The device has accessibility; what the release's UIKit
does not have is the declaration. Where hardware IS the reason — a pointer, a stylus — the fact is written
that way and cites `UIPointerEvents.md` and `UIPointerStyle.md`, which are the model: the iPad 2 has no
pointer, and `UIPointerEvents.md` says so with the run that read it.
