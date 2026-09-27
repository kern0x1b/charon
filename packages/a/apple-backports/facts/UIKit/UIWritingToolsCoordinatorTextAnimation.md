# `UIWritingToolsCoordinatorTextAnimationDebugDescription()`, iOS 18.2

`UIWritingToolsCoordinatorTextAnimationDebugDescription(UIKit/UIWritingToolsCoordinatorTextAnimation18.m)`
names a Writing Tools text animation for a log.

## What is measured, and what is not

**Not measured: the release's own spelling of each name.** No release that carries this function is
held on this machine - the newest held cache is iOS 18.0 and the function arrived in 18.2 - and no
host framework has it either, so there is nothing to read the string from and nothing to differ
against. This is the one value in this delivery that is not read out of a real release, and it is
said here rather than glossed.

**Measured: the case names.** `UIWritingToolsCoordinatorTextAnimation` is declared in SDK 26.2's
`UIWritingToolsCoordinator.h:431-447` with three cases and no explicit values, so they are 0, 1 and
2 in the order the header declares them:

| value | case |
| --- | --- |
| 0 | `UIWritingToolsCoordinatorTextAnimationAnticipate` |
| 1 | `UIWritingToolsCoordinatorTextAnimationRemove` |
| 2 | `UIWritingToolsCoordinatorTextAnimationInsert` |

The header's `NS_SWIFT_NAME` renames the type to `UIWritingToolsCoordinator.TextAnimation`, so in
Swift this is a case of a Swift enumeration and not a case of an imported one.

## Why the case name is the answer

A debug description of an enumeration is the name of its case on every Apple platform that has
one: `-[NSObject debugDescription]`, `NSStringFromClass`-style description of a case, and
`String(describing:)` all name the case they are handed, and none of them expands the name into
anything else. What is returned here is the case name as the header spells it, without the
enumeration type's prefix, which is the form Swift's `String(describing:)` gives for a Swift
enumeration case and the form a log line wants.

A value outside 0...2 is not a case of the enumeration, and there is no description to give for it,
so the answer is nil.

**A caller that compares the string should compare the case name, not the exact bytes.** That is
the one honest caveat: the spelling is Apple's and is not reproduced here, and a program that
string-matches a debug description is matching a log, not a contract.
