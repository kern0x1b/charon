# `UTType` and its eleven carried constants, iOS 14

Source: the local machine's own SDK headers - `UniformTypeIdentifiers/UTType.h` and
`UniformTypeIdentifiers/UTCoreTypes.h` under `/Library/Developer/CommandLineTools/SDKs/
MacOSX26.5.sdk` - for the class's surface and the exact identifier string behind each constant;
`UIDocumentPickerViewController.h` from the same SDK drop for the two `initFor...` pairs that
demand this class. Behaviour is not reasoned: it is the `UTType*` C functions MobileCoreServices
already carries on iOS 6 (`UTTypeConformsTo`, `UTTypeCopyPreferredTagWithClass`,
`UTTypeCopyDescription`, `UTTypeCreatePreferredIdentifierForTag`, `UTTypeIsDynamic`,
`UTTypeIsDeclared`) - the same functions `UIDocumentPickerViewController.m`'s own
`charon_acceptsPath:` was already calling before this class existed.

## What `UTType` is

A recent SDK's object wrapper around the same Uniform Type Identifier a release since iOS 3
already names with a plain `NSString`/`CFStringRef`. `UTType.identifier` is that string; every
other property and method on the class is answered by calling the matching `UTType*` C function
with it. Nothing about behaviour is invented - the class is carried as a thin object shell over
functions that already work correctly on iOS 6.

`typeWithIdentifier:` builds the wrapper directly. `typeWithFilenameExtension:`,
`typeWithFilenameExtension:conformingToType:`, `typeWithMIMEType:`,
`typeWithMIMEType:conformingToType:` and `typeWithTag:tagClass:conformingToType:` all resolve
through `UTTypeCreatePreferredIdentifierForTag`, exactly as the SDK header documents each being
equivalent to a `typeWithTag:tagClass:conformingToType:` call.

## The eleven constants

Only the constants an application is likely to reach for while filtering a document picker are
carried, not the full 150-some-constant catalogue `UTCoreTypes.h` declares - a constant this
backport does not carry is only reached if an application references it directly, and that is a
LOAD-FAIL this corpus has not yet raised for this band. Each identifier below was read directly
out of the local SDK's `UTCoreTypes.h`, not recalled or guessed:

| Constant | Identifier |
| --- | --- |
| `UTTypeItem` | `public.item` |
| `UTTypeContent` | `public.content` |
| `UTTypeData` | `public.data` |
| `UTTypeDirectory` | `public.directory` |
| `UTTypeURL` | `public.url` |
| `UTTypeFileURL` | `public.file-url` |
| `UTTypeText` | `public.text` |
| `UTTypePlainText` | `public.plain-text` |
| `UTTypeUTF8PlainText` | `public.utf8-plain-text` |
| `UTTypeImage` | `public.image` |
| `UTTypePDF` | `com.adobe.pdf` |

Each is a plain, non-`const` global, filled in once by a `constructor` function, the same
technique `CFEmptyCollections.m` already uses for `__NSArray0__`/`__NSDictionary0__`: the real
SDK header declares these `UTType *const`, but that is a promise to the header's callers, not a
constraint on how this backport's own translation unit stores them.

## What the build gate measured, not reasoned

`UTTypeIsDeclared` and `UTTypeIsDynamic` are not exported by 6.1.3's armv7 release -
`build-gate.lua`'s own imports check flagged both as weak imports the release resolves to NULL,
on the very first gate run of this change. `isDeclared`/`isDynamic` guard each call
(`UTTypeIsDeclared != NULL` / `UTTypeIsDynamic != NULL`) and answer `YES`/`NO` respectively when
the release has no such function, rather than jump to a NULL pointer - `declared`, since every
identifier this class hands out either came from a caller that already had it or resolved through
`UTTypeCreatePreferredIdentifierForTag`, which iOS 6 does carry; not `dynamic`, the same answer a
declared identifier already gets on a release new enough to have the real function.

## What differs from the system

`tags` only ever reports `UTTagClassFilenameExtension` and `UTTagClassMIMEType`, the two tag
classes `charon_acceptsPath:` and the constants above already need; the release's real registry
of additional tag classes (`com.apple.nspboard-type`, `com.apple.ostype`, and so on) is not read.
`version` and `referenceURL` are not carried - no call site was found asking for either, and iOS
6's UTI database was never asked to declare a version or a reference URL for a type in the first
place.
