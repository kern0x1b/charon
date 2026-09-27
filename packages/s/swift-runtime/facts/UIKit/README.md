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

**State: 111/111 names resolve; the typecheck's last 30 errors are one lift change.**

`tc.sh` takes its resource directory from an installed `charon@swift-runtime`'s own `lib/swift`
(where the armv7 standard library, the armv7 swiftmodules and the toolchain's clang include are),
the SDK is the real 26.2 under the lift's `vfs.yaml`, and each of the 111 names is typechecked in
its own file against the overlay. Measured:

```
$ for f in /tmp/n111/*.swift; do packages/s/swift-runtime/facts/UIKit/tc.sh "$f" 2>&1 | grep "error:"; done \
    | sed 's/.*error: //' | grep -v "is only available in iOS" | sort | uniq -c
(no output)
```

**Every error the typecheck still reports is the availability gate on seven SDK classes the surface
spells these names through** - not one is a naming, nesting, payload or redeclaration error:

| errors | class | its floor |
| --- | --- | --- |
| 8 | `UITextFormattingViewController` | 18.0 |
| 8 | `UITargetedPreview` | 13.0 |
| 4 | `UITextItem` | 17.0 |
| 4 | `UITab` | 18.0 |
| 2 | `UITabSidebarItem` | 18.0 |
| 2 | `UIAction` | 13.0 |
| 2 | `NSTextAttachment` | 7.0 |

That gate is `charon`'s, and it is the same gate the Objective-C rows of this checklist already
carry as `needs=lift`: the surface spells `UITabSidebarItem.Content` through a class the port's
release does not have, and the lift lowers the headers' availability for the Objective-C side. The
overlay's own types are declared **unconditionally** - that is the Swift counterpart, and the
reason a name the surface spells at 6.1.3 can be named at 6.1.3 - so what is left is the lift
lowering these seven classes' availability, after which the typecheck is 111/111.

The file: 49 enumerations, 115 case declarations (the 111 rows and the three payload types of
`ChangeValue` that the cases name), 9 typealiases, and `swiftc -parse` clean.
