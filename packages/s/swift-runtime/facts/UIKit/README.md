# The UIKit Swift overlay: the surface's Swift constants and cases

`UIKitSurfaceConstants.swift` declares the 28 types and 111 cases of
`coordination/corpus/ledger/UIKit.tsv` whose `lang` is `swift` and whose `kind` is `constant` - the
part of the API push that is Swift-only, which no Objective-C file can answer.

**Where it goes.** Appended to the overlay's own `stdlib/public/Darwin/UIKit/UIKit.swift`, the file
`packages/s/swift-runtime/xmake.lua` builds the `UIKit` Swift module from (line 432 onwards, the
`uikit` tree it fetches at `swift-5.2.5-RELEASE` / `71d85a7c28eed8f46241649a723ddf23989139c6` and
patches with `patches/uikit/*.patch` before `build_overlay`). The overlay of swift-5.2.5 declares
none of these 28 types, so nothing here collides with what it already has.

**Two shapes, and which one a type takes is a measurement.** The 111 names are typechecked one per
file at `armv7-apple-ios6.1.3` with the port's own flags (`tc.sh`, which takes every path from the environment). Every one fails against the
lifted headers alone - `type 'UIButton' has no member 'Configuration'`, `cannot find
'UICellAccessory' in scope` - because these spellings are made by UIKit's *own Swift overlay*:
`UIButtonConfigurationCornerStyle` is a top-level Objective-C enum, and `UIButton.Configuration.
CornerStyle` is the nested Swift name the SDK's overlay gives it. So:

- where the lifted headers declare the enclosing Objective-C class, the overlay carries a namespace
  type of its own and a `typealias` on the class, which is what makes the nested name resolve
  (`extension UIButton { public typealias Configuration = CharonUIButton.Configuration }`);
- where the headers declare no such class at all - the type is native Swift in UIKitCore and has no
  Objective-C spelling - the namespace is declared outright.

`roots.txt` holds the eight roots of the second kind, taken from the typecheck's own errors.

**What is not claimed.** Only the cases this checklist names. A type's `==`, its `hash(into:)`, its
`init(rawValue:)`, and the types its payloads point at (`UITextFormattingViewController.TextList`,
`Highlight`, `TextAlignment`, `UITab`) are other rows of the surface.

**Regenerating.** `gen-overlay.py` reads the checklist and the SDK's own
`UIKit.framework/Modules/UIKit.swiftmodule/arm64e-apple-ios.swiftinterface`, and prints the file
above. The case names and their payloads are the SDK's own, not typed by hand.

**State: the typecheck runs, and 111/111 is not yet reached.** `tc.sh` takes its resource
directory from an installed `charon@swift-runtime`'s own `lib/swift`, which is where the armv7
standard library, the armv7 swiftmodules and the toolchain's clang include are; with that the file
compiles far enough to report real errors instead of "unable to load standard library". What is
left, measured, one `tc.sh /tmp/n111/NNN.swift` per name:

| errors | what |
| --- | --- |
| 8 | `'UITargetedPreview' is only available in iOS 13.0 or newer` - a payload type the SDK gates below the port's release, so the case that names it needs the same `@available` the roots get |
| 4 | `'Position' is not a member type of enum 'CharonUICellAccessory.Placement'` - a payload naming a sibling type, substituted into the wrong parent |
| 4 | `'CharonUITextItem' is only available in iOS 17.0 or newer` - a payload of ours that is itself gated, so its cases need the floor as well |
| 2 | `CharonUIPointerShape has no member 'defaultCornerRadius'` - the case's default value names a `static let` that is a *property* row, not one of these 111; the case keeps its label and loses the default |
| 2 | `invalid redeclaration of 'TitleAlignment'`, of `'Size'` - two types share a short name (`UIListContentConfiguration.TextProperties.TextAlignment` and `UIButton.Configuration.TitleAlignment`), and the generator's tree keys a level by its short name |

The file itself parses clean (`swiftc -parse`, no errors): 46 enumerations, 112 case declarations
covering the 111 rows, 16 typealiases. It is **not yet in the package's patch set** - the diff is
still to be generated with `git diff` in a git checkout of the pinned upstream, which is what the
last commit's README says to do next.
