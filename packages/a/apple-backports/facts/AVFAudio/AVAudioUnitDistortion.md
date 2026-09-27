# The four AVAudioUnit members that are inert on this release

`AVAudioUnitDistortion.preGain`, `AVAudioUnitDistortion.wetDryMix`,
`AVAudioUnitDistortion.loadFactoryPreset:` and `AVAudioUnitReverb.loadFactoryPreset:` are kept and read
back, and nothing acts on them. The reason is in `AVAudioUnitSubclasses.md`; this file is what the
registry entries point at for those four.

The measurement: iOS 6.1.3's v2 distortion unit publishes fifteen parameters, all out of
`AudioUnitParameters.h` — `kDistortionParam_Delay`, `_Decay`, `_DelayMix`, `_Decimation`, `_Rounding`,
`_DecimationMix`, `_LinearTerm`, `_SquaredTerm`, `_CubicTerm`, `_PolynomialMix`, `_RingModFreq1`,
`_RingModFreq2`, `_RingModBalance`, `_RingModMix`, `_SoftClipGain`, `_FinalMix`. None is a pre-gain,
a wet/dry mix or a preset. Its reverb publishes the `kReverb2Param_*` set and no preset either. All
four members are AudioUnit.framework (v3) properties, and this port's release has no v3 unit.

What a host sees: it sets a value, reads the same value back, and the audio does not change. What it
would see on a release with a v3 distortion unit: the same set and read, and the audio *would*
change. Nothing crashes and nothing is silently wrong — the effect is in the registry entry, next to
the value.
