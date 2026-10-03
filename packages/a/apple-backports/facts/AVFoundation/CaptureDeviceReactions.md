# The capture-device capability rows of iOS 17 and 17.2: 12 rows, two objects

`AVFoundation/AVCaptureDeviceReactions17.m` (the 17.0 half, ten rows) and
`AVFoundation/AVCaptureDeviceFormatDepthZoom17.m` (the 17.2 half, two rows). Registry:
`registry/AVFoundation/reactions17.json`. Header: `CharonAVCaptureDeviceReactions17.h`, which transcribes
26.2's own declarations because SDK 16.4 has no `AVCaptureReactions.h` at all and its `AVCaptureDevice.h`
declares none of this.

## Two oracles, and which one speaks depends on the row

**This host's own AVFoundation, and this Mac has a camera.** Measured: one video device,
`MacBook Pro Camera`, type `AVCaptureDeviceTypeBuiltInWideAngleCamera`, seven formats, 640x480 through
1920x1080. So every row here is something the host answers, and the harness
(`tests/backports/host/avf-capabilities/run.sh`) asks both sides in one process and compares **both columns**
against `expectations.tsv` - what this camera answers and what the port answers, with the reason where the
two differ. "The two columns are equal" is not the claim, because the hardware differs: this camera has
reaction effects, the devices of this port's bands (an iPhone 4S, an iPad 2) have not.

**The SDK 26.2 header's own words for the hardware that does not have the feature**, which is this port's
case. Every rule below is quoted from the header in `AVCaptureDeviceReactions17.m` beside the code that
implements it.

What the host's camera answers, all measured by the harness:

| member | host | port | why they differ |
| --- | --- | --- | --- |
| `availableReactionTypes` | 8 types: Balloons, Confetti, Fireworks, Heart, Lasers, Rain, ThumbsDown, ThumbsUp | none | "The list may differ between devices" (:2481) |
| `canPerformReactionEffects` | 1 | 0 | "returns YES when resources for reactions are available on the device instance" (:2471) |
| `reactionEffectsInProgress` | 0 running | 0 running | they agree |
| `reactionEffectsEnabled` (class) | 1 | 0 with an empty plist, 1 with voip, 1 with the opt-in key | macOS's rule is "enabled by default for all applications" (:2447); iOS's is the application's own (:2448) |
| `reactionEffectGesturesEnabled` (class) | 0 | 1 by default, 0 with `NSCameraReactionEffectGesturesEnabledDefault` false | the host reflects this Mac's Control Center Gestures setting (:2458) |
| `systemPreferredCamera` | nil | nil | they agree: nothing to prefer between on either |
| `userPreferredCamera` | nil until set | nil until set, then what it was given | the host does not answer nil again after a nil is set (measured): a fallback to a system default on a release with several cameras, and there is nothing to fall back to here |
| `performEffectForReaction:` | returned | raises NSInvalidArgumentException | the host's camera has the type in `availableReactionTypes`; this one has none |
| Format `reactionEffectsSupported` | 1 for all seven formats | 0 | hardware |
| Format `videoFrameRateRangeForReactionEffectsInProgress` | a 15-30 `AVFrameRateRange` on all seven | nil | a format runs reactions only where it reports support; the NO case cannot be read off this host, so the pairing is the header's `nullable` |
| Format `supportedVideoZoomRangesForDepthDataDelivery` | 0 ranges | 0 ranges | they agree: this host's camera has no depth sensor either |
| Format `zoomFactorsOutsideOfVideoZoomRangesForDepthDeliverySupported` | 0 | 0 | they agree |

So **four of the twelve rows have the host's own answer identical to the port's**, and the rest differ for a
hardware reason that is stated per row. That is a weaker differential than the controls family, and the
report says so rather than dressing it up: for a reaction effect there is nothing on this machine to measure
the *absence* of, because the only camera available to the host has the feature.

## The two class properties are rules, not constants

`+reactionEffectsEnabled` and `+reactionEffectGesturesEnabled` are read out of the **application's**
`Info.plist`, because that is where the header puts both rules. The harness proves that by running the probe
as a bundle four times over four `Info.plist`s it writes itself - empty, `UIBackgroundModes` = `voip`,
`NSCameraReactionEffectsEnabled` = true, `NSCameraReactionEffectGesturesEnabledDefault` = false - and
**computing the expectation out of the plist each run used**:

```
ok  the empty Info.plist: reactionEffectsEnabled=0, reactionEffectGesturesEnabled=1
ok  the voip Info.plist: reactionEffectsEnabled=1, reactionEffectGesturesEnabled=1
ok  the optin Info.plist: reactionEffectsEnabled=1, reactionEffectGesturesEnabled=1
ok  the gesturesoff Info.plist: reactionEffectsEnabled=0, reactionEffectGesturesEnabled=0
```

A constant cannot pass that, in either direction.

## `-performEffectForReaction:`

The header's rule is exact: "The reactionType requested must be one of those listed in
`availableReactionTypes` or an exception will be thrown" (:2496), and "Performing a reaction when
`canPerformReactionEffects` is NO is ignored" (same line). The list is empty here, so **every** type is one
that must not be passed and the port raises. The header names no exception for it; the port raises
`NSInvalidArgumentException`, which is the name the two unsupported-argument refusals of this host's own class
use (measured: `"*** -[AVCaptureDALDevice setAutoVideoFrameRateEnabled:] Not supported"` and
`"*** -[AVCaptureDeviceInput setMultichannelAudioMode:] Not supported"`). That choice is named here because
it is a choice.

## The bands

Both objects are categories on classes the release carries, so they export no symbol of their own and
`band()` keeps them in every band from the floor up. That is what every category in this package does, and
what the port wants here: from 17.0 up the port's answers are the ones for hardware this port's devices do
not have. (The controls family is the opposite case and says so in its own facts page: there the class object
makes the whole surface drop out of the 18.0 and later bands.)

## Checks

```
sh tests/backports/host/avf-capabilities/run.sh        exit 0
  ok  11 members are answered by both sides
  ok  11 answers are the ones expectations.tsv names, the host's and the port's columns both
  ok  +userPreferredCamera keeps the value it was given and reads it back
  ok  over four Info.plists ... (the four lines above)
AVFCAPSMUTANT=1 sh .../run.sh                          ok  the mutation was noticed: 1 of 11 answers differ
    from the table / DIFFERS AVCaptureDevice.canPerformReactionEffects want port=[0] got port=[1]
CONTROL=1 AVFCAPSMUTANT=1 sh .../run.sh                 ok  the control is clean
```
