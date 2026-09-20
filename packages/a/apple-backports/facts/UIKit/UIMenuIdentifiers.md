# The menu identifiers, iOS 13.0 and 14.0

`UIMenuApplication` to `UIMenuWindow` and the rest are the standard identifiers of the menu bar's menus
(`UIMenuFile`, `UIMenuEdit`, `UIMenuSpelling`, ...), 43 from iOS 13.0 and `UIMenuOpen` and `UIMenuOpenRecent` from 14.0.
Each is a string, and the port carries the same string.

Source: read out of the host's own UIKit under Mac Catalyst (macOS 27.0) by asking each symbol; `tests/backports/host/uikit2`
(the `menus` group) compares all 45 with the backport's, and `tests/backports/device/menus.m` holds the same table against
the device, and that each comes from `libUIKitBackports.dylib`.

- All are `com.apple.menu.<name>`, the name in lower case with hyphens (`UIMenuNewScene` is `com.apple.menu.new-item`,
  `UIMenuUndoRedo` is `com.apple.menu.undo-redo`), except `UIMenuSpeech`, which is `com.apple.command.speech`.
- `UIMenuSidebar` (15.0) and `UIMenuDocument` (16.0) are the constants of later releases and are not carried.

Nothing on this release builds a menu from them: the identifiers exist so that an application that keys its menus by them
- to name a menu it makes, or to look for one in a builder - links.
