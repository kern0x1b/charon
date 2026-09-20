# The interactions that have nothing to react to, iOS 13 and 14

`UILargeContentViewerInteraction`, `UIScreenshotService`, `UITextFormattingCoordinator`, `UITextPlaceholder`, `UIScribbleInteraction`,
`UIIndirectScribbleInteraction` and `UIPointerLockState` are carried as the objects an application makes and holds so that one that
links them launches. What each would react to is not on the release, so each is `inert`: made, kept, added to a view and removed like
its kin, never called back, and says so once in the log the first time it is used.

Source: the host's own UIKit under Mac Catalyst (macOS 27.0), asked for every default, and held against the backport by the `inert`
group of `tests/backports/host/uikit2`; `tests/backports/device/uirest.m` for a device.

## Large content viewer

The viewer shows a magnified item when a person holds a control while the accessibility text size is large; iOS 6 has neither. The
five members of `UILargeContentViewerItem` are kept on a view - no viewer, NO, no title, no image, no scaling, zero insets to begin
with - and nothing reads them. An interaction made with a delegate keeps it weakly and has no `gestureRecognizerForExclusionRelationship`
until it is added to a view, when it has a disabled recogniser on that view, as the host has; `+enabled` answers NO and the
notification of its change is never posted. The first interaction added says so in the log.

## Screenshot service

A window scene answers one `UIScreenshotService`, always the same, that keeps its delegate weakly and its scene weakly. iOS 6 takes a
screenshot itself and asks the application for nothing, so the delegate is never asked for a PDF; setting one says so in the log.

## Text formatting coordinator

The font panel belongs to Mac Catalyst. The coordinator is made, keeps its delegate weakly, is never visible (`+fontPanelVisible` NO),
takes selected attributes and forgets them, and `+toggleFontPanel:` does nothing and says so.

## Text placeholder

A value with no rects, as the host answers for one made with `init`; a text input sets them, and none of the release's does.

## Scribble

Handwriting with Apple Pencil is not on the release. Both interactions are made, with `-init` too as the host allows, keep their
delegate weakly, never handle writing, and `+pencilInputExpected` is NO. The delegates' messages are never sent.

## Pointer lock

A scene answers one `UIPointerLockState`, always the same and never locked; `prefersPointerLocked` of a view controller is NO,
`childViewControllerForPointerLock` nil, and asking for an update says so once. The notification's name is `UIPointerLockStateDidChangeNotification`,
its user info key `scene`, and it is never posted.
