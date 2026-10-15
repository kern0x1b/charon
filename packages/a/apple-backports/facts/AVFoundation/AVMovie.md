# AVMovie and AVMovieTrack, the read side, by forwarding

`packages/a/apple-backports/AVFoundation/AVMovie.m`: `CharonMovie` (runtime name `AVMovie`, superclass `AVAsset`) and
`CharonMovieTrack` (runtime name `AVMovieTrack`, superclass `AVAssetTrack`). Registry rows: `registry/AVFoundation/movie13.json`.

## Status of the answers

Nothing here is measured against the host yet. The host differential (two movies written by AVAssetWriter, one H.264
video track and one AAC audio track, compared member by member) is the next band's job. Each answer below is one of two
kinds, and the second kind is a design still to be checked:

- the release's own answer, handed on: every forwarded member, and the tracks, which are the inner asset's tracks wrapped;
- a design choice of this port: the list below.

## The design

A movie is an AVAsset in the 16.4 header (`AVMovie.h:57`), and a movie track an AVAssetTrack (`AVMovieTrack.h:22`).
Both classes exist on 6.1.3 only as their superclasses, so a movie holds one `AVURLAsset` made from the same URL and
options, and answers each public member from it. A method AVAsset implements for its own instance variables reads state a
movie does not have, so no inherited AVAsset behaviour is relied on for a movie's state.

- `+movieWithURL:options:`, `-initWithURL:options:`: the inner asset is `[[AVURLAsset alloc] initWithURL:options:]`.
- `+movieWithData:options:`, `-initWithData:options:`: the data is written to `NSTemporaryDirectory()` under a unique name
  with the `.mov` extension, and that file is opened. The file is removed in `-dealloc`. A write that fails logs the error
  and makes no movie (`nil`).
- `-init` is not marked unavailable in the 16.4 header, so it makes a movie with no URL, no data and no inner asset. Each
  member then answers what a message to nil answers: zero for scalars and structs (a zeroed `CMTime` is invalid), `NO`,
  `nil`; the array members answer `@[]`. The track list is empty. A plain `+new` is the same.
- `+movieWithURL:options:` and `-initWithURL:options:` with a nil URL raise `NSInvalidArgumentException`, and so do the
  data forms with nil data. The reason is this library's own wording; the host's behaviour is not measured.
- `-copyWithZone:` returns the movie itself, retained: a movie is immutable, and AVMutableMovie, which is mutable, is a
  later row. `-isEqual:` and `-hash` are not overridden: identity, as for any AVAsset instance.
- `-URL` is the URL given, or `nil` for a data movie. `-data` is the data given, or `nil` for a URL movie.
- `-defaultMediaDataStorage` is `nil`: AVMediaDataStorage is absent on this release.
- `-canContainMovieFragments` and `-containsMovieFragments` are `NO`: AVFragmentedMovie is absent on this release.
- `+movieTypes` is `[AVURLAsset audiovisualTypes]`, the file types this release's asset reads. The host's list is not known
  to be the same; that is one of the differential's questions.
- `-isCompatibleWithFileType:` is whether the file type is in `+movieTypes`.
- `-tracks` is one `AVMovieTrack` per track of the inner asset, built the first time and kept, so the same objects come
  back each time. `-trackWithTrackID:`, `-tracksWithMediaType:` and `-tracksWithMediaCharacteristic:` search that array;
  they do not forward to the inner asset.
- A track's `-asset` is the movie that made it, held weakly (the movie owns its tracks), never the inner asset.
- `-statusOfValueForKey:error:` and `-loadValuesAsynchronouslyForKeys:completionHandler:` forward to the inner asset. A
  movie with no inner asset answers the release's unknown status, and calls the handler on the main queue.

## The members forwarded

On `AVMovie` (`CharonMovie`), the public `AVAsset` members the 16.4 header declares and the 6.1.3 `AVAsset` carries, each
answered by the inner `AVURLAsset`:

`duration`, `preferredRate`, `preferredVolume`, `preferredTransform`, `naturalSize`, `providesPreciseDurationAndTiming`,
`referenceRestrictions`, `cancelLoading`, `trackGroups`, `creationDate`, `lyrics`, `commonMetadata`,
`availableMetadataFormats`, `metadataForFormat:`, `availableChapterLocales`,
`chapterMetadataGroupsWithTitleLocale:containingItemsWithCommonKeys:`,
`chapterMetadataGroupsBestMatchingPreferredLanguages:`, `availableMediaCharacteristicsWithMediaSelectionOptions`,
`mediaSelectionGroupForMediaCharacteristic:`, `hasProtectedContent`, `isPlayable`, `isExportable`, `isReadable`,
`isComposable`, `isCompatibleWithSavedPhotosAlbum`, `statusOfValueForKey:error:`,
`loadValuesAsynchronouslyForKeys:completionHandler:`. That is 29 members, plus `tracks`, `trackWithTrackID:`,
`tracksWithMediaType:` and `tracksWithMediaCharacteristic:`, answered from the movie's own track array.

On `AVMovieTrack` (`CharonMovieTrack`), the public `AVAssetTrack` members the 16.4 header declares and the 6.1.3
`AVAssetTrack` carries: `asset` (the movie), `availableMetadataFormats`, `commonMetadata`, `estimatedDataRate`,
`extendedLanguageTag`, `formatDescriptions`, `hasMediaCharacteristic:`, `isEnabled`, `isPlayable`, `isSelfContained`,
`languageCode`, `mediaType`, `metadataForFormat:`, `naturalSize`, `naturalTimeScale`, `nominalFrameRate`,
`preferredTransform`, `preferredVolume`, `samplePresentationTimeForTrackTime:`, `segmentForTrackTime:`, `segments`,
`statusOfValueForKey:error:`, `loadValuesAsynchronouslyForKeys:completionHandler:`, `timeRange`, `totalSampleDataLength`,
`trackID`. That is 26 members, `asset` among them.

## Members left out, and why

The 6.1.3 inventory (`objc-inventory` of the armv7 cache) and the 16.4 headers disagree in both directions; the header
decides what a caller can name, the inventory decides what the release answers.

- Declared by the header, not carried by 6.1.3 `AVAsset`: `metadata` (`-metadataForFormat:` is carried, the property is not).
- Carried by 6.1.3 `AVAsset`, not declared on `AVAsset` in the 16.4 header: `mediaSelectionGroups`, `compatibleTrackForCompositionTrack:`
  (the header puts it on `AVURLAsset`), `tracksWithMediaCharacteristics:`, `unusedTrackID` (the header puts it on
  `AVMutableMovie`), `alternateTrackGroups`, `audioAlternatesTrackGroup`, `subtitleAlternatesTrackGroup`,
  `preferredSoundCheckVolumeNormalization`, `trackReferences`, `-statusOfValueForKey:` without an error. These are not
  public on AVMovie, so they are not overridden; an inherited one reads AVAsset state a movie does not have, and nothing
  here promises it.
- The `AVAsset` `-mpLoadValuesAsynchronouslyForKeys:completionQueue:completionHandler:` is MediaPlayer's category: not AVFoundation.
- Newer than 6.1.3: `preferredDisplayCriteria`, `minimumTimeOffsetFromLive`, `canContainFragments`, `containsFragments`,
  `overallDurationHint`, `preferredMediaSelection`, `allMediaSelections`, `compatibleWithAirPlayVideo`. The `load...` family
  (iOS 15) is the category in `AVAssetAsyncLoading15.m` on `AVAsset`, which a movie inherits; it answers through the
  overridden accessors, so it needs no row of its own here.
- The `AVAsynchronousKeyValueLoading` protocol declares only `statusOfValueForKey:error:` and
  `loadValuesAsynchronouslyForKeys:completionHandler:`; the keys-for-collection-keys variant is not in the header.
- The `AVMovieTrack` members `mediaPresentationTimeRange`, `mediaDecodeTimeRange`, `alternateGroupID` and `mediaDataStorage`
  are not answered: their values are not measured, so they have absent rows in `movie13.json`.
- The writer pair `movieHeaderWithFileType:error:` and `writeMovieHeaderToURL:fileType:options:error:` is the later
  header-writer band; absent rows in `movie13.json`.
- `AVMutableMovie` and `AVMutableMovieTrack` are the later commit.
