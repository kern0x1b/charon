# Changes to the photo library, iOS 8.0

`-[PHPhotoLibrary performChanges:completionHandler:]` and `-performChangesAndWait:error:` run a block that makes change requests,
and apply the requests together. iOS 6 has one way to change the library: an application adds an image or a video to the saved photos
through `ALAssetsLibrary`. So the change that can be made is a creation.

## What is made

`+[PHAssetChangeRequest creationRequestForAssetFromImage:]`, `...FromImageAtFileURL:` and `...FromVideoAtFileURL:` are made
into a write to the saved photos: an image with `writeImageToSavedPhotosAlbum:`, the bytes of an image file with
`writeImageDataToSavedPhotosAlbum:metadata:`, a video with `writeVideoAtPathToSavedPhotosAlbum:`. A creation date and a
location set on the request are written as the EXIF, TIFF and GPS metadata of the image (an image with either set is written from its JPEG data, at full quality). A file that is not an
image, or a video the saved photos cannot hold, gives nil, as the header says.

`placeholderForCreatedAsset` is a `PHObjectPlaceholder` whose identifier is a token before the write, and is the address of the new asset
after it; the token also finds the asset with `+[PHAsset fetchAssetsWithLocalIdentifiers:options:]`, and is kept between launches in the
application support folder of the application.

`+[PHAssetCreationRequest creationRequestForAsset]` (iOS 9) is the same kind of change request, staged instead of written immediately:
`addResourceWithType:data:options:` and `addResourceWithType:fileURL:options:` accept exactly one resource, photo or video, and the
commit writes it the same way the iOS 8 creation request does. A second resource, or a resource type other than photo or video
(adjustment data, an alternate photo, a live photo pairing), fails the change with a reason. `+supportsAssetResourceTypes:` answers
YES only for a single-element array naming the photo or the video type. `+[PHAssetResource assetResourcesForAsset:]` (iOS 9) describes
the one resource an iOS 6 asset already has, read from `ALAssetRepresentation` (`defaultRepresentation`) rather than from a Photos
database row; `+assetResourcesForLivePhoto:` always gives an empty array, since no live photo can exist on this release.

Albums are the one other thing this release lets an application change. `+[PHAssetCollectionChangeRequest
creationRequestForAssetCollectionWithTitle:]` and `+changeRequestForAssetCollection:` (only for a regular album — a smart album or one
synced from elsewhere is refused) are made into `-[ALAssetsLibrary addAssetsGroupAlbumWithName:resultBlock:failureBlock:]` and
`-[ALAssetsGroup addAsset:]`; `addAssets:` queues assets to append at commit, and `placeholderForCreatedAssetCollection` resolves like
the asset placeholder above. `addAssets:` takes a `PHAsset` or, the documented way to add an asset to an album in the same change
that creates it, the `PHObjectPlaceholder` such a creation request gives back; the placeholder is resolved to the asset it wrote
right before it is added to the album, so a change block must add the asset's creation request before the album request that
references its placeholder, in the order this port runs a block's requests. iOS 6 has no way through `ALAssetsLibrary` to rename an album, reorder or remove its assets, or delete an
album at all, so `setTitle:` on an existing album, `insertAssets:atIndexes:`, `removeAssets:`, `removeAssetsAtIndexes:`,
`replaceAssetsAtIndexes:withAssets:`, `moveAssetsAtIndexes:toIndex:` and `+deleteAssetCollections:` all fail the change with a reason,
before anything is written.

The block is run first and its requests are checked all together before any is written. A block called outside a change raises an
`NSInternalInconsistencyException` with the text of iOS 8. The completion handler is called once, off the main thread, with the
success and an error in the domain `PHPhotosErrorDomain`. No access answers `PHPhotosErrorAccessUserDenied` or `PHPhotosErrorAccessRestricted`.

## Reading a resource back

`+[PHAssetResourceManager defaultManager]` (iOS 9) gives the bytes of a `PHAssetResource` back, on the same `ALAssetRepresentation` the
resource was built from, one chunk at a time, as the documentation of iOS 9 says Photos does ("calls your handler block at least
once, progressively providing chunks of data"; the complete data is their concatenation):
`-requestDataForAssetResource:options:dataReceivedHandler:completionHandler:` reads the representation with
`getBytes:fromOffset:length:error:` one chunk after another and calls `dataReceivedHandler` with each, then `completionHandler` with
`nil`; `-writeDataForAssetResource:toFile:options:completionHandler:` writes each chunk as it is read. Only one chunk is held at a
time, so a video is never read into memory whole. A chunk is 1 MiB here, the port's own choice: the size Photos of iOS 9 and later uses
cannot be measured on this machine, since that needs a Photos library with assets in it and the host's one library is the
owner's, and the devices run iOS 6. Nothing of the API depends on it; the device test holds what does not depend on the size: the chunks, none
empty, are together the bytes of a direct read of the asset, and a video of several megabytes is not handed over in one piece.

The file of `writeDataForAssetResource:` is written into a file of its own beside the given one and renamed into place when every
chunk is in: a file already there is replaced on success, as the whole-file atomic write here did before, and left as it was
when the read or a write fails, with the file system's error. What Photos itself does with a file that is already there is not
measured, for the same reason as the chunk size; the documentation says only that it writes the data "progressively" into the file.

Either call gives `completionHandler` an error, and never calls `dataReceivedHandler` again, when the asset behind the resource's
`assetLocalIdentifier` is gone (`PHPhotosErrorIdentifierNotFound`), the asset has no representation (`PHPhotosErrorMissingResource`),
or the release gives no more bytes before the representation's own `size` (its own error, or `PHPhotosErrorInternalError` when it
gives none) — the read never ends on a silently short answer. `PHAssetResourceRequestOptions.networkAccessAllowed` is held but
changes nothing, since the read never reaches the network; `progressHandler`, when set, is called after each chunk with the part
read so far, the last time with `1.0`. The read runs on a global queue after the call returns, and the handlers of one request are
called one after another from it, so a caller can cancel it: `-cancelDataRequest:` takes the request out of the manager's pending
ones, and the read looks at that before every chunk. A request cancelled before its first chunk calls `dataReceivedHandler` never,
one cancelled during the read no more after that, and either calls `completionHandler` once, with `PHPhotosErrorUserCancelled`
(3072, which the header documents for "the asset resource or editing request"); a cancel after the last chunk still completes it
cancelled, which the documentation allows ("a non-nil error when the data is complete if the user cancels"). A request that has
completed already is not changed by a cancel. The earlier text here, that the read had always finished before a caller could
cancel, was wrong: the read was asynchronous already, and a cancel reached nothing.

## What is refused

The library of iOS 6 lets an application add to it and read it, not delete from it and not change what is in it. `+deleteAssets:`, an
edit of an asset with `+changeRequestForAsset:`, a favorite, a hidden asset and a date or a location of an existing asset make the whole
change fail with `PHPhotosErrorChangeNotSupported` and a reason, before anything is written. The requests that come with the
content editing (`contentEditingOutput`, `revertAssetContentToOriginal`) are absent; the album and resource requests above are the
only two exceptions, and each still refuses whatever `ALAssetsLibrary` itself cannot do.

Once the checks pass the writes are made one after another; a write that then fails (the disk is full) leaves the ones before it made, as the release has no way to undo them.

Source: the header of iOS 16.4; the host's Photos for the text of the exception and the
error codes; `ALAssetsLibrary` of an iPad 2 running 6.1.3 for the iOS 8 creation request. The iOS 9 creation request with its placeholder
passed to `addAssets:` of an album created in the same change, the album found again by its placeholder with that one asset in it,
the refused rename, reorder and delete (`PHPhotosErrorChangeNotSupported`, title unchanged afterwards), the asset resource, and the
resource manager (completion once with `nil`, progress once with `1.0`, within five seconds) were run on an iPad 2 running 6.1.3 on
2026-09-23, called off the main thread, 17 of 19 checks passing; the two others are the release's rewrite below. The refusal of
an album name in use below was run there too: 3300, and the number of 8-by-8 saved photos the same before and after.
The change observers were run on the same iPad on 2026-09-23 with `tests/backports/device/photoschanges8.m`, an application of its
own with the photo library allowed: 22 checks, 0 failures.

The saved photos of iOS 6 do not keep the bytes they are given: a 726-byte JPEG written with
`writeImageDataToSavedPhotosAlbum:metadata:` and `nil` metadata reads back as 1929 bytes, measured the same with no port code on the
path. The resource and the resource manager hand back what the library stores — identical to a direct `ALAssetsLibrary` read of the
same asset — not the bytes given to the creation request.

An album name is unique on iOS 6: `addAssetsGroupAlbumWithName:` answers `nil` for a name already in use. A creation request whose
title is already the name of an album of the device, or of an album created earlier in the same change, fails the whole change with
`PHPhotosErrorChangeNotSupported` and a reason, when the requests are checked — before anything is written, so none of the change's
assets are left behind. Names are compared exactly: the release itself made an album whose name differs from an existing one only
in case. The code is the header's (3300, "The change request is not supported as configured"), the one this port
gives every change iOS 6 cannot make; what the system's Photos answers for a duplicate title was not measured, since this machine
has no Catalyst and the host's own Photos holds the owner's library. A name that collides only at the write, on something the check
does not see, still fails the change there, after the writes before it. When the release refuses to list the albums (an
application denied or restricted, or a library whose data is unavailable), the check has no answer, and the change fails there
with the release's own error (`ALAssetsLibraryErrorDomain`, -3311 "User denied access" for a denied process) instead of taking
the refusal for "no such album" and writing on; `tests/backports/device/photosalbums8.m` holds it on an iPad 2, in a daemon the
release denies. A fetch of albums, which has no way to report an error, is empty then, as it is for an application that may not
read, and the refusal is said in the log.
