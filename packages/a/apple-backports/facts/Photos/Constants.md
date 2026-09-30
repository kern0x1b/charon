# The constants of the families this port does not carry

Eight `NSString * const` of the content editing, live photo and cloud identifier families are `absent`
in `registry/Photos/`, and each row's reason said only that "the constant arrived in iOS 8/9.1/11/15".
That is not a reason a reader can check and not a value: the port does not carry these families, and a
constant whose value nobody has read is a name. This page is the value, read out of a device's own
Photos.framework, and what it would take for each row to become `implemented`.

## The values, and where they were read

`tools/corpus/cache-value.lua` over `$HOME/.charon/dyld/16.0/dyld_shared_cache_arm64e` -- a split
cache, a 393216-byte header and the bodies in `.01` ... `.44`, read through the port's own cache reader
(`modules/apple/dyld.lua`) because the address space of a split cache and the slide a stored pointer
carries are that code's business, not a second parser's. The tool prints, per symbol, the image that
exports it, the address, and the constant string the pointer in the symbol's storage names. Every one
of the eight is exported by `/System/Library/Frameworks/Photos.framework/Photos`:

| symbol | introduced | value | address |
| --- | --- | --- | --- |
| `PHContentEditingInputCancelledKey` | 8.0 | `PHContentEditingInputCancelledKey` | `0x1d5e7f7d8` |
| `PHContentEditingInputErrorKey` | 8.0 | `PHContentEditingInputErrorKey` | `0x1d5e7f7d0` |
| `PHContentEditingInputResultIsInCloudKey` | 8.0 | `PHContentEditingInputResultIsInCloudKey` | `0x1d5e7f7e0` |
| `PHLivePhotoInfoCancelledKey` | 9.1 | `PHLivePhotoInfoCancelledKey` | `0x1d5e7dcb8` |
| `PHLivePhotoInfoErrorKey` | 9.1 | `PHLivePhotoInfoErrorKey` | `0x1d5e7dca8` |
| `PHLivePhotoInfoIsDegradedKey` | 9.1 | `PHLivePhotoInfoIsDegradedKey` | `0x1d5e7dcb0` |
| `PHLivePhotoShouldRenderAtPlaybackTime` | 11.0 | **`LivePhotoShouldRenderAtPlaybackTime`** | `0x1d5e7fcc8` |
| `PHLocalIdentifiersErrorKey` | 15.0 | `PHLocalIdentifiersErrorKey` | `0x1d5e7f440` |

Seven of the eight are a string equal to their own name. **The eighth is not**: the option key of
`-[PHLivePhotoEditingContext prepareLivePhotoForPlaybackWithTargetSize:options:]` is
`LivePhotoShouldRenderAtPlaybackTime`, with no `PH` in front, which is why a port that writes
`@"PHLivePhotoShouldRenderAtPlaybackTime"` -- the guess every other one of these invites -- exports a
key no system dictionary is built with. The five keys `PHImageManager8.m` already carries were read in
the same run and each is a string equal to its own name, so what that file does is right for a reason
that can now be repeated.

```
$ CHARON_ROOT=$PWD xmake l tools/corpus/cache-value.lua \
    $HOME/.charon/dyld/16.0/dyld_shared_cache_arm64e symbols.tsv
#cache	arm64e	8
PHLivePhotoShouldRenderAtPlaybackTime	/System/Library/Frameworks/Photos.framework/Photos	0x1d5e7fcc8	30b8dfdf01002000	3755980848	9007207305689136	...	0x1dfdfb830	LivePhotoShouldRenderAtPlaybackTime	8	264
```

## The first held rung of each name

`tools/cache-index/first-rung.py`, which answers presence and not the release a name was introduced
in, and which wants the name as the cache spells it -- for a C symbol the Mach-O underscore, since
`PHLivePhotoShouldRenderAtPlaybackTime` read `NONE` and `_PHLivePhotoShouldRenderAtPlaybackTime` read
`11.0`:

| name | first held rung | header's `introduced` |
| --- | --- | --- |
| `PHContentEditingInputCancelledKey` | 8.0 | 8.0 |
| `PHContentEditingInputErrorKey` | 8.0 | 8.0 |
| `PHContentEditingInputResultIsInCloudKey` | 8.0 | 8.0 |
| `PHLivePhotoInfoCancelledKey` | 9.1 | 9.1 |
| `PHLivePhotoInfoErrorKey` | 9.1 | 9.1 |
| `PHLivePhotoInfoIsDegradedKey` | 9.1 | 9.1 |
| `_PHLivePhotoShouldRenderAtPlaybackTime` | 11.0 | 11.0 |
| `PHLocalIdentifiersErrorKey` | 16.0 | 15.0 |

The 15.0 row reads 16.0 because the held set has no rung between `12.0` and `16.0` -- the arm64e rungs
above 12.0 are `16.0` and `18.0` -- so the oldest held release that carries the name is one above the
release that introduced it. That is the tool's own rule and not a disagreement with the header.

## Why the rows stay `absent`

A constant is landed when the thing that produces or consumes it exists, because a key nothing builds
a dictionary with is a name with the right value and no user -- the shape the tree forbids. None of the
three families is carried, and each is absent for a reason of its own:

- **Content editing (8.0).** The three keys are the keys of the info dictionary
  `-[PHAsset requestContentEditingInputWithOptions:completionHandler:]` hands its result handler, and
  that request is not in the registry at all. It becomes implementable over the port's own store: the
  asset's full-size image is readable through the same `ALAssetRepresentation` the image manager
  already uses, and the output is a file the change block writes back as a new asset. The keys land
  with it.
- **Live photos (9.1 and 11.0).** The three info keys belong to
  `+[PHLivePhoto requestLivePhotoWithResourceFileURLs:placeholderImage:targetSize:contentMode:resultHandler:]`
  and the option key to the live photo editing context. A live photo is a still image and a video
  carrying Apple's paired-media metadata, and iOS 6 has neither the reader for that metadata nor a
  Photos application that would use it: `ALAssetsLibrary` can add a photo and a video and cannot pair
  them, and no release this port supports exposes the pairing. `PHLivePhoto` is therefore not carried
  and cannot be, and the keys stay with it.
- **Cloud identifiers (15.0).** `PHLocalIdentifiersErrorKey` is a key in the `userInfo` of the error
  `-[PHPhotoLibrary localIdentifierMappingsForCloudIdentifiers:]` reports when a cloud identifier
  matched **more than one** resource (`PHPhotosErrorMultipleLocalIdentifiersFound`, 3202). A release
  with no iCloud container can match nothing at all, so that user info has no producer here whatever
  else the 15.0 family does. The other three 15.0 rows are implementable and are not blocked by this.

Source: the header of iOS 16.4 for the declarations and the codes; `tools/corpus/cache-value.lua` over
the arm64e cache of 16.0 for every value and every address above, which is the device's own Photos and
not the host's library; `tools/cache-index/first-rung.py` over the 50 held rungs for the presence
column. What Apple's Photos *does* with these keys, and what a system library answers for an
identifier it has never seen, is a separate question and is not answered here.
