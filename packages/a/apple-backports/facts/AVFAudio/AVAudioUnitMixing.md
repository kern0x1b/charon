# bypass, AVAudioMixing, and AVAudioMixingDestination

Carried in `libAVFAudioBackports.dylib` (the `avfaudio` config), in `AVAudioUnitMixing9.m`, as a
**category on `AVAudioUnit`** plus the `AVAudioMixingDestination` class.

## Why the base, and why a category in this folder

`-bypass` and the eleven `AVAudioMixing` members belong on `AVAudioUnit`, which is where Apple's own
hierarchy puts them: `AVAudioUnitTimeEffect.h:38` and `AVAudioUnitGenerator.h:39` both declare
`bypass` and both classes derive from `AVAudioUnit`, and `AVAudioUnitGenerator.h:22` declares
`AVAudioMixing`. The port had `bypass` on `AVAudioUnitEffect`, one level too low, so
`timeEffect.bypass = YES` and `generator.volume = 0.0` raised `unrecognized selector:` — a class
row saying `implemented` while the class could not do the one thing it exists for.

They are a category in **this** library's folder rather than an edit to `AVFoundation/AVAudioUnit.m`,
so no file of the AVFoundation band's is touched, and no ivar is needed: every value is the unit's own
property, read and written on the unit.

## The values are the release's own

`kAudioUnitProperty_BypassEffect` — the property the port's `AVAudioUnitEffect` already used and the
one Apple's header names for the pair. The mixing members are the **mixer's `k3DMixerParam_` set**,
which the release's `AudioToolbox/AudioUnitParameters.h` carries since iOS 2.0 — azimuth, elevation,
distance, gain, playback rate, bus enable, reverb blend, global reverb gain, occlusion and obstruction
attenuation — asked of the unit's **input scope, element 0**, which is this node's own source.

- `volume` is `k3DMixerParam_Gain`; `rate` is `k3DMixerParam_PlaybackRate`;
  `reverbBlend` is `k3DMixerParam_ReverbBlend` over 0–100; `occlusion` and `obstruction` are their own
  attenuation parameters.
- `pan` is `k3DMixerParam_Azimuth` over −180…180 degrees, because the header's pan is −1…+1 and the
  azimuth is the same angle at a different scale.
- `position` is the spherical form of azimuth, elevation and distance, and setting it is the inverse of
  reading it — exact, since the mixer's three numbers and a point in space are one statement.
- A unit that is not a mixer has none of these parameters, and `AudioUnitGetParameter` leaves the value
  at zero, which is what the gain-like members then answer. A refused set is **checked** now and said
  once per member and unit through the log note, which is the fourth review finding's second half.

## What the release's parameters cannot express, and what is said instead

`sourceMode` answers `AVAudio3DMixingSourceModePointSource` and setting it changes nothing: the
release's mixer places every source as a point in a sphere, and that is the point source mode and the
only one its parameter set can express. `pointSourceInHeadMode` answers `...Mono` for the same reason.
Neither is faked as something else.

`renderingAlgorithm` is the one this port can honour in both directions, because the mixer's own
parameters have placement on or off and nothing else: the sound field and the stereo pass-through map
onto `k3DMixerParam_Enable`, and the two algorithms that need an ear model leave it where it is rather
than being answered as the sound field.

## AVAudioMixingDestination

The header's own class, and the header's own contract is honoured: a reference "could become invalid
when there is any disconnection between the source and the mixer node ... should not be retained and
should be fetched every time you want to set/get properties on it". So `-destinationForMixer:bus:`
answers a **fresh** object over the pair asked for, and its values are the source node's — read and
written through the node as an `AVAudioMixing`, which is the protocol that declares them. A nil mixer
answers nil.

## `-[AVAudioUnitBus setLatency:]` is `absent`

The header's `AudioUnitProperties.h` marks `kAudioUnitProperty_Latency` **`Access: Read`**, and a
conforming unit refuses a set: measured against a real host `AudioUnit` in
`tests/backports/host/avfaudio/`, `AudioUnitSetProperty(kAudioUnitProperty_Latency, …)` returns
`kAudioUnitErr_InvalidProperty` (−10879) and the read-back is unchanged. So the member is `absent`
with that as its reason — calling it raises an unrecognised selector, which is what `absent` means —
rather than `implemented` with a body that provably does nothing. The bus's `latency` is read, as
`Float64`, which is the header's own value type for it.

## Reuse

**searched: none.** The queries were `AVAudioUnit`, `AUParameterTree` and `AVAudioMixing` on GitHub
repository search; the permissive results are sample applications and a macOS-only Rust binding crate,
none of which re-implements Apple's classes — they call the same AudioUnit C API this calls. Nothing
from Resonance Audio or Steam Audio (both Apache-2.0) is taken: the three distance models are three
closed forms and the mixer already applies the result as its own gain. OpenAL Soft is LGPL and was not
read.
