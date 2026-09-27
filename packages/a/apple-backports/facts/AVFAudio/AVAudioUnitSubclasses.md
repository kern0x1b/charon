# The AVAudioUnit effect subclasses of iOS 8

Carried in `libAVFAudioBackports.dylib` (the `avfaudio` config), in `AVAudioUnitSubclasses8.m`. The
base classes — `AVAudioUnit`, `AVAudioUnitEffect`, `AVAudioNode`, `AVAudioEngine` — are carried in
`libAVFoundationBackports.dylib`, which this library links; none of their files is edited here.

## What each of these is

A **description of one of the release's own built-in units** plus **a set of the release's own
parameters**. Every subtype and every parameter id is out of `AudioUnitParameters.h` of the release:

| class | subtype | parameters |
| --- | --- | --- |
| `AVAudioUnitDelay` | `kAudioUnitSubType_Delay` | `kDelayParam_DelayTime`, `kDelayParam_Feedback`, `kDelayParam_LopassCutoff`, `kDelayParam_WetDryMix` |
| `AVAudioUnitVarispeed` | `kAudioUnitSubType_Varispeed` | `kVarispeedParam_PlaybackRate` |
| `AVAudioUnitTimePitch` | `kAudioUnitSubType_TimePitch` | `kTimePitchParam_Rate`, `kTimePitchParam_Pitch`, `kTimePitchParam_EffectBlend` |
| `AVAudioUnitReverb` | iOS's own reverb | `kReverb2Param_DryWetMix` |

A value set is an `AudioUnitSetParameter` on the real unit, so it changes what the release's unit
renders. A value read is an `AudioUnitGetParameter`. A value set before the node is attached is kept
and applied when the real `AudioUnit` arrives, which is the base class's own
`-charon_applyPendingParameters` — the same arrangement `AVAudioUnitEQ` already uses.

**`AVAudioUnitReverb` uses `kReverb2Param_*`, not `kReverbParam_*`.** iOS's reverb unit is a different
unit from the desktop one and carries a different parameter set: `AudioUnitParameters.h` has the
desktop `kReverbParam_*` under one heading and `kReverb2Param_*` under "Parameters for the iOS reverb
unit". Only the second exists on a release of this port, and using the first would be a parameter
id the unit does not have.

## The three that are `inert`, and why

`AVAudioUnitDistortion.preGain`, `AVAudioUnitDistortion.wetDryMix`,
`AVAudioUnitDistortion.loadFactoryPreset:` and `AVAudioUnitReverb.loadFactoryPreset:` are kept and read
back, and **nothing acts on them**. The reason is measured, not guessed: iOS 6.1.3's v2 distortion unit
has fifteen parameters — `kDistortionParam_Delay`, `_Decay`, `_DelayMix`, `_Decimation`, `_Rounding`,
`_DecimationMix`, `_LinearTerm`, `_SquaredTerm`, `_CubicTerm`, `_PolynomialMix`, `_RingModFreq1`,
`_RingModFreq2`, `_RingModBalance`, `_RingModMix`, `_SoftClipGain` and `_FinalMix` — and neither
`PreGain` nor `WetDryMix` nor any preset is among them. Its reverb carries the `kReverb2Param_*` set
and no preset either. `preGain` and `wetDryMix` are v3 members of the AudioUnit.framework units, and
`loadFactoryPreset:` is v3 with it.

Mapping either property onto one of the fifteen would be a claim the release cannot back, so they are
`inert`: a value a host can set before the node is rendered and read back afterwards, which changes
no audio on this release. That is the registry's `inert` status and not a silent fake; the effect and
the reason are in `registry/AVFAudio/iosaudiounitsubclasses8.json`.

## Not carried, and why

`AVAudioUnitMIDIInstrument` and `AVAudioUnitSampler` are **not** in this delivery, and the reason is
the same for both and is a measurement:

- **iOS 6.1.3 exports no function that sends a MIDI event to an audio unit.** Its AudioToolbox
  `AudioUnit` family is the twenty-seven functions enumerated in `facts/AVFAudio/AUAudioUnit.md` and
  none of them is a MIDI send; there is no `AudioUnitSendMIDIEvent` and no `AUGraphSendMIDIEvent`. The
  path a MIDI instrument has on this release is `MusicSequence` and `MusicPlayer`, which it *does*
  export in full (`MusicSequenceNewTrack`, `MusicSequenceSetUserCallback`, `MusicPlayerStart`, the
  `MusicSequenceFile*` family), and that is the sequencer family's to build.
- **iOS 6.1.3 carries no sampler component.** The Apple sampler is a system dynamic library the
  release loads on demand, not a unit in the shared cache, so there is no component for
  `kAudioUnitSubType_Sampler` to instantiate and `loadSoundBankInstrumentAtURL:…` would have nothing
  to load into.

Writing the note methods as a queue nothing drains, or answering a load as having succeeded, is
exactly the silent fake `COORDINATION` §2 forbids. They wait for the sequencer family.
`facts/AVFAudio/AVAudioUnitMIDI.md` records it.

Also not carried here: `AVAudioEnvironmentNode` and its two parameter classes, `AVAudioSourceNode`,
`AVAudioSinkNode` and `AVAudioMixingDestination` — the environment node and the mixing destination
need a real environment unit and the engine's mixer, which is the next family, and the two node
classes need a render block on the release's own `AUGraphSetNodeInputCallback` path, which is the
engine's business.
