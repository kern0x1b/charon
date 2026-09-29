# AVFoundation: what is still owed, and why it is not here

The corpus carries **590** `absent` AVFoundation rows at `2c7d8a7b8`. This file is the plan for them,
in the order they can honestly be answered. It exists so that a deferred row is a line with a reason
and a measurement on it, and never a row quietly left `absent` as though `absent` were a finished
answer.

**Answered so far: 47** - the metadata key-space names and the coordinated-playback and player-rate
strings, in [MetadataKeySpaces.md](MetadataKeySpaces.md) and
[CoordinatedPlaybackReasons.md](CoordinatedPlaybackReasons.md), each value read out of the host's own
framework at runtime and diffed between Apple's build and the port's.

**Left: 543** - the 17 below, and 526 more in 228 families.

## The seventeen of this family, and the measurement that defers them

| row | kind | introduced | owner |
| --- | --- | --- | --- |
| `AVDateRangeMetadataGroup` | class | 9.0 | `AVDateRangeMetadataGroup` |
| `AVMetadataBodyObject` | class | 13.0 | `AVMetadataBodyObject` |
| `AVMetadataCatBodyObject` | class | 13.0 | `AVMetadataCatBodyObject` |
| `AVMetadataDogBodyObject` | class | 13.0 | `AVMetadataDogBodyObject` |
| `AVMetadataGroup` | class | 9.0 | `AVMetadataGroup` |
| `AVMetadataHumanBodyObject` | class | 13.0 | `AVMetadataHumanBodyObject` |
| `+[AVMetadataItem metadataItemWithPropertiesOfMetadataItem:valueLoadingHandler:]` | method | 9.0 | `AVMetadataItem` |
| `+[AVMetadataItem metadataItemsFromArray:filteredByIdentifier:]` | method | 8.0 | `AVMetadataItem` |
| `+[AVMetadataItem metadataItemsFromArray:filteredByMetadataItemFilter:]` | method | 7.0 | `AVMetadataItem` |
| `AVMetadataItem.startDate` | property | 9.0 | `AVMetadataItem` |
| `AVMetadataItemFilter` | class | 7.0 | `AVMetadataItemFilter` |
| `AVMetadataItemValueRequest` | class | 9.0 | `AVMetadataItemValueRequest` |
| `AVMetadataSalientObject` | class | 13.0 | `AVMetadataSalientObject` |
| `AVMutableDateRangeMetadataGroup` | class | 9.0 | `AVMutableDateRangeMetadataGroup` |
| `AVMutableMetadataItem.startDate` | property | 9.0 | `AVMutableMetadataItem` |
| `-[AVTimedMetadataGroup copyFormatDescription]` | method | 8.0 | `AVTimedMetadataGroup` |
| `-[AVTimedMetadataGroup initWithSampleBuffer:]` | method | 8.0 | `AVTimedMetadataGroup` |

Two measurements decide all seventeen, and both were taken on the host before a line was written:

1. **There is no public way to build the objects, so a differential has no common input.** Asked
   directly with `class_getClassMethod:` / `class_getInstanceMethod:` on the host build:
   `+[AVMetadataItem metadataItemWithIdentifier:value:extraAttributes:]` **no**,
   `-[AVMetadataGroup initWithItems:]` **no**, `+[AVDateRangeMetadataGroup dateRangeGroupWithItems:]`
   **no**, `-[AVMetadataItemFilter initWithIdentifiers:]` **no**, and `-[AVMetadataItemFilter identifiers]`
   **no** - the host's spelling of that one is `allowList`. What the host *does* answer is
   `-[AVMetadataGroup items]`, `-[AVDateRangeMetadataGroup startDate]`, `-endDate`,
   `-[AVMutableDateRangeMetadataGroup setItems:]`, `-setStartDate:`, `-setEndDate:`. So the accessors
   can be compared once there is something to call them on, and the constructors cannot be compared
   at all, because Apple has no public constructor either.
2. **The body-object classes carry state a detection produces.** On the host, by
   `class_copyMethodList` and `class_getInstanceSize`: `AVMetadataBodyObject` 5 own methods, 24
   bytes; `AVMetadataCatBodyObject` 6 and 24; `AVMetadataDogBodyObject` 6 and 24;
   `AVMetadataHumanBodyObject` 8 and **40**; `AVMetadataSalientObject` 7 and 24. A class of that name
   with an empty body would satisfy every `isKindOfClass:` and answer nothing for `timeRange`,
   `bodyObjectType` or `confidence`. That is the silent shape the registry README names, so these
   rows want `inert` with the effect written down, or a real body-object fed by a capture pipeline -
   and neither is a row to close by writing a file.

`AVMetadataItem`'s three class methods and its `startDate`, and `AVTimedMetadataGroup`'s two, are in
this list for the same reason and not for a third: `+metadataItemsFromArray:filteredBy...` filters
items the port cannot be handed, and `-[AVTimedMetadataGroup initWithSampleBuffer:]` needs a
`CMSampleBuffer` of timed metadata that no test in this tree builds yet.

**What would unblock them:** a host test that builds one `AVMetadataItem` and one timed-metadata
sample buffer from a fixture file, which makes the accessors comparable. That is the next piece of
work, and it is a piece of test infrastructure, not a row.

## The rest, largest families first

| family | absent rows |
| --- | --- |
| `AVCaptureDevice` | 69 |
| `AVCaptureDeviceFormat` | 31 |
| `AVPlayerItem` | 27 |
| `AVAsset` | 16 |
| `AVPlayer` | 16 |
| `AVAssetTrack` | 15 |
| `AVPlayerItemAccessLogEvent` | 12 |
| `AVMutableVideoComposition` | 11 |
| `AVAssetWriterInput` | 10 |
| `AVCaptureMovieFileOutput` | 10 |
| `AVVideoComposition` | 10 |
| `AVAssetWriter` | 9 |
| `AVCaptureStillImageOutput` | 9 |
| `AVAssetExportSession` | 8 |

Of the families above, these are pure data and can be answered the way this slice was, one
`dlsym`-measurable table or one constructible object at a time, in this order:

- **the format and configuration descriptors** - `AVCaptureBracketedStillImageSettings`,
  `AVCaptureAutoExposureBracketedStillImageSettings`, `AVCaptureManualExposureBracketedStillImageSettings`,
  `AVCapturePhotoBracketSettings`, `AVCaptureSystemPressureState`, `AVAssetDownloadConfiguration`,
  `AVAssetDownloadContentConfiguration`, `AVAssetVariant*`, `AVAssetSegmentReport*`,
  `AVAssetWriterInputPassDescription`, `AVContentKey*`, `AVCoordinatedPlaybackSuspension`. All
  constructible and readable, none touching a device.
- **the timing and range classes** - `AVMediaSelection`, `AVMutableMediaSelection`,
  `AVMediaSelectionGroup`, `AVMediaSelectionOption`, `AVPlayerMediaSelectionCriteria`, which are
  pure ranges and options.
- **the composition and instruction classes** - `AVComposition`, `AVMutableComposition`,
  `AVCompositionTrack`, `AVMutableCompositionTrack`, `AVVideoComposition`,
  `AVMutableVideoComposition`, and the layer and time-range instruction objects. These need a media
  source, so they want the same fixture as the seventeen above.
- **the capture and session layer, last** - `AVCaptureDevice` (69 rows), `AVCaptureDeviceFormat`
  (31), the outputs, the session and the device inputs. These are the rows where the policy in the
  brief bites: hardware the device lacks answers as Apple documents (`isSupported` NO, the
  documented error), and nothing may be called on this Mac's real capture devices. That slice needs
  the device-session discipline and the coordinator's gate, not a host differential alone.
