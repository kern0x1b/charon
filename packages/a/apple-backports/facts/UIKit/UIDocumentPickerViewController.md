# UIDocumentPickerViewController, iOS 8

Introduced in iOS 8: the view controller through which an application opens or imports a document, and exports or
moves one. iOS 11 added the plural `initWithURLs:` and `allowsMultipleSelection`, and iOS 13 `shouldShowFileExtensions`
and `directoryURL`.

Source: the host's own UIKit under Mac Catalyst, asked for every initializer and mode and held against the port by the
`documentpicker` group of `tests/backports/host/uikit2/run.sh`; and `tests/backports/device/documentpicker.m`, which
drives the browser with real touches on iOS 6.

## What the port does as the system does

`initWithDocumentTypes:inMode:` takes the import and open modes and raises `NSInternalInconsistencyException` for the
others; `initWithURL:inMode:` and `initWithURLs:inMode:` take the export and move modes and raise the same for the
others, with the system's reasons. `init` and `initWithNibName:bundle:` raise `NSInvalidArgumentException`. The
properties are kept and the delegate is weak.

## The browser

iOS 6 has no document providers, so the picker is a file browser over the device's own file system, in a navigation
controller inside the picker, presented as a form sheet.

- The first page lists the locations: the application's home, `/var/mobile/Media`, `/var/mobile/Documents`,
  `/var/mobile` and `/`, each only if the application can read it. `directoryURL`, when it is an existing folder, opens
  the browser inside it with the trail back to its location.
- A folder lists folders first, then files, by name; hidden files are not shown. Extensions are hidden unless
  `shouldShowFileExtensions` is set.
- `documentTypes` filter the files through the UTI of their extension (`UTTypeConformsTo`); a file that does not
  conform is greyed and cannot be chosen. `public.item` accepts everything; folders are always entered.
- Open mode answers the chosen file's own URL. Import mode answers a copy in a fresh folder of the temporary directory,
  as the system does. With `allowsMultipleSelection` rows are ticked and a Done button answers all of them, in the order
  chosen. The plural delegate method is used when the delegate has it, else the singular one.
- Export and move show a folder browser whose button, "Copy" or "Move", answers the URLs of the copies or the moved
  files inside the folder shown; a name already taken there gets a number.

- Cancel dismisses the picker and then sends `documentPickerWasCancelled:`; a choice dismisses it and then sends the URL.

## What differs from the system

There is no iCloud Drive, no other application's documents, no recents and no tags, and no security scope
(`NSURL` answers YES to `startAccessingSecurityScopedResource`; see `NSURL.md`). The browser is the system's file
system, unsandboxed on a jailbroken device.
