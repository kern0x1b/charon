# The UIKit constants of iOS 26

`UIKit/UIKitConstants260.m`: the action that takes what is on the pasteboard as something new, the
document-moved notification and its key, the two menu identifiers, and the assistive-access scene
role.

## Where the values come from

No iOS release on this machine carries these symbols: the held ladder ends at iOS 18.0. They are
read out of the Mac Catalyst UIKit of macOS 27, in the system's own dyld shared cache
(`/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e`), with this
repository's own reader (`tools/corpus/cache-value.lua` over `modules/apple/dyld.lua`).

| constant | the value |
| --- | --- |
| `UIActionNewFromPasteboard` | `com.apple.action.newFromPasteboard` |
| `UIDocumentDidMoveToWritableLocationNotification` | `UIDocumentDidMoveToWritableLocationNotification` |
| `UIDocumentDidMoveToWritableLocationOldURLKey` | `UIDocumentDidMoveToWritableLocationOldURLKey` |
| `UIMenuFindPanel` | `com.apple.menu.find-panel` |
| `UIMenuNewItem` | `com.apple.menu.new-item` |
| `UIWindowSceneSessionRoleAssistiveAccessApplication` | `UIWindowSceneSessionRoleAssistiveAccessApplication` |

`UIMenuNewItem` and `UIMenuFindPanel` are the two the measurement is most needed for: both are
`NSString * const` behind names that say nothing about their value, and both differ from the
neighbouring identifiers this package already carries - `UIMenuNewScene` is `com.apple.menu.new-item`
(`UIKit/UIMenuIdentifiers.m`), so `UIMenuNewItem` is the same scheme one release later with the same
value, and `UIMenuFindPanel` is `com.apple.menu.find-panel` where `UIMenuFind` is
`com.apple.menu.find`. A guess from the neighbouring constants would have been right for the first
and wrong for the second.
