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
resource was built from: `-requestDataForAssetResource:options:dataReceivedHandler:completionHandler:` reads the whole representation
with `getBytes:fromOffset:length:error:` in one call (iOS 6 has no chunked network fetch to page through), then calls
`dataReceivedHandler` once with everything and `completionHandler` with `nil`; `-writeDataForAssetResource:toFile:options:completionHandler:`
writes the same bytes to the given file. Either call gives `completionHandler` an error, and never calls `dataReceivedHandler`, when the
asset behind the resource's `assetLocalIdentifier` is gone or the release hands back fewer bytes than the representation's own `size` —
the read is never allowed to answer with a silently short buffer. `PHAssetResourceRequestOptions.networkAccessAllowed` is held but
changes nothing, since the read never reaches the network; `progressHandler`, when set, is always called exactly once, with `1.0`, on
success, so a caller waiting on it is never left waiting forever. `-cancelDataRequest:` is a no-op: by the time a caller could call it,
the read this release can do has already finished.

## What is refused

The library of iOS 6 lets an application add to it and read it, not delete from it and not change what is in it. `+deleteAssets:`, an
edit of an asset with `+changeRequestForAsset:`, a favorite, a hidden asset and a date or a location of an existing asset make the whole
change fail with `PHPhotosErrorChangeNotSupported` and a reason, before anything is written. The requests that come with the
content editing (`contentEditingOutput`, `revertAssetContentToOriginal`) are absent; the album and resource requests above are the
only two exceptions, and each still refuses whatever `ALAssetsLibrary` itself cannot do.

Once the checks pass the writes are made one after another; a write that then fails (the disk is full) leaves the ones before it made, as the release has no way to undo them.

Source: the header of iOS 16.4; the host's Photos for the text of the exception and the
error codes; `ALAssetsLibrary` of an iPad 2 running 6.1.3 for the iOS 8 creation request. The iOS 9 creation request, the asset
resource, the resource manager, and the collection change request are verified against this port's own `ALAssetsLibrary` calls and
against the SDK header (`PHAssetCreationRequest` inherits from `PHAssetChangeRequest`), but not yet run on device.
