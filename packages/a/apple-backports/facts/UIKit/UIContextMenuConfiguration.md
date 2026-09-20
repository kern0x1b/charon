# UIContextMenuConfiguration, iOS 13.0

Introduced in iOS 13.0: what a delegate returns to say a context menu should appear - an identifier, a block that makes the preview and a
block that makes the menu.

Source: the host's own UIKit under Mac Catalyst (macOS 27.0), held against the backport by `tests/backports/host/uikit2` (the
`menus` group).

## As UIKit does

- `+configurationWithIdentifier:previewProvider:actionProvider:` keeps the two blocks and a **copy** of the identifier; with none, the
  identifier is a new `NSUUID`. `-init` does the same for the identifier.
- The class adopts nothing: it does not copy, is not archived, and equals only itself.

## What the port does with it

Only the action provider is called, by `UIContextMenuInteraction`, with an empty array where the host passes the actions its responder chain
suggests: iOS 6 has no such actions. The preview provider is **never** called, since no preview is drawn and a preview view controller nobody
sees would cost its `-loadView`.

`secondaryItemIdentifiers`, `badgeCount` and `preferredMenuElementOrder` (16.0) are not carried.
