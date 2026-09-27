# AVAudioEnvironmentNode and its two parameter classes

Carried in `libAVFAudioBackports.dylib` (the `avfaudio` config), in `AVAudioEnvironmentNode8.m`. The
base class `AVAudioNode` is carried in `libAVFoundationBackports.dylib`, which this library links.

## The unit is the release's own

`kAudioUnitSubType_SpatialMixer` — the SDK's name for `kAudioUnitSubType_AU3DMixerEmbedded`, the same
value, which the SDK deprecates only as a spelling. The evidence that the unit is really there is its
own parameter set in **the release's** `AudioToolbox/AudioUnitParameters.h`, marked iOS 2.0 and
thirty-odd entries long: `k3DMixerParam_Azimuth`, `_Elevation`, `_Distance`, `_Gain`, `_PlaybackRate`,
`_BusEnable`, `_MinGainInDecibels`, `_MaxGainInDecibels`, `_DryWetReverbBlend`,
`_GlobalReverbGainInDecibels`, `_OcclusionAttenuationInDecibels`,
`_ObstructionAttenuationInDecibels`, and the deprecated originals of each. A parameter set that size
only exists if the unit does.

The node carries a **graph of its own** — the mixer terminated into a `kAudioUnitSubType_GenericOutput`
— built with the release's own `NewAUGraph` / `AUGraphOpen` / `AUGraphAddNode` /
`AUGraphConnectNodeInput` / `AUGraphNodeInfo`, and initialized with `AUGraphInitialize` on the first
render rather than in `-init`, because a unit needs its formats first. It is there so the node can be
rendered offline with no engine at all, which is what makes its own output measurable.

## The coordinate model is the mixer's, not a translation of it

A bus's parameters are that source's azimuth, elevation, distance and gain **relative to a listener at
the mixer's origin**. `AVAudioEnvironmentNode` exposes the listener as a position, which is the same
statement read the other way round: moving the listener is the inverse transform applied to every
source. The port applies the former because that is the property the header exposes, and the
arithmetic is exact rather than fitted — a rigid transform and its inverse compose to the identity on
the positions the mixer is already given, and the listener's basis is orthonormal because its forward
vector is normalised and its up vector comes from the listener's own yaw and pitch.

## The only arithmetic the port does that the unit does not

The **distance attenuation model**. The header defines three laws — linear stops attenuating at
`maximumDistance`, exponential falls off by `rolloffFactor`, inverse is the reciprocal in units of
`referenceDistance` — and the mixer's own parameters for a source are a distance and a gain, so the
model is applied to the gain and the distance the unit is given. The unit still renders; the port only
decides the gain, which is exactly the parameter it has. The three laws are written out in
`-charon_gainForDistance:` from the header's own documentation, with the documented defaults (inverse
model, 1 m reference, 100000 m maximum, rolloff 1).

## What this unit cannot be

**The applicable rendering algorithms are the sound field and the stereo pass-through, and that is the
whole of what it is.** The mixer places a source in a sphere around the listener and sums the buses; it
has no head-related transfer function, and nothing in its thirty-odd parameters says where a listener's
ears are. So `AVAudio3DMixingRenderingAlgorithmHRTF`, `...HRTFHQ`, `...EqualPowerPanning` and
`...SphericalHead` are **not applicable** — they are absent from `applicableRenderingAlgorithms`, and
setting one leaves the unit where it is rather than quietly behaving like the sound field. The
algorithms that need an ear model need audio this device does not have, and saying so is the honest
answer, not a substitute.

## Two answers the release cannot give

- **`reverbParameters.filterParameters` is `nil`.** The header names an `AVAudioUnitEQFilterParameters`
  — a band of a unit — and this release's environment reverb is the mixer's own
  `DryWetReverbBlend` and `GlobalReverbGain`, with no filter of its own. nil is the header's own
  optional answer; a synthesised filter would be a band of nothing.
- **`loadFactoryPreset:` keeps its value and acts on nothing.** The mixer of this release has no factory
  presets and no preset parameter. Same answer and the same reason as `AVAudioUnitDistortion`'s and
  `AVAudioUnitReverb`'s, which are written up in `AVAudioUnitDistortion.md`.
- **`outputType` answers `AVAudioEnvironmentOutputTypeAuto`**, the header's own first case: the
  mixer's output is a single bus and the release names no output device behind it, so nothing on this
  release distinguishes built-in speakers from headphones.

## Not yet measured here

The environment node's own offline pull — `-charon_renderOfflineToBuffer:frames:`, the release's
`AudioUnitRender` on its real generic output — is the hook the manual-rendering differential in
`AVAudioEngine.m` uses. The sample-by-sample comparison against macOS is the next piece of work and is
not in this delivery.
