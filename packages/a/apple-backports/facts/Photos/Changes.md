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

The block is run first and its requests are checked all together before any is written. A block called outside a change raises an
`NSInternalInconsistencyException` with the text of iOS 8. The completion handler is called once, off the main thread, with the
success and an error in the domain `PHPhotosErrorDomain`. No access answers `PHPhotosErrorAccessUserDenied` or `PHPhotosErrorAccessRestricted`.

## What is refused

The library of iOS 6 lets an application add to it and read it, not delete from it and not change what is in it. `+deleteAssets:`, an
edit of an asset with `+changeRequestForAsset:`, a favorite, a hidden asset and a date or a location of an existing asset make the whole
change fail with `PHPhotosErrorChangeNotSupported` and a reason, before anything is written. The requests that come with the
content editing (`contentEditingOutput`, `revertAssetContentToOriginal`) and the asset resources of iOS 9, and the change requests for collections, are absent.

Once the checks pass the writes are made one after another; a write that then fails (the disk is full) leaves the ones before it made, as the release has no way to undo them.

Source: the header of iOS 16.4; the host's Photos for the text of the exception and the
error codes; `ALAssetsLibrary` of an iPad 2 running 6.1.3.
