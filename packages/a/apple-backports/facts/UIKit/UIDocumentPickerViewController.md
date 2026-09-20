# UIDocumentPickerViewController, iOS 8

Introduced in iOS 8: the view controller through which an application opens or imports a document that another
application or iCloud Drive keeps, and exports or moves one to such a place. iOS 11 added the plural `initWithURLs:` and
`allowsMultipleSelection`, and iOS 13 `shouldShowFileExtensions` and `directoryURL`.

Source: the host's own UIKit under Mac Catalyst, asked for every initializer and mode below and held against the port by
the `documentpicker` group of `tests/backports/host/uikit2/run.sh`; and `tests/backports/device/uikit2.m` for the flow
on iOS 6.

## What the port does as the system does

`initWithDocumentTypes:inMode:` takes the import and open modes and raises `NSInternalInconsistencyException` for the
others, and `initWithURL:inMode:` and `initWithURLs:inMode:` take the export and move modes and raise the same for the
others, with the system's reasons. `init` and `initWithNibName:bundle:` raise `NSInvalidArgumentException` with the
system's reason; `initWithCoder:` is allowed. `documentPickerMode`, `delegate` (held weakly), `allowsMultipleSelection`,
`shouldShowFileExtensions` and `directoryURL` are kept.

## What it cannot do

iOS 6 has no document providers: no iCloud Drive, no file provider extension, no other application that offers its
documents. So the picker shows a bar titled "Locations" with a cancel button and says that no locations are available.
Cancelling dismisses it and then sends the delegate `documentPickerWasCancelled:`. The delegate never hears
`documentPicker:didPickDocumentAtURL:` or `documentPicker:didPickDocumentsAtURLs:`, and an export or a move never
completes. An application that handles the cancellation, as it has to, carries on without a document.
