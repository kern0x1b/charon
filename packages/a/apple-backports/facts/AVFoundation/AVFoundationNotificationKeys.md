# The notification names, user-info keys and option keys

Thirty-three rows of the 526 `absent` AVFoundation rows at this base: the `NSString *const` names a
caller observes a notification by or writes into a `userInfo` dictionary, and the media-characteristic
strings a resource loader answers with. Four objects, one per release band, and no camera, no sensor
and no media anywhere in the slice.

## Open source checked

The coordinator's scout table (`charon/.agent-work/runs/oss-scout/oss-candidates.tsv`, **21 data rows** —
22 lines with the header) was read. Its candidates are the Swift runtime libraries -
swift-corelibs-foundation, swift-corelibs-libdispatch, swift-crypto, swift-collections,
swift-numerics and the rest - plus three Apple-OSS frameworks held on a separate list with their own
licence question (CoreFoundation APSL-2.0, objc4, libdispatch).

**Its `framework_breakdown` column does name AVFoundation, once.** The `apple/swift-corelibs-foundation`
row reads `Foundation=20;UIKit=4;SensorKit=3;AVFoundation=1`, and that one line is the file's only
AVFoundation mention. An earlier version of this paragraph said the column had "nothing for
AVFoundation"; that was wrong about the column, and it mattered — a reader who opened the table to
check would have found the opposite of what this file claimed about it. Both numbers are corrected
here for that reason alone.

**Not used, because no candidate answers these rows.** That one AVFoundation surface is a Foundation
implementation's own type definitions, and the 33 rows here are `NSString *const` *values* — no
candidate in the table carries them. The values are therefore measured from the host's own framework
instead, and the two Apple-OSS frameworks that could conceivably have carried a header are on the
separate list the coordinator holds, so they were not read and not used.

## The measurement, and what it decided

Each name was resolved as an exported symbol in the **host's own AVFoundation** with
`dlsym(RTLD_DEFAULT, name)` and the `NSString *const` it points at printed, twice: as text and as
bytes, so a value with a non-UTF-8 byte could not be mistaken for a rendering accident. All 33
answered, and **every one is printable ASCII** - no byte above 0x7e - so each decodes byte for byte to
its printed text.

The same table is then read out of two builds and the two diffed, which is what
`tests/backports/host/avf-notifications/run.sh` does: once linked against Apple's framework alone, and
once with the port's four objects in the same binary, every name renamed to `charon_host_<name>`, so
the port's definition and Apple's sit side by side. The port's table is byte-identical to the host's.

**The objects are split by measurement, not by the corpus's `introduced`.** Searching the exports of
every held cache - 4.3, 6.1.3, 7.0, 7.1, 7.1.1, 7.1.2 and 8.0 (armv7), 8.1.3, 8.2 and 8.4.1 (armv7s),
9.3.6 (armv7), 10.0.1, 11.0 and 12.0 (arm64) and 16.0 (arm64e) - for each name's own symbol:

| first held rung that exports it | rows | the object |
| --- | --- | --- |
| 9.3.6 | 1 | `AVFoundationKeys9.m` |
| 11.0 | 1 | `AVFoundationKeys11.m` |
| 16.0 | 27 | `AVFoundationKeys16.m` |
| none of the fifteen | 4 | `AVFoundationKeysUnheld.m` |

The four in the last row are 16.4-era names that no held rung exports, so the port carries them on
every band and they get an object of their own rather than joining the 16.0 one - a band that already
exports the 16.0 names must not find itself holding a mix, which is what `band()` raises on. The two
singles are the same case: `introduced` is corrected to the rung for them, because `carried` is
`introduced <= deployment` and Apple's header annotation is later than its own export.

**23 of the 33 answer their own symbol's name and 10 do not**, and which 10 is a measurement and not a
rule: `AVMediaCharacteristicContainsAlphaChannel` is `public.contains-alpha-channel`,
`AVMediaCharacteristicContainsHDRVideo` is `public.contains-hdr-video`,
`AVMediaCharacteristicIsOriginalContent` is `public.original-content`, the four
`AVPlayerInterstitialEventMonitor...` names drop the monitor's own prefix, and
`AVVideoAppleProRAWBitDepthKey` answers `AppleProRAWBitDepthKey`. An earlier note in these objects
claimed all 33 were their own name; the host says otherwise for those ten and the port follows the
host, which is why the values are read at runtime rather than composed from the symbol.

## The values

| name | value the host answered | first held rung |
| --- | --- | --- |
| `AVAssetDownloadTaskMediaSelectionPrefersMultichannelKey` | `AVAssetDownloadTaskMediaSelectionPrefersMultichannelKey` | 16.0 |
| `AVAssetDownloadTaskMinimumRequiredPresentationSizeKey` | `AVAssetDownloadTaskMinimumRequiredPresentationSizeKey` | 11.0 |
| `AVAssetDownloadTaskPrefersHDRKey` | `AVAssetDownloadTaskPrefersHDRKey` | 16.0 |
| `AVAssetDownloadTaskPrefersLosslessAudioKey` | `AVAssetDownloadTaskPrefersLosslessAudioKey` | 16.0 |
| `AVFragmentedMovieContainsMovieFragmentsDidChangeNotification` | `AVFragmentedMovieContainsMovieFragmentsDidChangeNotification` | 16.0 |
| `AVFragmentedMovieDurationDidChangeNotification` | `AVFragmentedMovieDurationDidChangeNotification` | 16.0 |
| `AVFragmentedMovieTrackSegmentsDidChangeNotification` | `AVFragmentedMovieTrackSegmentsDidChangeNotification` | 16.0 |
| `AVFragmentedMovieTrackTimeRangeDidChangeNotification` | `AVFragmentedMovieTrackTimeRangeDidChangeNotification` | 16.0 |
| `AVFragmentedMovieWasDefragmentedNotification` | `AVFragmentedMovieWasDefragmentedNotification` | 16.0 |
| `AVMediaCharacteristicContainsAlphaChannel` | `public.contains-alpha-channel` | 16.0 |
| `AVMediaCharacteristicContainsHDRVideo` | `public.contains-hdr-video` | 16.0 |
| `AVMediaCharacteristicIsOriginalContent` | `public.original-content` | 16.0 |
| `AVMovieReferenceRestrictionsKey` | `AVMovieReferenceRestrictionsKey` | 16.0 |
| `AVMovieShouldSupportAliasDataReferencesKey` | `AVMovieShouldSupportAliasDataReferencesKey` | 16.0 |
| `AVPlayerEligibleForHDRPlaybackDidChangeNotification` | `AVPlayerEligibleForHDRPlaybackDidChangeNotification` | 16.0 |
| `AVPlayerInterstitialEventMonitorAssetListResponseStatusDidChangeErrorKey` | `AssetListResponseStatusDidChangeErrorKey` | none of the fifteen |
| `AVPlayerInterstitialEventMonitorAssetListResponseStatusDidChangeEventKey` | `AssetListResponseStatusDidChangeEventKey` | none of the fifteen |
| `AVPlayerInterstitialEventMonitorAssetListResponseStatusDidChangeNotification` | `AssetListResponseStatusDidChangeNotification` | none of the fifteen |
| `AVPlayerInterstitialEventMonitorAssetListResponseStatusDidChangeStatusKey` | `AssetListResponseStatusDidChangeStatusKey` | none of the fifteen |
| `AVPlayerInterstitialEventMonitorCurrentEventDidChangeNotification` | `CurrentEventDidChangeNotification` | 16.0 |
| `AVPlayerInterstitialEventMonitorEventsDidChangeNotification` | `EventsDidChangeNotification` | 16.0 |
| `AVPlayerItemMediaSelectionDidChangeNotification` | `AVPlayerItemMediaSelectionDidChangeNotification` | 9.3.6 |
| `AVPlayerItemRecommendedTimeOffsetFromLiveDidChangeNotification` | `AVPlayerItemRecommendedTimeOffsetFromLiveDidChangeNotification` | 16.0 |
| `AVPlayerItemTimeJumpedOriginatingParticipantKey` | `AVPlayerItemTimeJumpedOriginatingParticipantKey` | 16.0 |
| `AVSampleBufferAudioRendererOutputConfigurationDidChangeNotification` | `AVSampleBufferAudioRendererOutputConfigurationDidChangeNotification` | 16.0 |
| `AVSampleBufferDisplayLayerOutputObscuredDueToInsufficientExternalProtectionDidChangeNotification` | `AVSampleBufferDisplayLayerOutputObscuredDueToInsufficientExternalProtectionDidChangeNotification` | 16.0 |
| `AVSampleBufferDisplayLayerRequiresFlushToResumeDecodingDidChangeNotification` | `AVSampleBufferDisplayLayerRequiresFlushToResumeDecodingDidChangeNotification` | 16.0 |
| `AVURLAssetAllowsConstrainedNetworkAccessKey` | `AVURLAssetAllowsConstrainedNetworkAccessKey` | 16.0 |
| `AVURLAssetAllowsExpensiveNetworkAccessKey` | `AVURLAssetAllowsExpensiveNetworkAccessKey` | 16.0 |
| `AVURLAssetHTTPUserAgentKey` | `AVURLAssetHTTPUserAgentKey` | 16.0 |
| `AVURLAssetPrimarySessionIdentifierKey` | `AVURLAssetPrimarySessionIdentifierKey` | 16.0 |
| `AVURLAssetURLRequestAttributionKey` | `AVURLAssetURLRequestAttributionKey` | 16.0 |
| `AVVideoAppleProRAWBitDepthKey` | `AppleProRAWBitDepthKey` | 16.0 |

## What the harness can and cannot settle

It COMPILES the port's sources, LINKS them beside Apple's, and READS the port's object. A name the
port does not define is a **link error**, so a missing constant cannot read as "both sides absent and
therefore equal"; a value that is not valid UTF-8 would print `(null)` on both sides and pass, which
is why the bytes are compared too; and a run that compared nothing fails, because the row count is
asserted on both sides and against the 33 this slice claims.

One value, one byte, in one object, is the mutant and the diff goes red on that row and no other. The
control runs the **unmutated** source through the identical build-and-run path and stays green, so the
red is the mutation and not the path. And a mutation that does not build is `RUN FAILED` with the
compiler's line and exit 1 - a build failure is never counted as a noticed mutation, which is why the
build step and the diff step are separate.
