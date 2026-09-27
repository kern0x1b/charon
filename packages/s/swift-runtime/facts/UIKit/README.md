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


## The rows that wait for their class

These 25 rows spell their names through a class the port's registry carries as `absent`
(`registry/UIKit/ios17-18.json`: `UITab`, `UITabSidebarItem`, `UITextFormattingViewController`
and `UITextItem`), so the overlay cannot declare the name they ask for: the enclosing class is
not there to nest a type in, and a typealias on a class that does not exist does not compile.
They are registered `absent` for that reason until the UIKit bands carry those classes, and the
typecheck counts them as such: each is a row whose name is unreachable, not a row whose
declaration is wrong.

| row | the class it waits for |
| --- | --- |
| `UITabBarController.Sidebar.ScrollTarget.tab` | `UITab` |
| `UITabSidebarItem.Content.action` | `UITabSidebarItem.Content` |
| `UITabSidebarItem.Content.tab` | `UITabSidebarItem.Content` |
| `UITextFormattingViewController.ChangeValue.bold` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.decreaseFontSize` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.decreaseIndentation` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.font` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.fontSize` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.formattingStyle` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.highlight` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.increaseFontSize` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.increaseIndentation` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.italic` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.lineHeightPointSize` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.strikethrough` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.textAlignment` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.textColor` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.textList` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.undefined` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.underline` | `UITextFormattingViewController.ChangeValue` |
| `UITextItem.Content.link` | `UITextItem.Content` |
| `UITextItem.Content.tag` | `UITextItem.Content` |
| `UITextItem.Content.textAttachment` | `UITextItem.Content` |
| `UITextItem.MenuConfiguration.Preview.default` | `UITextItem.MenuConfiguration` |
| `UITextItem.MenuConfiguration.Preview.view` | `UITextItem.MenuConfiguration` |

## The 86 that resolve, and the one class standing between them and 86/86

The overlay, with the 25 waiting rows' namespaces left out, is 38 enumerations, 87 case
declarations and 5 typealiases, and the typecheck over the 86 rows that are not waiting reports
exactly one error:

```
$ for f in /tmp/n86/*.swift; do packages/s/swift-runtime/facts/UIKit/tc.sh "$f" 2>&1 | grep "error:"; done \
    | sed 's/.*error: //' | sort | uniq -c
    688 'UITargetedPreview' is only available in iOS 13.0 or newer
```

688 is 86 files naming the same four `UIPointerEffect` cases. `UIAction` and `NSTextAttachment`
already lower in the headers this typecheck reads; `UITargetedPreview` does not, and
`registry/UIKit/ios13menus.json` carries it as `implemented` - the headers were lifted when the
`swift-runtime` install this typecheck takes its resource directory from was built, so a fresh lift
over this tree's registry lowers it. The count against those fresh lifted headers is what
`lift-remeasure.sh` (or `fast_lift2.lua`, the recipe it uses) is for, and it is queued.
## The rows that wait for their class

These 25 rows spell their names through a class the port's registry carries as `absent`
(`registry/UIKit/ios17-18.json`: `UITab`, `UITabSidebarItem`, `UITextFormattingViewController`
and `UITextItem`), so the overlay cannot declare the name they ask for: the enclosing class is
not there to nest a type in, and a typealias on a class that does not exist does not compile.
They are registered `absent` for that reason until the UIKit bands carry those classes, and the
typecheck counts them as such: each is a row whose name is unreachable, not a row whose
declaration is wrong.

| row | the class it waits for |
| --- | --- |
| `UITabBarController.Sidebar.ScrollTarget.tab` | `UITab` |
| `UITabSidebarItem.Content.action` | `UITabSidebarItem.Content` |
| `UITabSidebarItem.Content.tab` | `UITabSidebarItem.Content` |
| `UITextFormattingViewController.ChangeValue.bold` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.decreaseFontSize` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.decreaseIndentation` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.font` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.fontSize` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.formattingStyle` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.highlight` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.increaseFontSize` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.increaseIndentation` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.italic` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.lineHeightPointSize` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.strikethrough` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.textAlignment` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.textColor` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.textList` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.undefined` | `UITextFormattingViewController.ChangeValue` |
| `UITextFormattingViewController.ChangeValue.underline` | `UITextFormattingViewController.ChangeValue` |
| `UITextItem.Content.link` | `UITextItem.Content` |
| `UITextItem.Content.tag` | `UITextItem.Content` |
| `UITextItem.Content.textAttachment` | `UITextItem.Content` |
| `UITextItem.MenuConfiguration.Preview.default` | `UITextItem.MenuConfiguration` |
| `UITextItem.MenuConfiguration.Preview.view` | `UITextItem.MenuConfiguration` |

## The other 86

The remaining rows resolve once the lift lowers the availability of the SDK classes the surface
spells them through, which it does for a class the registry carries as `implemented` - `UIAction` and
`UITargetedPreview` are, in `registry/UIKit/ios13menus.json`. The lifted headers a typecheck reads
were made when a `swift-runtime` install was built, so a fresh lift over this tree's registry is
what the count below is measured against.
