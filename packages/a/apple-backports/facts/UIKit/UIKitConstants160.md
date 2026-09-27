# The UIKit constants first exported by iOS 16.0

`UIKit/UIKitConstants160.m`. 34 constants, one object, and every value read out of a real dyld
shared cache rather than taken from a header or from a host framework.

The reader is `tools/corpus/cache-value.lua` over this repository's own cache reader
(`modules/apple/dyld.lua`). It is checked before any value is taken: on each cache of
the ladder, eight constants whose value is their own name are read back, and a cache
that reproduces none of the ones it holds contributes nothing. On this ladder every
cache reproduced all eighteen of the checked strings it holds, and no constant's
value differed between caches.

| constant | the release it was read from | the value |
| --- | --- | --- |
| `NSTextContentStorageUnsupportedAttributeAddedNotification` | 16.0 | `@"NSTextContentStorageUnsupportedAttributeAddedNotification"` |
| `UIActionPaste` | 16.0 | `@"com.apple.action.paste"` |
| `UIActionPasteAndGo` | 16.0 | `@"com.apple.action.pasteAndGo"` |
| `UIActionPasteAndMatchStyle` | 16.0 | `@"com.apple.action.pasteAndMatchStyle"` |
| `UIActionPasteAndSearch` | 16.0 | `@"com.apple.action.pasteAndSearch"` |
| `UIActivityItemsConfigurationMetadataKeyLinkPresentationMetadata` | 16.0 | `@"linkPresentationMetadata"` |
| `UIActivityTypeCollaborationCopyLink` | 16.0 | `@"com.apple.UIKit.activity.CollaborationCopyLink"` |
| `UIActivityTypeCollaborationInviteWithLink` | 16.0 | `@"com.apple.UIKit.activity.CollaborationInviteWithLink"` |
| `UIActivityTypeSharePlay` | 16.0 | `@"com.apple.UIKit.activity.SharePlay"` |
| `UIApplicationLaunchOptionsEventAttributionKey` | 16.0 | `@"UIApplicationLaunchOptionsEventAttributionKey"` |
| `UIApplicationOpenExternalURLOptionsEventAttributionKey` | 16.0 | `@"UIApplicationOpenExternalURLOptionsEventAttributionKey"` |
| `UIApplicationOpenURLOptionsEventAttributionKey` | 16.0 | `@"UIApplicationOpenURLOptionsEventAttributionKey"` |
| `UIGuidedAccessErrorDomain` | 16.0 | `@"UIGuidedAccessErrorDomain"` |
| `UIKeyInputDelete` | 16.0 | `@"."` |
| `UIListSeparatorAutomaticInsets` | 16.0 | `{top = 0.0, leading = CGFLOAT_MAX, bottom = 0.0, trailing = CGFLOAT_MAX}` |
| `UIPasteboardDetectionPatternCalendarEvent` | 16.0 | `@"com.apple.uikit.pasteboard-detection-pattern.dd.event"` |
| `UIPasteboardDetectionPatternEmailAddress` | 16.0 | `@"com.apple.uikit.pasteboard-detection-pattern.dd.email"` |
| `UIPasteboardDetectionPatternFlightNumber` | 16.0 | `@"com.apple.uikit.pasteboard-detection-pattern.dd.flight"` |
| `UIPasteboardDetectionPatternLink` | 16.0 | `@"com.apple.uikit.pasteboard-detection-pattern.dd.link"` |
| `UIPasteboardDetectionPatternMoneyAmount` | 16.0 | `@"com.apple.uikit.pasteboard-detection-pattern.dd.money"` |
| `UIPasteboardDetectionPatternPhoneNumber` | 16.0 | `@"com.apple.uikit.pasteboard-detection-pattern.dd.phone"` |
| `UIPasteboardDetectionPatternPostalAddress` | 16.0 | `@"com.apple.uikit.pasteboard-detection-pattern.dd.address"` |
| `UIPasteboardDetectionPatternShipmentTrackingNumber` | 16.0 | `@"com.apple.uikit.pasteboard-detection-pattern.dd.shipment"` |
| `UIPointerAccessoryPositionBottom` | 16.0 | `{offset = 14.0, angle = 3.141592653589793}` |
| `UIPointerAccessoryPositionBottomLeft` | 16.0 | `{offset = 14.0, angle = 3.9269908169872414}` |
| `UIPointerAccessoryPositionBottomRight` | 16.0 | `{offset = 14.0, angle = 2.356194490192345}` |
| `UIPointerAccessoryPositionLeft` | 16.0 | `{offset = 14.0, angle = 4.71238898038469}` |
| `UIPointerAccessoryPositionRight` | 16.0 | `{offset = 14.0, angle = 1.5707963267948966}` |
| `UIPointerAccessoryPositionTop` | 16.0 | `{offset = 14.0, angle = 0.0}` |
| `UIPointerAccessoryPositionTopLeft` | 16.0 | `{offset = 14.0, angle = 5.497787143782138}` |
| `UIPointerAccessoryPositionTopRight` | 16.0 | `{offset = 14.0, angle = 0.7853981633974483}` |
| `UITextContentTypeDateTime` | 16.0 | `@"date-time"` |
| `UITextContentTypeFlightNumber` | 16.0 | `@"flight-number"` |
| `UITextContentTypeShipmentTrackingNumber` | 16.0 | `@"shipment-tracking-number"` |

## The release each object carries

A band links one object per release and an object carries the API that arrived in
one release: an object that defines a symbol the band already has together with one
it does not is refused at link time (`modules/apple/backports.lua`, `band()`). The
release above is the first *held* release that exports every symbol in the file,
measured symbol by symbol over `~/.charon/dyld`, so the file is kept by every band below that
release and reexported by the release's own from that one on.
