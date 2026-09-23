# UIModalPresentationAutomatic as the default style, iOS 13.0

From iOS 13.0 a view controller that a program linked with SDK 13.0 or later makes starts with
`UIModalPresentationAutomatic`, and `modalPresentationStyle` answers the style it resolves to, which on a
phone and a pad is the page sheet: a controller presented without a style of its own is a sheet, not a
full-screen presentation. A program linked with an older SDK keeps full screen.

**This touches every ported application.** Charon links against the iPhoneOS 16.4 SDK, and clang writes
that into the load command (`LC_VERSION_MIN_IPHONEOS` version 6.0, sdk 16.4, read from the apple-backports
libraries themselves). So every port built by charon is linked on or after 13.0, and every presentation
it makes without setting a style - `presentViewController:animated:completion:` of a plain controller, a
navigation controller, a picker - now shows as a sheet on the phone (`UISheetPresentationController.md`)
and as the release's page sheet on the iPad, where it used to cover the screen. A port that wants full
screen sets `UIModalPresentationFullScreen`, as it must on iOS 13 itself. A program linked with an older
SDK (an App Store binary of its time, a port built with an old SDK) is not touched at all.

Source: UIKitCore of the held 16.0 cache (arm64e), read statically; no 13.x or 14.x cache is on the ladder.
UIKit of 6.1.3 (armv7) and UIKitCore of 12.0 (arm64) are read for what the older library does with the
value. The listing and every address: `.agent-work/plan-and-analysis/b1314-sheet/modal-default.md` of the
band that made the port. Held by `tests/backports/device/modaldefault.m`, built twice.

## What the release does (16.0)

- `-[UIViewController initWithNibName:bundle:]` (0x188fd7770-0x188fd778c) calls
  `dyld_program_sdk_at_least` with iOS 13.0.0 and writes the style ivar -2 (Automatic) when it answers
  YES, 0 (full screen) otherwise.
- `-initWithCoder:` (0x18917ab8c-0x18917abc8) decodes `UIModalPresentationStyle` when the archive holds
  the key, and otherwise makes the same check. `-init` goes through `-initWithNibName:bundle:`.
- `-modalPresentationStyle` (0x188e97f50) answers the ivar unless it is Automatic; then it asks
  `-_preferredModalPresentationStyle` (UIViewController's answers Automatic, 0x188e987d0), and when that
  is Automatic too, `-[_UIPresentationControllerDefaultVisualStyleProvider
  defaultConcretePresentationStyleForViewController:]`. That asks the provider registered for the
  controller's idiom, and UIKitCore registers none for the phone or the pad, so the fallback
  `_UIPresentationControllerNullVisualStyleProvider` answers: the page sheet (1, 0x189ab9524). The getter
  never answers Automatic.
- `UIImagePickerController` prefers full screen when its source is the camera (0x1895fc4ac).
- `UIDocumentPickerViewController` prefers the form sheet behind the feature flag `UIKit/dci_navbar`
  (0x1896c0ef8); `UISplitViewController` prefers 4, or 2 for a program linked with SDK 16.0 or later and
  a style other than unspecified (0x188e995ac).

## What the port does

- The same decision by the same fact. `dyld_program_sdk_at_least` is not in 6.1.3's libdyld, and
  `dyld_get_program_sdk_version`, which is, is declared only in `mach-o/dyld_priv.h`. The port reads
  the SDK the way dyld does, from the main image's load commands - `_NSGetMachExecuteHeader()`
  (`<crt_externs.h>`) and the `sdk` of `LC_VERSION_MIN_IPHONEOS`, or of an iOS `LC_BUILD_VERSION` - and
  takes an image that records neither as linked before 13.0.
- For such a program, and only on a release whose `UIViewController` lacks `isModalInPresentation` (the
  release decides in `+load`, before the port's own categories are attached), the port writes Automatic
  through the release's own setter after `-initWithNibName:bundle:` and after `-initWithCoder:` of an
  archive without the key, and its getter answers Automatic as the page sheet, or full screen for an image
  picker of the camera. A style set explicitly, an archived one and a subclass's own setting after `super`
  are left as they are.
- Writing -2 into the release's ivar is safe on the releases it runs on: UIKit 6.1.3 reads the ivar
  directly only in its getter and setter, in `-_useSheetRotation` (compared with 16), `-initWithCoder:` and
  `-encodeWithCoder:`; UIKitCore 12.0 in the same places and `-_setModalPresentationStyle:` (compared with
  16 and 4). Everything else asks the getter. The archive of an Automatic controller holds -2, as the
  release's does.

## Not carried

- `UISplitViewController`'s preference (4 or 2): a split view controller presented modally resolves to the
  page sheet. iOS 6 has the class on the iPad only, and 4 is a custom presentation with no delegate on a
  release that has none.
- `UIDocumentPickerViewController`'s: the port's own class answers its style itself (the form sheet on the
  pad, full screen on the phone).
- A presentation restores the resolved style, not Automatic, on the presented controller once it has
  begun (`UIViewController+TransitionCoordinator.m` sets full screen around the release's own present and
  puts back what the getter answered). Nothing reads the difference except an image picker whose source
  changes from the camera to the library after it was presented.
