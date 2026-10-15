# AVMovie and AVMovieTrack, the read side, by forwarding

`packages/a/apple-backports/AVFoundation/AVMovie.m`: `CharonMovie` (runtime name `AVMovie`, superclass `AVAsset`) and
`CharonMovieTrack` (runtime name `AVMovieTrack`, superclass `AVAssetTrack`). Registry rows: `registry/AVFoundation/movie13.json`.
Host differential: `tests/backports/host/avf-movie4` (writer.m makes the movies, probe.m is built against the host and the
port, run.sh joins the tables and holds the planted control).

## Status of the answers

The differential measures each answer below against the host on three movies made by the host's AVAssetWriter
(movie-a: 1.0 s, 24 fps; movie-b: 2.0 s, 30 fps; both one H.264 video track and one AAC audio track; movie-c: movie-b with
the audio track's alternate group patched to 3) and on one movie read from data. Every compared row is equal. The data
movie is the exception and is described below.

Each answer is one of three kinds:

- the release's own answer, handed on: every forwarded member, and the tracks, which are the inner asset's tracks wrapped;
- a value the host measured, written by the port: the file-type answers, `+movieTypes`, `referenceRestrictions`,
  the duration of a movie with no asset, and the four track members read from the file;
- a design of this port that the differential does not reach (listed at the end).

## The design

A movie is an AVAsset in the 16.4 header (`AVMovie.h:57`), and a movie track an AVAssetTrack (`AVMovieTrack.h:22`).
Both classes exist on 6.1.3 only as their superclasses, so a movie holds one `AVURLAsset` made from the same URL and
options, and answers each public member from it. A method AVAsset implements for its own instance variables reads state a
movie does not have, so no inherited AVAsset behaviour is relied on for a movie's state.

- `+movieWithURL:options:`, `-initWithURL:options:`: the inner asset is `[[AVURLAsset alloc] initWithURL:options:]`.
- `+movieWithData:options:`, `-initWithData:options:`: the data is written to `NSTemporaryDirectory()` under a unique name
  with the `.mov` extension, and that file is opened. The file is removed in `-dealloc`. A write that fails logs the error
  and makes no movie (`nil`).
- `-init` makes a movie with no URL, no data and no inner asset. Its members answer what a message to nil answers: zero
  for scalars and structs, `NO`, `nil`, and the array members `@[]`. The exception is `-duration`, which answers `0/600`
  (a valid zero of the default movie timescale): the host answers that for `-init` (measured, `init duration`).
- `+movieWithURL:options:` and `-initWithURL:options:` with a nil URL raise `NSInvalidArgumentException`. The data forms
  raise for nil data and for empty data (`[data length] > 0`, as the host asserts). The exception name is the host's
  (measured); the reason text is this library's own wording and is not compared.
- `-copyWithZone:` returns the movie itself, retained (measured: the host answers the same object). `-isEqual:` and `-hash`
  are not overridden.
- `-URL` is the URL given, or `nil` for a data movie (measured). `-data` is the data given, or `nil` for a URL movie.
- `-defaultMediaDataStorage` is `nil` (measured for URL and data movies).
- `-canContainMovieFragments` and `-containsMovieFragments` are `NO` (measured for each movie read).
- `+movieTypes` is the host's six types, measured: `com.apple.m4a-audio`, `com.apple.m4v-video`, `com.apple.quicktime-audio`,
  `com.apple.quicktime-movie`, `public.3gpp`, `public.mpeg-4`. It is not the release's audiovisual list (103 types on 6.1.3).
- `-isCompatibleWithFileType:` is YES for `com.apple.quicktime-movie`, `public.mpeg-4`, `com.apple.m4v-video`, `public.3gpp`
  and `com.apple.quicktime-audio`, and NO for `com.apple.m4a-audio` and `com.microsoft.waveform-audio` (measured). It is not
  `+movieTypes` membership: the host lists m4a in movieTypes and answers NO. The host traps (SIGTRAP inside
  `FigMovieFormatWriterCanFileTypeSupportMediaType`) for `public.jpeg`, so no answer for it is measured; the port answers NO.
- `-referenceRestrictions` is `ForbidLocalReferenceToRemote` (measured for a movie made from a URL with no options). The
  inner asset's own answer is `ForbidNone`, so it is not forwarded. The options are not read for this answer.
- `-tracks` is one `AVMovieTrack` per track of the inner asset, built the first time and kept, so the same objects come
  back each time. `-trackWithTrackID:`, `-tracksWithMediaType:` and `-tracksWithMediaCharacteristic:` search that array;
  they do not forward to the inner asset.
- A track's `-asset` is the movie that made it, held weakly (the movie owns its tracks), never the inner asset (measured:
  the host answers the movie too).
- `-statusOfValueForKey:error:` and `-loadValuesAsynchronouslyForKeys:completionHandler:` forward to the inner asset. A
  movie with no inner asset answers the release's unknown status, and calls the handler on the main queue.

## The AVMovieTrack members the release does not carry

6.1.3's `AVAssetTrack` carries none of `mediaPresentationTimeRange`, `mediaDecodeTimeRange`, `alternateGroupID` or
`mediaDataStorage` (checked against the 6.1.3 inventory, `inv613.tsv`, class AVAssetTrack). They are answered as follows:

- `mediaDecodeTimeRange`: `[0, D)` in the track's media timescale, where D is the sum of the stts sample deltas. Measured
  equal to the host on every track of the three movies.
- `mediaPresentationTimeRange`: the least sample time to the greatest sample end, in the media timescale, where a sample's
  time is its decode time plus the ctts offset of its run (no offset when the track has no ctts). Measured equal to the
  host on every track of the three movies. The video tracks carry ctts boxes with non-zero (signed) offsets, so the offset
  rule is measured on those files; the reader reads the offsets as signed. Not measured: a version 0 ctts with large
  unsigned offsets, and a track with no samples (it answers the zero range in its timescale). The edit
  list is not applied; the host does not apply it on these files either (the audio tracks' presentation ranges are longer
  than their `timeRange`, which is the edit-listed one).
- `alternateGroupID`: the `alternate_group` field of the track's `tkhd` box. Measured 0 on the two AVAssetWriter movies and 3
  on movie-c, where the host reads the patched value.
- `mediaDataStorage`: `nil`. Measured nil for every track of the three movies. AVMediaDataStorage is absent on 6.1.3.

The reader is `charonReadTrackHeader` in `AVMovie.m`: it reads the movie file's own boxes (`moov`, `trak`, `tkhd`, `mdia`,
`mdhd`, `minf`, `stbl`, `stts`, `ctts`) with the layout in Apple's QuickTime File Format specification. A movie with no file
(made by `-init`), a remote URL, or a box that does not fit its parent answers an invalid range, or 0 for the alternate
group. The file is read on each call.

## Where the port is not the host, and why

- **A movie made from data.** The host cannot open the data of movie-b: its duration status is failed
  (`AVFoundationErrorDomain -11800`), it has no tracks, and it is neither readable nor playable. The port writes the bytes
  to a temporary file and opens that, so it reads the movie. The differential holds the `data-b` rows out of the comparison
  and prints them. Which behaviour the port should have is a decision for the coordinator; the port's is the one the design
  states.
- **The reason text** of the raised exceptions (the names are compared; the text is not).
- **The 6.1.3 behaviour of `-initWithAssetTrack:movie:`.** The wrapper takes NSObject's `-init`, not AVAssetTrack's: the
  release's own `-init` crashed on a wrapper on the host (a SIGSEGV in `objc_release` under this method). Whether the
  wrapper's `dealloc` is safe on 6.1.3 is not measured; the emulator probe is the next band's.
- **`-isCompatibleWithFileType:` for file types the host was not asked about**, and the host's answer for `public.jpeg`
  (a trap). The port answers NO for every type outside the five above.
- **`-referenceRestrictions` for movies made with options.** Not measured.
- **The `compatibleWithSavedPhotosAlbum` member.** iOS-only in the macOS SDK, so the probe does not ask it; the scratch copy in
  run.sh replaces its body with NO so that the file compiles on the host. The device gate builds the real one.

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
- The writer pair `movieHeaderWithFileType:error:` and `writeMovieHeaderToURL:fileType:options:error:` is the later
  header-writer band; absent rows in `movie13.json`.
- `AVMutableMovie` and `AVMutableMovieTrack` are the later commit.
