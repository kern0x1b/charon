# AVAudioUnitSampler

Carried in `libAVFAudioBackports.dylib` (the `avfaudio` config), in `AVAudioUnitSampler8.m`, over the
release's own sampler.

## The measurement, from the guest

`tests/backports/device/sampler-probe` on the emulated **iPhone2,1 6.1.3 (10B329)**, verbatim from
`run/run.log` and `run/guest.log`:

```
probe: AudioComponentCount = 55
probe: minimum = 6.1.3
MusicDevice/Sampler/Apple: found, name=Apple: AUSampler type=0x61656d75 subtype=0x73616d70 manufacturer=0x6170706c version=0x10000
'aumu'/'samp'/any: found, name=Apple: AUSampler type=0x61656d75 subtype=0x73616d70 manufacturer=0x6170706c version=0x10000
anyType/Sampler/any: found, name=Apple: AUSampler type=0x61656d75 subtype=0x73616d70 manufacturer=0x6170706c version=0x10000
...
component 48: type=0x61656d75 subtype=0x73616d70 manufacturer=0x6170706c name=Apple: AUSampler
component 49: type=0x61756d78 subtype=0x3364656d manufacturer=0x6170706c name=Apple: AU3DMixerEmbedded
...
pass on iPhone2,1 6.1.3 (10B329) in 0.3 guest s / 24.6 host s at time scale 10
```

**iOS 6.1.3 carries the Apple sampler**, as a registered audio component: type `'aumu'`, subtype
`'samp'`, manufacturer `'appl'`, version `0x10000`, named `Apple: AUSampler`, and it is entry 48 of the
55 the release registers. All three of the probe's queries agree, and the whole-list walk finds it
independently, so it is not one lookup's answer.

**The same run confirms the environment node's substrate**: component 49 is
`Apple: AU3DMixerEmbedded` — type `'xmud'`, subtype `'med3'` — which is what
`AVAudioEnvironmentNode8.m` is built on.

This corrects what the band reported twice before that a cache grep could not settle. A component is a
*registration* and not an exported symbol, so the absence of a `Sampler` symbol among the 580
libraries of the armv7 6.1.3 cache was never evidence about the sampler either way — as
`facts/AVFAudio/AVAudioUnitMIDI.md` says. The only answer is the release's own registry, and the guest
has now given it.

## What the class is built on

`AVAudioUnitSampler` derives from `AVAudioUnitMIDIInstrument` in the header
(`AVAudioUnitSampler.h:23`), which is why its initializer asks the generator family for a
`kAudioUnitType_MusicDevice` / `kAudioUnitSubType_Sampler` unit.

- **`loadSoundBankInstrumentAtURL:program:bankMSB:bankLSB:error:`** and
  **`loadInstrumentAtURL:error:`** are the release's own `kAUSamplerProperty_LoadInstrument`
  (`AudioUnitProperties.h:3636`, Scope Global, Value Type `AUSamplerInstrumentData`, Access Write;
  the id is `:3651`). That struct is the release's own layout: a `CFURLRef`, an `instrumentType`, a
  `bankMSB`, a `bankLSB` and a `presetID` — the five things the method takes. A sound bank is an SF2,
  so the instrument type is `kInstrumentType_SF2Preset`; the header's enumeration has no member
  called "SoundBank", and using one would have been a name the release does not have.
- **`loadAudioFilesAtURLs:error:`** is the release's second property,
  `kAUSamplerProperty_LoadAudioFiles` (`:3639`, Value Type `CFArrayRef`, Access Write; id `:3652`).
  One file is that array of one; an empty list is refused with an error rather than answered as a
  load of nothing.
- A refused load is reported with the status the release returned, never as a load that quietly did
  nothing.
- `globalTuning`, `masterGain`, `overallGain` and `stereoPan` are the sampler's own state on this
  port, held and read back.

## What is not carried, and why

The note-control half of the header — `startNote:velocity:channel:`, `stopNote:channel:`, `reset` and
their kin — is **not** implemented here. Those are the sampler's instrument interface, and the
release's property set does not name one for them; the corpus carries no row for any of them on
`AVAudioUnitSampler` (its seven rows are the class, three load methods and four gain properties), so
nothing is claimed for them. A caller that sends one gets an unrecognised selector, which is what an
unimplemented member is, and the header's own contract for a caller — check `respondsToSelector:` —
still holds.

## Reuse

searched: none. This is a property write and a struct layout the release defines;
there is no sampler or synthesis to vendor, and Resonance Audio and Steam Audio (both Apache-2.0)
carry DSP the release's own unit already has.
