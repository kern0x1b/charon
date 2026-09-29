# The device-type names, the presets, the codec and matte types — and five that are not strings

The other 39 of the corpus's 72 AVFoundation constant rows, after
[AVFoundationNotificationKeys.md](AVFoundationNotificationKeys.md) took the first 33. Two objects, and
the split of them is the useful part of this slice.

## Five of the thirty-nine are not strings, and the corpus does not say so

`AVCaptureExposureDurationCurrent`, `AVCaptureISOCurrent`, `AVCaptureExposureTargetBiasCurrent`,
`AVCaptureLensPositionCurrent` and `AVCaptureWhiteBalanceGainsCurrent` are `kind: constant` in the
corpus, and the SDK declares **four different types** for them: one `const CMTime`, three `const
float`, and one `const AVCaptureWhiteBalanceGains` struct. **Reading them as `NSString *const` is what
found it** - the first version of this slice's scan took the address `dlsym` answered with, sent
`-UTF8String` to it, and SEGFAULTED.

So `AVCaptureCurrentSentinels8.m` declares them with the types the SDK declares, and the differential
reads each through a pointer typed for it. Their values, read out of the host's own AVFoundation:

    AVCaptureExposureDurationCurrent     CMTime { value 0, timescale 0, flags 0 }   the invalid time
    AVCaptureISOCurrent                 3.40282347e+38   FLT_MAX
    AVCaptureExposureTargetBiasCurrent  3.40282347e+38   FLT_MAX
    AVCaptureLensPositionCurrent        3.40282347e+38   FLT_MAX
    AVCaptureWhiteBalanceGainsCurrent   { redGain 0, blueGain 0 }

The three floats are FLT_MAX, which is what makes them safe to pass: no measured ISO can be that, so a
caller cannot confuse "do not tell me" with a reading. The gains are **zero, which is a real gain
pair** and so is not a safe sentinel - the header's own answer is what is written here rather than
something safer-looking, and the facts file says so.

## Four of the thirty-four strings cannot be named by this host either

`AVCaptureDeviceTypeBuiltInDualWideCamera`, `…TripleCamera`, `…UltraWideCamera` and
`…LiDARDepthCamera` are declared `AVCaptureDeviceType`, which the SDK marks `API_UNAVAILABLE(macos)`,
so a host program cannot take their address at all and a table built from `&name` does not compile
here. The probe reaches them by `dlsym`, and the port build asks for the **renamed** symbol, because
the port's object and Apple's framework define the same name and two definitions would collide at link
time. The row is printed under the real name on both sides, so the four rows compare on their value
and not on which build asked for which symbol.

## The two objects

| first held rung that exports it | rows | the object |
| --- | --- | --- |
| 8.0 | 5 | `AVCaptureCurrentSentinels8.m` |
| 16.0 | 34 | `AVFoundationDeviceTypeAndPresetKeys16.m` |

Measured over every held cache - 4.3, 6.1.3, 7.0, 7.1, 7.1.1, 7.1.2 and 8.0 armv7, 8.1.3, 8.2 and 8.4.1
armv7s, 9.3.6 armv7, 10.0.1, 11.0 and 12.0 arm64, 16.0 arm64e - with `_NSFileSize` planted as a
control, which answers 4.3 on this set.

**20 of the 34 answer their own symbol's name and 14 do not**, and which 14 is a measurement: the
three `AVVideoCodecTypeAppleProRes422*` names are Apple's four-letter codes (`apch`, `apcs`, `apco`),
`AVVideoCodecTypeHEVCWithAlpha` is `muxa`, `AVVideoTransferFunction_Linear` is `Linear`, the
`AVFileTypeProfile` and `AVContentKey*` names are a UTI suffix or a bare key name, and the
`AVPlayerInterstitialEvent*` cue names drop their prefix. An earlier note claimed all of them were
their own name; the host says otherwise and the port follows the host, which is the reason every
value here is read at runtime rather than composed from the symbol.

## The values

| name | value the host answered | first held rung |
| --- | --- | --- |
| `AVAssetExportPresetAppleProRes422LPCM` | `AVAssetExportPresetAppleProRes422LPCM` | 16.0 |
| `AVAssetExportPresetAppleProRes4444LPCM` | `AVAssetExportPresetAppleProRes4444LPCM` | 16.0 |
| `AVAssetExportPresetHEVC1920x1080WithAlpha` | `AVAssetExportPresetHEVC1920x1080WithAlpha` | 16.0 |
| `AVAssetExportPresetHEVC3840x2160WithAlpha` | `AVAssetExportPresetHEVC3840x2160WithAlpha` | 16.0 |
| `AVAssetExportPresetHEVCHighestQualityWithAlpha` | `AVAssetExportPresetHEVCHighestQualityWithAlpha` | 16.0 |
| `AVAssetPlaybackConfigurationOptionStereoMultiviewVideo` | `AVAssetPlaybackConfigurationOptionStereoMultiviewVideo` | 16.0 |
| `AVAssetPlaybackConfigurationOptionStereoVideo` | `AVAssetPlaybackConfigurationOptionStereoVideo` | 16.0 |
| `AVCaptureDeviceTypeBuiltInDualWideCamera` | `AVCaptureDeviceTypeBuiltInDualWideCamera` | 16.0 |
| `AVCaptureDeviceTypeBuiltInLiDARDepthCamera` | `AVCaptureDeviceTypeBuiltInLiDARDepthCamera` | 16.0 |
| `AVCaptureDeviceTypeBuiltInTripleCamera` | `AVCaptureDeviceTypeBuiltInTripleCamera` | 16.0 |
| `AVCaptureDeviceTypeBuiltInUltraWideCamera` | `AVCaptureDeviceTypeBuiltInUltraWideCamera` | 16.0 |
| `AVCaptureExposureDurationCurrent` | `(a sentinel)` | 8.0 |
| `AVCaptureExposureTargetBiasCurrent` | `(a sentinel)` | 8.0 |
| `AVCaptureISOCurrent` | `(a sentinel)` | 8.0 |
| `AVCaptureLensPositionCurrent` | `(a sentinel)` | 8.0 |
| `AVCaptureWhiteBalanceGainsCurrent` | `(a sentinel)` | 8.0 |
| `AVContentKeyRequestRequiresValidationDataInSecureTokenKey` | `RequiresValidationDataInSecureTokenKey` | 16.0 |
| `AVContentKeySessionServerPlaybackContextOptionProtocolVersions` | `ProtocolVersionsKey` | 16.0 |
| `AVContentKeySessionServerPlaybackContextOptionServerChallenge` | `ServerChallenge` | 16.0 |
| `AVContentKeySystemAuthorizationToken` | `AuthorizationTokenSystem` | 16.0 |
| `AVFileTypeProfileMPEG4AppleHLS` | `MPEG4AppleHLS` | 16.0 |
| `AVFileTypeProfileMPEG4CMAFCompliant` | `MPEG4CMAFCompliant` | 16.0 |
| `AVOutputSettingsPresetHEVC1920x1080WithAlpha` | `AVOutputSettingsPresetHEVC1920x1080WithAlpha` | 16.0 |
| `AVOutputSettingsPresetHEVC3840x2160WithAlpha` | `AVOutputSettingsPresetHEVC3840x2160WithAlpha` | 16.0 |
| `AVPlayerInterstitialEventJoinCue` | `EventJoinCue` | 16.0 |
| `AVPlayerInterstitialEventLeaveCue` | `EventLeaveCue` | 16.0 |
| `AVPlayerInterstitialEventNoCue` | `EventNoCue` | 16.0 |
| `AVSemanticSegmentationMatteTypeGlasses` | `AVSemanticSegmentationMatteTypeGlasses` | 16.0 |
| `AVSemanticSegmentationMatteTypeHair` | `AVSemanticSegmentationMatteTypeHair` | 16.0 |
| `AVSemanticSegmentationMatteTypeSkin` | `AVSemanticSegmentationMatteTypeSkin` | 16.0 |
| `AVSemanticSegmentationMatteTypeTeeth` | `AVSemanticSegmentationMatteTypeTeeth` | 16.0 |
| `AVVideoCodecTypeAppleProRes422HQ` | `apch` | 16.0 |
| `AVVideoCodecTypeAppleProRes422LT` | `apcs` | 16.0 |
| `AVVideoCodecTypeAppleProRes422Proxy` | `apco` | 16.0 |
| `AVVideoCodecTypeHEVCWithAlpha` | `muxa` | 16.0 |
| `AVVideoRangeHLG` | `AVVideoRangeHLG` | 16.0 |
| `AVVideoRangePQ` | `AVVideoRangePQ` | 16.0 |
| `AVVideoRangeSDR` | `AVVideoRangeSDR` | 16.0 |
| `AVVideoTransferFunction_Linear` | `Linear` | 16.0 |
