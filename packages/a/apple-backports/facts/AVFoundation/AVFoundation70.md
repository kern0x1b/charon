# iOS 7's AVFoundation on a release that arrived before it: the 79 rows, read class by class

The 79 rows of `absent_AVFoundation.json` that `API_AVAILABLE(ios(7.0))` puts at 7.0. Every one of them
is a member of a class the release already carries, or of a class the release does not have at all, so
the question each row asks is not "does a name exist anywhere" but "does THIS class have THIS member on
the release the port runs on".

## The ladder, and the two questions a name cannot answer

Measured over five releases, each one read as `objc-inventory.lua` dumps through
`tools/corpus/class-scoped-rows.py`, with the ladder's own architecture choice
(`dyld.held_ladder({"armv7","armv7s"})`): 4.3 armv7, 6.0 armv7, 6.1.3 armv7, 7.0 armv7 and 7.0 armv7s as a
cross-check, 7.1 armv7.

A selector's first rung says nothing about its owner, measured twice on 2026-09-30: `fileSystemRepresentation`
reads 3.0 (another class's selector of that name) while `-[NSURL fileSystemRepresentation]` is 7.0, and
`init` reads 3.0, which is NSObject's. So each row was looked up in its OWNER's class line.

Two more traps in the same shape, both hit while measuring this file:

- **The own table is not the class.** `-[AVCompositionTrack associatedTracksOfType:]` is `ABSENT` on
  6.1.3 and `INHERITED` on 7.0 — AVCompositionTrack answers it from AVAssetTrack. An own-table-only read
  would have written the 7.0 rung down as absent too.
- **A name of the row's can belong to another class in the port itself.** `extendedLanguageTag` is one of
  the rows (on `AVMediaSelectionOption`) and the port's own `AVMetadataItem` declares
  `-extendedLanguageTag` in `AVMetadataItem+Identifiers8.m`. Grepping the tree for the name finds the
  wrong class and would have flipped a row to `implemented`.

| release | CARRIED | INHERITED | ABSENT | NO CLASS | NO PROTOCOL |
| --- | --- | --- | --- | --- | --- |
| 4.3 armv7 | 0 | 0 | 56 | 21 | 2 |
| 6.0 armv7 | 0 | 0 | 68 | 9 | 2 |
| **6.1.3 armv7** | **0** | **0** | **68** | **9** | **2** |
| 7.0 armv7 | 77 | 2 | 0 | 0 | 0 |
| 7.0 armv7s | 77 | 2 | 0 | 0 | 0 |
| 7.1 armv7 | 77 | 2 | 0 | 0 | 0 |

**What the cache said that the headers did not.** Nothing here contradicts `introduced: 7.0`: at 7.0 every
one of the 79 is on its owner, and at 6.1.3 not one is. The header annotation is confirmed for all 79 by a
read that could have refuted it. Two things the headers alone would have got wrong:

- `AVMutableAudioMixInputParameters.audioTimePitchAlgorithm` and `-[AVCompositionTrack
  associatedTracksOfType:]` are **not** on the class the row names even at 7.0; both arrive through
  `AVAudioMixInputParameters` and `AVAssetTrack`. The row's `introduced` is right and the class the row
  names is the one that would have been searched for nothing.
- The 4.3 band shows 21 `NO CLASS` against 9 at 6.0: seven of the nine owner classes arrive with iOS 6
  itself, which is why the rows carry `minimum: 6.0` and not 4.3.

## The host, asked once

`tools/host-has-row.m` over the same 79 rows, this Mac's own AVFoundation loaded,
through `coordination/heavy.sh`:

    #SUMMARY input_lines=80 parsed=79 has=71 lacks=8 malformed=0 unparsed=1

The `unparsed=1` is the queue file's trailing blank line, and the tool refused to certify the run rather
than report totals that did not cover its input. All four of its controls answered correctly
(`-[NSURLSessionTask cancel]` HAS, `-[NSURLSessionTask charonProbeNoSuchSelector]` LACKS,
`NSAttributedString` HAS, `NSCharonProbeNoSuchClass` LACKS).

The eight `LACKS` are not eight absences, and reading them as such would be the third shape of the same
trap:

| row | why the host does not answer |
| --- | --- |
| `AVCaptureDevice.autoFocusRangeRestrictionSupported` | `API_UNAVAILABLE(macos, tvos)` at `AVCaptureDevice.h:1107` |
| `AVCaptureDevice.smoothAutoFocusSupported` | `API_UNAVAILABLE(macos, tvos)` at `AVCaptureDevice.h:1127` |
| `AVCaptureDeviceFormat.videoBinned` | `API_UNAVAILABLE(macos)` at `AVCaptureDevice.h:2590` |
| `AVCaptureStillImageOutput.stillImageStabilizationSupported` | `API_UNAVAILABLE(macos)` at `AVCaptureStillImageOutput.h:79` |
| `AVCaptureStillImageOutput.stillImageStabilizationActive` | `API_UNAVAILABLE(macos)` at `AVCaptureStillImageOutput.h:99` |
| `-[AVAssetResourceLoaderDelegate resourceLoader:didCancelLoadingRequest:]` | the row's owner is a **protocol**, and the probe asks `NSClassFromString` (`tools/host-has-row.m:63`), which no protocol answers |
| `-[AVPlayerItemLegibleOutputPushDelegate legibleOutput:didOutputAttributedStrings:nativeSampleBuffers:forItemTime:]` | the same |
| `AVAssetResourceLoadingRequest.cancelled` | the property's getter is `isCancelled` (`AVAssetResourceLoader.h:216`) and the probe's property branch asks the property's own name and `set…:` only (`tools/host-has-row.m:82-88`) |

So **no row of the 79 is a capability the host lacks.** Five are Apple's own annotation, three are the
probe's shape. The last one is a defect in a shared tool, reported and not patched here:
`tools/host-has-row.m`'s property branch does not try the `is` spelling, which
`tests/backports/host/mediaplayeritem/` documented for MPMediaItem and which is now measured a third time.

And one row runs the other way: the iOS SDK marks `videoFieldOfView` `API_UNAVAILABLE(macos)` at
`AVCaptureDevice.h:2580`, and the macOS runtime answers it anyway, so the annotation is about the
documented availability and not about what the framework's own binary carries.

## What each owner carries at 6.1.3 where 7.0 has the row

Own instance selectors, read from each release's own class line. This is the substrate a port would build
on, and it is what the rows now name.

| class | 6.1.3 | 7.0 | at 6.1.3, where 7.0's member is not |
| --- | --- | --- | --- |
| `AVCaptureDevice` | 100 | 134 | `-focusMode`, `-setFocusMode:`, `-isFocusModeSupported:`, `-lockForConfiguration:`, `-focusPointOfInterest` — no focus **range**, no smooth focus |
| `AVCaptureDeviceFormat` | 11 | 39 | `-isBinned`, `-hasBinned`, `-formatDescription`, `-supportedStabilizationMethod`, `-videoSupportedFrameRateRanges` |
| `AVCaptureSession` | 84 | 91 | 7.0 adds `-masterClock`, `-_determineMasterClock`, `-_setMasterClock:`; 6.1.3 has no clock member at all |
| `AVCaptureInputPort` | 11 | 14 | `-input`, `-mediaType`, `-formatDescription`, `-isEnabled`, `-setEnabled:`, `-setOwner:` — no clock |
| `AVCaptureMetadataOutput` | 13 | 18 | 7.0 adds `-rectOfInterest`, `-setRectOfInterest:`; 6.1.3 has `-metadataObjectTypes`, `-availableMetadataObjectTypes`, `-metadataObjectsDelegate` |
| `AVCaptureOutput` | 26 | 29 | `-updateMetadataTransformForCaptureOptions:`, `-transformedMetadataObjectForMetadataObject:connection:` — the metadata transform is kept, the public rect conversion is not |
| `AVCaptureVideoPreviewLayer` | 54 | 58 | 7.0 adds the two rect conversions; 6.1.3 has `-pointForCaptureDevicePointOfInterest:`, `-captureDevicePointOfInterestForPoint:`, `-rectForCaptureDeviceFaceRect:` |
| `AVPlayerItemAccessLogEvent` | 20 | 32 | 6.1.3 keeps only the aggregates: `indicatedBitrate`, `observedBitrate`, `numberOfBytesTransferred`, `numberOfSegmentsDownloaded`, `segmentsDownloadedDuration`, `numberOfStalls`, `numberOfMediaRequests`, `numberOfServerAddressChanges`, `durationWatched`, and `initWithDictionary:` |
| `AVVideoCompositionLayerInstruction` | 21 | 27 | `-getOpacityRampForTime:startOpacity:endOpacity:timeRange:` and its transform twin are there; the crop ramp and `-setCropRectangle:atTime:` are 7.0's, and 6.1.3 has no crop member to store one in |
| `AVMediaSelectionOption` | 24 | 30 | `-locale`, `-optionID`, `-_title`, `-propertyList`, `-dictionary`, `-metadataForFormat:`; 7.0 adds `displayName`, `displayNameWithLocale:`, `extendedLanguageTag` |

`CMClockGetHostTimeClock` is carried from 6.0 (`tools/cache-index/first-rung.py`, with `_NSFileSize`
answering 3.0 as the index's own control), so the clock type is on the floor; what 6.1.3 lacks is any way
to reach one from the capture stack.

## Reproducing

    CHARON_ROOT=$PWD xmake l tools/corpus/objc-inventory.lua ~/.charon/dyld/6.1.3/dyld_shared_cache_armv7 \
        > 6.1.3.armv7.inventory.tsv
    CHARON_ROOT=$PWD xmake l tools/corpus/objc-inventory.lua ~/.charon/dyld/7.0/dyld_shared_cache_armv7 \
        > 7.0.armv7.inventory.tsv
    python3 tools/corpus/class-scoped-rows.py --inventory 6.1.3 7.0 \
        -- $HOME/Git/projects/ios/coordination/corpus/queue/avfoundation-7_0.tsv

The tool prints three controls per release and writes no row if any of them is wrong, because `ABSENT` is
what a reader that read nothing produces.