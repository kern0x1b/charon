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

**State.** The file is complete and parses (`swiftc -parse` clean, 46 enumerations, 111 cases, 20
typealiases). It is **not yet in the package's patch set**: the generated diff does not apply, and
the typecheck cannot run, because another band's `swift-runtime` rebuild has taken the installed
package's armv7 swiftmodules and standard library off the disk for now. Both are one `swift-runtime`
build away.
