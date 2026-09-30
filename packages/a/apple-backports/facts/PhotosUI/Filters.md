# The picker's filters, iOS 15.0 and 16.0

Eleven rows: the five filters of iOS 15 that name a kind of asset the header lists
(`panoramasFilter`, `screenshotsFilter`, `screenRecordingsFilter`, `slomoVideosFilter`,
`timelapseVideosFilter`), the three of iOS 16 (`depthEffectPhotosFilter`, `burstsFilter`,
`cinematicVideosFilter`), and the three class methods that build a filter out of other
filters (`playbackStyleFilter:`, `allFilterMatchingSubfilters:`, `notFilterOfSubfilter:`).
The rows are in `registry/PhotosUI/ios15.json` and `registry/PhotosUI/ios16.json`; the code
is in `PHPickerFilter15.m` and `PHPickerFilter16.m`, which are categories on the class the
14.0 object implements, because an object carries the API of one release only.

Source: `PHPicker.h` of the iOS 16.4 SDK, which is the SDK this package compiles against and
which declares all eleven with their availability; `sdk-26.2-surface.tsv` for the same eleven
by name, kind and introduced release; `ALAsset.h` of the same SDK for what the release's
library can say about an asset; and `tools/cache-index/first-rung.py` over the 50 held rungs
for which of the asset-type constants exist in a release at all.

## What a filter is here

A filter restricts which assets the picker shows, and the picker this port carries shows them
with `UIImagePickerController` of iOS 6, which takes two media types: `public.image` and
`public.movie`. A filter is therefore a set over those two, and a set over two elements has
four values. All four are already objects the 14.0 filter object makes:

| the set | the filter |
| --- | --- |
| `{image}` | `+imagesFilter` |
| `{movie}` | `+videosFilter` |
| `{image, movie}` | `+anyFilterMatchingSubfilters:@[images, videos]` |
| `{}` | `+livePhotosFilter`, which names nothing |

So a filter composed out of other filters needs no state of its own: the composition is
computed here and the answer is one of the four objects above. That is why the three class
methods of iOS 15 are built from the four filters of iOS 14 rather than from a new kind, and
why `-[PHPickerFilter copyWithZone:]` needs no change: a copy is the same object.

## Where iOS 6 differs

The release's library answers `ALAssetPropertyType` with one of three values, and its own
header says so: `ALAssetTypePhoto`, `ALAssetTypeVideo` or `ALAssetTypeUnknown`
(`ALAsset.h:21` and `:33-35` of the 16.4 SDK). Nothing finer exists. Measured over the 50
held rungs, `_ALAssetTypePanorama` and `_ALAssetTypePhotoStream` are in none of them
(`first-rung.py` answers `NONE` for both, while `_ALAssetTypePhoto` and `_ALAssetTypeVideo`
read `4.0`). So of the eight kind filters:

- `playbackStyleFilter:` is the one that names something. `-[PHAsset playbackStyle]` is the
  port's own answer for an asset - an image, a video, or `Unsupported` when the library
  cannot say (`PHAsset8.m:49`, registered under the `PHAsset` class row) - so a filter of
  style `Image` is the image filter and a filter of style `Video` is the video filter, and the
  picker shows images or movies. The other four cases of the enum, `Unsupported`,
  `ImageAnimated`, `LivePhoto` and `VideoLooping`, name what the release keeps no record of:
  an animated image, a live photo and a looping video are all of iOS 9.1 or later and none of
  them is in the library this port reads, so the filter built for one matches nothing.
- the other ten match nothing, because a panorama, a screenshot, a screen recording, a slow
  motion clip, a time lapse, a depth effect photo, a burst and a cinematic video are all one
  and the same to this release. The filter that says so is `+livePhotosFilter`, and the
  picker then presents nothing and calls the delegate with no results once it has appeared -
  the answer `facts/Photos/PHPicker.md` already gives for a live photo, and the reason that
  path exists.

A filter of nothing is not the port declining to answer. It is the filter the release's own
library can be asked for, and `-[PHPickerFilter charon_mediaTypes]`, the seam the 14.0 picker
reads, is empty for it, which is what the picker acts on.

## The three compositions

`allFilterMatchingSubfilters:` keeps the media types every subfilter names, and
`notFilterOfSubfilter:` keeps what is left of the two once the subfilter has taken its own.
Two edges are decisions, not measurements, because the header's own API cannot be asked what
a filter matches - there is no public query for it, on this port or on the host:

- an empty array constrains nothing, so `allFilterMatchingSubfilters:@[]` is every media
  type. That is the reading of "AND-ing the filters in a given array", and it is the
  opposite of `anyFilterMatchingSubfilters:@[]`, which the 14.0 object already answers with
  nothing, as OR-ing over nothing must.
- a `nil` array is read as an empty one. The header's parameter is not nullable, and the
  release's picker asks for nothing else.

## What is not here

The picker still shows the release's own picker, and a filter of panoramas therefore shows
nothing rather than the library's panoramas. That is a property of `UIImagePickerController`
of iOS 6 - no API of it restricts the library to a subset - and not of the filter, which
answers what the release's library can say. Making the picker show a subset would mean
carrying a list of the library's assets in the picker, which is a row about
`PHPickerViewController` and not about these eleven.
